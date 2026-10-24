import Foundation
import FoundationModels
import LiteRTLM
import Synchronization
import os

/// Gemma 4 E4B, run on this device by LiteRT-LM, behind Apple's `LanguageModel`
/// protocol — so every page drives it with a stock `LanguageModelSession`, and
/// going back to Apple's model is a change to `OnDeviceModel.languageModel`.
///
/// It follows the shape of LiteRT-LM's own Foundation Models adapter
/// (`LiteRTLanguageModel`, in swift/apple_fm of the LiteRT-LM repository): the
/// transcript is rebuilt into a fresh LiteRT `Conversation` on every turn,
/// guided generation is a JSON schema the decoder is constrained to, and tools
/// are described in the system prompt and called with a small JSON envelope.
/// What it adds is what that adapter leaves out:
///
/// - Thinking. Every turn runs with Gemma's thinking channel on, and the
///   thoughts stream into the transcript as `.reasoning` entries, and live to
///   `ModelActivity` for the pages to show while the model works.
/// - Speculative decoding, through the drafter bundled in the model file, on
///   every turn whose output isn't held to a schema.
/// - A required tool call held to by constrained decoding, structured tool
///   output reaching the model as JSON instead of being dropped, and optional
///   schema fields written as explicit nulls.
nonisolated struct GemmaLanguageModel: LanguageModel {
    typealias Executor = GemmaExecutor

    let capabilities = LanguageModelCapabilities([.guidedGeneration, .toolCalling, .reasoning])
    let executorConfiguration: GemmaExecutor.Configuration

    /// - Parameters:
    ///   - modelPath: The `.litertlm` file on disk.
    ///   - contextSize: Prompt and output tokens together, which is the size of
    ///     the KV cache the engine allocates.
    ///   - thinkingTokenBudget: The most a turn may spend thinking before the
    ///     decoder closes the thought and moves on to the answer.
    ///   - speculativeDecoding: Whether turns whose output isn't held to a
    ///     schema decode with the drafter. Turns that are held to one never do.
    init(
        modelPath: String,
        contextSize: Int = 8192,
        thinkingTokenBudget: Int = 1024,
        speculativeDecoding: Bool = true
    ) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        // EngineConfig only throws for a context size of zero or less.
        let engineConfig = try! EngineConfig(
            modelPath: modelPath,
            backend: .gpu,
            maxNumTokens: contextSize,
            cacheDir: caches?.path
        )
        executorConfiguration = GemmaExecutor.Configuration(
            engineConfig: engineConfig,
            thinkingTokenBudget: thinkingTokenBudget,
            speculativeDecoding: speculativeDecoding
        )
    }
}

enum GemmaError: LocalizedError {
    case modelMissing
    case noPrompt

    var errorDescription: String? {
        switch self {
        case .modelMissing: "The Gemma model file hasn't been downloaded to this device."
        case .noPrompt: "The transcript holds nothing for the model to respond to."
        }
    }
}

// MARK: - Executor

nonisolated final class GemmaExecutor: LanguageModelExecutor {
    typealias Model = GemmaLanguageModel

    /// What engine to build, and how hard to think. Foundation Models wants a
    /// hashable value here rather than a live engine, so the engine itself is
    /// looked up from `GemmaEngine.shared(for:)`.
    struct Configuration: Hashable, Sendable {
        let engineConfig: EngineConfig
        let thinkingTokenBudget: Int
        let speculativeDecoding: Bool
    }

    private let configuration: Configuration
    private let engine: GemmaEngine

    init(configuration: Configuration) throws {
        self.configuration = configuration
        self.engine = GemmaEngine.shared(for: configuration.engineConfig)
    }

    /// Loads the weights. There is nothing worth prefilling ahead of time,
    /// since every turn starts a conversation of its own.
    func prewarm(model: GemmaLanguageModel, transcript: Transcript) {
        let engine = engine
        Task { _ = try? await engine.ready() }
    }

    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: GemmaLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let loaded = try await engine.ready()
        await engine.acquire()
        do {
            try await generate(request, on: loaded, into: channel)
            await engine.release()
        } catch {
            await engine.release()
            throw error
        }
    }

    private func generate(
        _ request: LanguageModelExecutorGenerationRequest,
        on engine: Engine,
        into channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let toolCallingMode = request.generationOptions.toolCallingMode
        let tools = toolCallingMode == .disallowed ? [] : request.enabledToolDefinitions
        let mustCallTool = !tools.isEmpty && toolCallingMode == .required
        let schema = try request.schema.map(SchemaJSON.init)
        let schemaInPrompt = tools.isEmpty && request.contextOptions.includeSchemaInPrompt != false
            ? schema : nil

        let turn = try Turn(
            transcript: request.transcript,
            tools: tools,
            mustCallTool: mustCallTool,
            schema: schemaInPrompt
        )

        // Prose with no tool in play streams straight onto the page. JSON — a
        // guided answer or a tool call — is held back until it is whole.
        let streamsText = tools.isEmpty && schema == nil
        // With tools merely allowed, the model may answer in prose instead of
        // calling one, so there is nothing to hold its output to.
        let constraint: String? = if mustCallTool {
            try SchemaJSON.toolCall(tools).text
        } else if tools.isEmpty {
            schema?.text
        } else {
            nil
        }

        // Structured output is written freely first, with speculative
        // decoding, and only rewritten under llguidance when it wouldn't
        // decode. The constraint has two costs in LiteRT-LM 0.18.1: it can't
        // run with speculation (drafted tokens slip past the grammar and the
        // JSON dissolves into whitespace), and it masks some of Gemma's
        // tokens at value boundaries, so a merchant the model named in its
        // thinking comes out as `null`. Free JSON keeps every value the model
        // meant but now and then leaves out a key or writes Gemma's own tool
        // call syntax — which is what the constrained pass is for.
        var pass = try await decode(
            turn,
            request: request,
            on: engine,
            constraint: nil,
            speculative: configuration.speculativeDecoding,
            streamingTextInto: streamsText ? channel : nil
        )
        var retried = false
        if let constraint, !Self.decodes(pass.text, tools: tools, mustCallTool: mustCallTool, schema: schema) {
            Self.logger.notice("Free JSON didn't fit the schema; retrying under llguidance. Got: \(pass.text, privacy: .public)")
            let freePass = pass
            pass = try await decode(
                turn,
                request: request,
                on: engine,
                constraint: constraint,
                speculative: false,
                streamingTextInto: nil
            )
            pass.usage.add(freePass.usage)
            retried = true
        }
        pass.usage.retriedUnderConstraint = retried

        if !streamsText, !pass.thought.isEmpty {
            await channel.send(.reasoning(action: .appendText(pass.thought, tokenCount: pass.usage.reasoningTokens)))
        }

        if !tools.isEmpty, let call = Self.toolCall(in: pass.text, tools: tools) {
            await channel.send(.toolCalls(action: .toolCall(
                id: UUID().uuidString,
                name: call.name,
                action: .appendArguments(call.arguments, tokenCount: pass.usage.textTokens)
            )))
            await channel.send(.toolCalls(action: .updateUsage(
                input: pass.usage.input, output: pass.usage.output, metadata: pass.usage.metadata
            )))
            return
        }

        if !streamsText {
            let reply = schema == nil ? pass.text : (SchemaJSON.firstObject(in: pass.text) ?? pass.text)
            await channel.send(.response(action: .appendText(reply, tokenCount: pass.usage.textTokens)))
        }
        await channel.send(.response(action: .updateUsage(
            input: pass.usage.input, output: pass.usage.output, metadata: pass.usage.metadata
        )))
    }

    /// One generation: what the model thought, what it wrote, and the cost.
    private struct Pass {
        var thought = ""
        var text = ""
        var usage: Usage
    }

    /// Runs the turn once in a fresh conversation.
    ///
    /// The thinking is reported live to `ModelActivity` as it streams; it
    /// reaches the transcript through `channel` only for prose, just before
    /// the first word of the answer, so that a structured pass the caller
    /// throws away leaves no thinking behind.
    private func decode(
        _ turn: Turn,
        request: LanguageModelExecutorGenerationRequest,
        on engine: Engine,
        constraint: String?,
        speculative: Bool,
        streamingTextInto channel: LanguageModelExecutorGenerationChannel?
    ) async throws -> Pass {
        let thinking = ThinkingConfig(
            enableThinking: true,
            thinkingTokenBudget: configuration.thinkingTokenBudget
        )
        let conversation = try await engine.createConversation(with: ConversationConfig(
            systemMessage: turn.system,
            initialMessages: turn.history,
            samplerConfig: Self.sampler(for: request.generationOptions),
            thinkingConfig: thinking,
            enableResponseFormat: constraint != nil,
            enableSpeculativeDecoding: speculative
        ))
        let responseFormat = try constraint.map { try ResponseFormat.json(schema: $0) }

        var thought = ""
        var text = ""
        var thoughtSent = false
        await ModelActivity.shared.beginTurn()

        let stream = conversation.sendMessageStream(
            turn.prompt,
            // A turn that loses its way stops here rather than at the end
            // of the context window.
            maxOutputTokens: request.generationOptions.maximumResponseTokens
                ?? configuration.thinkingTokenBudget + Self.answerTokenLimit,
            thinkingConfig: thinking,
            responseFormat: responseFormat
        )
        do {
            try await withTaskCancellationHandler {
                for try await chunk in stream {
                    // Gemma 4 has one channel, the thought channel.
                    let thinkingDelta = chunk.channels.values.joined()
                    if !thinkingDelta.isEmpty {
                        thought += thinkingDelta
                        await ModelActivity.shared.think(thinkingDelta)
                    }
                    let delta = chunk.toString
                    if !delta.isEmpty {
                        text += delta
                        await ModelActivity.shared.endThinking()
                        if let channel {
                            if !thoughtSent, !thought.isEmpty {
                                await channel.send(.reasoning(action: .appendText(thought, tokenCount: 1)))
                            }
                            thoughtSent = true
                            await channel.send(.response(action: .appendText(delta, tokenCount: 1)))
                        }
                    }
                }
            } onCancel: {
                try? conversation.cancel()
            }
            await ModelActivity.shared.endThinking()
        } catch {
            await ModelActivity.shared.endThinking()
            throw error
        }
        try Task.checkCancellation()
        if let channel, !thoughtSent, !thought.isEmpty {
            await channel.send(.reasoning(action: .appendText(thought, tokenCount: 1)))
        }

        return Pass(
            thought: thought,
            text: text,
            usage: Usage(
                conversation: conversation,
                thoughtLength: thought.count,
                textLength: text.count,
                speculated: speculative
            )
        )
    }

    /// Whether structured output will decode as what was asked for: a call
    /// to a tool on offer with arguments that fit its schema, or a JSON object
    /// that fits the response schema.
    private static func decodes(
        _ text: String,
        tools: [Transcript.ToolDefinition],
        mustCallTool: Bool,
        schema: SchemaJSON?
    ) -> Bool {
        if mustCallTool {
            guard let call = toolCall(in: text, tools: tools),
                  let tool = tools.first(where: { $0.name == call.name }),
                  let parameters = try? SchemaJSON(tool.parameters)
            else { return false }
            return parameters.accepts(call.arguments)
        }
        guard let schema else { return true }
        return SchemaJSON.firstObject(in: text).map(schema.accepts) ?? false
    }

    private static let logger = Logger(subsystem: "FM-Playground", category: "Gemma")

    /// Room for the answer after the thinking budget: far more than any page
    /// needs, far less than a runaway would take.
    private static let answerTokenLimit = 2048

    /// Foundation Models' sampling options in LiteRT terms. Left unset, the
    /// engine's own defaults for the model apply.
    private static func sampler(for options: GenerationOptions) -> SamplerConfig? {
        let temperature = Float(options.temperature ?? 1)
        switch options.samplingMode?.kind {
        case .greedy:
            return try? SamplerConfig(topK: 1, topP: 1, temperature: 0)
        case .randomTopK(let k, let seed):
            return try? SamplerConfig(
                topK: k, topP: 1, temperature: temperature,
                seed: Int(truncatingIfNeeded: seed ?? 0)
            )
        case .randomProbabilityThreshold(let threshold, let seed):
            return try? SamplerConfig(
                topK: 64, topP: Float(threshold), temperature: temperature,
                seed: Int(truncatingIfNeeded: seed ?? 0)
            )
        case nil:
            return options.temperature.flatMap { _ in
                try? SamplerConfig(topK: 64, topP: 0.95, temperature: temperature)
            }
        @unknown default:
            return nil
        }
    }

    /// The call in `{"tool_call": {"name": …, "arguments": {…}}}`, when the
    /// output is one and names a tool on offer.
    private static func toolCall(
        in text: String,
        tools: [Transcript.ToolDefinition]
    ) -> (name: String, arguments: String)? {
        guard let json = SchemaJSON.firstObject(in: text),
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let call = object["tool_call"] as? [String: Any],
              let name = call["name"] as? String,
              tools.contains(where: { $0.name == name })
        else { return nil }
        let arguments = call["arguments"] ?? [String: Any]()
        let data = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
        return (name, String(decoding: data, as: UTF8.self))
    }
}

// MARK: - Usage

/// What a turn cost, as the engine counted it.
///
/// The engine counts decoded tokens as one figure, thinking and answer
/// together, so the thinking share is estimated from how much of the decoded
/// text came through the thought channel.
private nonisolated struct Usage {
    var inputTokens: Int
    var outputTokens: Int
    var reasoningTokens: Int
    var decodeSpeed: Double?
    var speculated: Bool
    var retriedUnderConstraint = false

    init(conversation: Conversation, thoughtLength: Int, textLength: Int, speculated: Bool) {
        let benchmark = try? conversation.getBenchmarkInfo()
        let total = (try? conversation.getTokenCount()) ?? 0
        let decoded = benchmark?.lastDecodeTokenCount ?? 0
        let characters = max(thoughtLength + textLength, 1)
        inputTokens = max(total - decoded, 0)
        outputTokens = decoded
        reasoningTokens = Int((Double(decoded) * Double(thoughtLength) / Double(characters)).rounded())
        decodeSpeed = benchmark?.lastDecodeTokensPerSecond
        self.speculated = speculated
    }

    /// Counts a discarded pass's tokens in with this one's; the speed and the
    /// decoding mode stay this pass's own.
    mutating func add(_ other: Usage) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        reasoningTokens += other.reasoningTokens
    }

    var textTokens: Int { max(outputTokens - reasoningTokens, 1) }

    var input: LanguageModelExecutorGenerationChannel.Usage.Input {
        .init(totalTokenCount: inputTokens, cachedTokenCount: 0)
    }

    var output: LanguageModelExecutorGenerationChannel.Usage.Output {
        .init(totalTokenCount: outputTokens, reasoningTokenCount: reasoningTokens)
    }

    var metadata: [String: any ConvertibleToGeneratedContent] {
        var metadata: [String: any ConvertibleToGeneratedContent] = [
            OnDeviceModel.speculativeDecodingKey: speculated,
            OnDeviceModel.constrainedRetryKey: retriedUnderConstraint,
        ]
        if let decodeSpeed { metadata[OnDeviceModel.decodeSpeedKey] = decodeSpeed }
        return metadata
    }
}

// MARK: - Transcript → conversation

/// One turn of the Foundation Models transcript, laid out the way a LiteRT
/// conversation takes it: a system message, the turns before, and the message
/// to answer — the last prompt, or the tool output of a round trip.
private nonisolated struct Turn {
    var system: LiteRTLM.Message?
    var history: [LiteRTLM.Message] = []
    var prompt: LiteRTLM.Message

    init(
        transcript: Transcript,
        tools: [Transcript.ToolDefinition],
        mustCallTool: Bool,
        schema: SchemaJSON?
    ) throws {
        let entries = Array(transcript)
        guard let triggerIndex = entries.lastIndex(where: { entry in
            switch entry {
            case .prompt, .toolOutput: true
            default: false
            }
        }) else {
            throw GemmaError.noPrompt
        }

        var systemParts: [String] = []
        var trigger: LiteRTLM.Message?
        for (index, entry) in entries.enumerated() {
            let isTrigger = index == triggerIndex
            switch entry {
            case .instructions(let instructions):
                systemParts.append(Transcript.text(of: instructions.segments))
            case .prompt(let prompt):
                var text = Transcript.text(of: prompt.segments)
                if isTrigger, let schema {
                    text += "\n\nAnswer with one JSON object that follows this JSON schema:\n\(schema.text)"
                }
                let message = LiteRTLM.Message(text, role: .user)
                if isTrigger { trigger = message } else { history.append(message) }
            case .response(let response):
                history.append(LiteRTLM.Message(Transcript.text(of: response.segments), role: .model))
            case .toolCalls(let calls):
                let text = calls.map { call in
                    #"{"tool_call": {"name": "\#(call.toolName)", "arguments": \#(call.arguments.jsonString)}}"#
                }.joined(separator: "\n")
                history.append(LiteRTLM.Message(text, role: .model))
            case .toolOutput(let output):
                let message = LiteRTLM.Message(
                    "\(output.toolName) returned:\n\(Transcript.text(of: output.segments))",
                    role: .user
                )
                if isTrigger { trigger = message } else { history.append(message) }
            case .reasoning:
                // Earlier thoughts stay out of later turns, as Gemma expects.
                break
            @unknown default:
                break
            }
        }
        if !tools.isEmpty {
            systemParts.append(try Self.toolSection(tools, mustCallTool: mustCallTool))
        }

        let system = systemParts.filter { !$0.isEmpty }.joined(separator: "\n\n")
        self.system = system.isEmpty ? nil : LiteRTLM.Message(system, role: .system)
        self.prompt = trigger!  // guaranteed by triggerIndex
    }

    private static func toolSection(_ tools: [Transcript.ToolDefinition], mustCallTool: Bool) throws -> String {
        var lines = ["TOOLS"]
        for tool in tools {
            lines.append("\(tool.name): \(tool.description)")
            lines.append("Arguments, as a JSON schema: \(try SchemaJSON(tool.parameters).text)")
        }
        lines.append(#"To call a tool, reply with only {"tool_call": {"name": "<tool name>", "arguments": {...}}}."#)
        lines.append(mustCallTool
            ? "Reply with a tool call now; the answer comes after its result."
            : "To answer without a tool, reply in plain text.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Schemas

/// A `GenerationSchema` as the JSON schema the prompt shows and the decoder
/// is held to.
///
/// Two changes on the way through. Every property becomes required and the
/// optional ones nullable, so the model writes an explicit `null` for what a
/// question leaves out — Foundation Models' own encoding just leaves optional
/// properties out of `required`, and a model held to that writes an empty
/// string instead. And properties keep the order they were declared in
/// (`x-order`), since the decoder generates them in schema order and the
/// declaration order is deliberate. The text is written in a fixed key order,
/// so the same schema always prompts the same way.
///
/// llguidance's own separators (`,` and `:`, with whitespace allowed around
/// them) are left alone. Setting `", "` and `": "` through `x-guidance` makes
/// the grammar force the space, and LiteRT-LM 0.18.1 doesn't apply forced
/// bytes: Gemma's `":` token is rejected and every constrained turn fails.
nonisolated struct SchemaJSON {
    let text: String
    private let value: JSONValue

    init(_ schema: GenerationSchema) throws {
        let data = try JSONEncoder().encode(schema)
        let object = try JSONSerialization.jsonObject(with: data)
        self.init(value: Self.normalized(JSONValue(object)))
    }

    private init(value: JSONValue) {
        self.value = value
        text = value.text
    }

    /// Whether `json` fits the schema closely enough for Foundation Models to
    /// decode it: every required key there, nulls only where a value may be
    /// left out, and each value the right type or one of the listed cases.
    /// Bounds such as `maxItems` and `minimum` aren't checked; decoding
    /// doesn't check them either.
    func accepts(_ json: String) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) else { return false }
        return Self.value(object, fits: value)
    }

    private static func value(_ any: Any, fits schema: JSONValue) -> Bool {
        guard case .object(let pairs) = schema else { return true }
        let fields = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        if case .array(let options)? = fields["anyOf"] {
            return options.contains { value(any, fits: $0) }
        }
        if case .array(let cases)? = fields["enum"] {
            return cases.contains { $0.matches(any) }
        }
        let types: [String] = switch fields["type"] {
        case .string(let type)?: [type]
        case let types?: types.strings ?? []
        case nil: []
        }
        // A `$ref` or anything else this doesn't model is taken on trust.
        guard !types.isEmpty else { return true }
        return types.contains { type in
            switch type {
            case "null": return any is NSNull
            case "string": return any is String
            case "boolean": return JSONValue.isBool(any)
            case "number": return any is NSNumber && !JSONValue.isBool(any)
            case "integer":
                guard let number = any as? NSNumber, !JSONValue.isBool(any) else { return false }
                return number.doubleValue.rounded() == number.doubleValue
            case "array":
                guard let items = any as? [Any] else { return false }
                guard let itemSchema = fields["items"] else { return true }
                return items.allSatisfy { value($0, fits: itemSchema) }
            case "object":
                guard let object = any as? [String: Any] else { return false }
                guard case .object(let properties)? = fields["properties"] else { return true }
                // A key left out is fine wherever a null would be.
                return properties.allSatisfy { name, property in
                    value(object[name] ?? NSNull(), fits: property)
                }
            default:
                return true
            }
        }
    }

    /// The envelope a required call is held to: one of the tools by name, with
    /// arguments that fit its schema.
    static func toolCall(_ tools: [Transcript.ToolDefinition]) throws -> SchemaJSON {
        let calls: [JSONValue] = try tools.map { tool in
            let arguments = Self.normalized(JSONValue(try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(tool.parameters)
            )))
            return .object([
                ("type", .string("object")),
                ("properties", .object([
                    ("name", .object([("type", .string("string")), ("enum", .array([.string(tool.name)]))])),
                    ("arguments", arguments),
                ])),
                ("required", .array([.string("name"), .string("arguments")])),
                ("additionalProperties", .bool(false)),
            ])
        }
        let call: JSONValue = calls.count == 1 ? calls[0] : .object([("anyOf", .array(calls))])
        return SchemaJSON(value: .object([
            ("type", .string("object")),
            ("properties", .object([("tool_call", call)])),
            ("required", .array([.string("tool_call")])),
            ("additionalProperties", .bool(false)),
        ]))
    }

    private static func normalized(_ value: JSONValue) -> JSONValue {
        switch value {
        case .array(let items):
            return .array(items.map(normalized))
        case .object(let pairs):
            var fields = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
            if case .object(let properties)? = fields["properties"] {
                let declared = fields["x-order"]?.strings ?? properties.map(\.0).sorted()
                let required = Set(fields["required"]?.strings ?? [])
                let byName = Dictionary(properties, uniquingKeysWith: { first, _ in first })
                let names = declared.filter { byName[$0] != nil }
                fields["properties"] = .object(names.map { name in
                    let property = normalized(byName[name]!)
                    return (name, required.contains(name) ? property : nullable(property))
                })
                fields["required"] = .array(names.map(JSONValue.string))
            }
            fields["x-order"] = nil
            fields["title"] = nil
            for key in ["items", "anyOf", "$defs", "additionalProperties"] {
                if let nested = fields[key] { fields[key] = normalized(nested) }
            }
            return .object(ordered(fields))
        default:
            return value
        }
    }

    private static func nullable(_ property: JSONValue) -> JSONValue {
        guard case .object(let pairs) = property else { return property }
        var fields = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        guard case .string(let type)? = fields["type"] else {
            return .object([("anyOf", .array([property, .object([("type", .string("null"))])]))])
        }
        fields["type"] = .array([.string(type), .string("null")])
        if case .array(let cases)? = fields["enum"] {
            fields["enum"] = .array(cases + [.null])
        }
        return .object(ordered(fields))
    }

    private static let keyOrder = [
        "type", "description", "enum", "const", "properties", "required", "items",
        "minItems", "maxItems", "minimum", "maximum", "anyOf", "additionalProperties", "$defs",
    ]

    private static func ordered(_ fields: [String: JSONValue]) -> [(String, JSONValue)] {
        fields.sorted { a, b in
            let i = keyOrder.firstIndex(of: a.key) ?? keyOrder.count
            let j = keyOrder.firstIndex(of: b.key) ?? keyOrder.count
            return i == j ? a.key < b.key : i < j
        }.map { ($0.key, $0.value) }
    }

    /// The first balanced JSON object in model output, so a stray code fence
    /// or sentence around it doesn't sink the parse.
    static func firstObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return String(text[start...index]) }
            }
            index = text.index(after: index)
        }
        return nil
    }
}

/// JSON that remembers its key order, which `JSONSerialization` doesn't.
private nonisolated indirect enum JSONValue {
    case object([(String, JSONValue)])
    case array([JSONValue])
    case string(String)
    case number(NSNumber)
    case bool(Bool)
    case null

    init(_ any: Any) {
        switch any {
        case let dictionary as [String: Any]:
            self = .object(dictionary.map { ($0.key, JSONValue($0.value)) }.sorted { $0.0 < $1.0 })
        case let array as [Any]:
            self = .array(array.map(JSONValue.init))
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number)
        default:
            self = .null
        }
    }

    static func isBool(_ any: Any) -> Bool {
        guard let number = any as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// Whether a value `JSONSerialization` parsed is this one, for enum cases.
    func matches(_ any: Any) -> Bool {
        switch self {
        case .string(let string): (any as? String) == string
        case .null: any is NSNull
        case .bool(let bool): Self.isBool(any) && (any as? NSNumber)?.boolValue == bool
        case .number(let number): !Self.isBool(any) && (any as? NSNumber) == number
        case .object, .array: false
        }
    }

    var strings: [String]? {
        guard case .array(let items) = self else { return nil }
        return items.compactMap { item in
            if case .string(let string) = item { string } else { nil }
        }
    }

    var text: String {
        switch self {
        case .object(let pairs):
            "{" + pairs.map { "\(JSONValue.string($0.0).text):\($0.1.text)" }.joined(separator: ",") + "}"
        case .array(let items):
            "[" + items.map(\.text).joined(separator: ",") + "]"
        case .string(let string):
            String(decoding: (try? Self.encoder.encode(string)) ?? Data("\"\"".utf8), as: UTF8.self)
        case .number(let number):
            number.doubleValue == number.doubleValue.rounded() && abs(number.doubleValue) < 1e15
                ? String(Int64(number.doubleValue))
                : number.stringValue
        case .bool(let bool):
            bool ? "true" : "false"
        case .null:
            "null"
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()
}

// MARK: - Engine

/// One loaded engine per configuration, shared by every session in the
/// process — the weights are gigabytes, and two copies would not fit.
///
/// Turns are taken one at a time: a session waits for the one ahead of it to
/// finish rather than racing it on the GPU.
actor GemmaEngine {
    private nonisolated static let engines = Mutex<[EngineConfig: GemmaEngine]>([:])

    nonisolated static func shared(for config: EngineConfig) -> GemmaEngine {
        engines.withLock { engines in
            if let engine = engines[config] { return engine }
            let engine = GemmaEngine(config: config)
            engines[config] = engine
            return engine
        }
    }

    private let config: EngineConfig
    private var loading: Task<Engine, Error>?
    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    private init(config: EngineConfig) {
        self.config = config
    }

    /// The loaded engine, loading it on first use. A failed load is retried
    /// on the next call.
    func ready() async throws -> Engine {
        if let loading { return try await loading.value }
        let config = config
        let task = Task {
            guard FileManager.default.fileExists(atPath: config.modelPath) else {
                throw GemmaError.modelMissing
            }
            Self.configureRuntime()
            let engine = Engine(engineConfig: config)
            try await engine.initialize()
            return engine
        }
        loading = task
        do {
            return try await task.value
        } catch {
            if loading == task { loading = nil }
            throw error
        }
    }

    func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        // Ownership is handed straight over by `release()`, so `isBusy`
        // stays set for the turn that wakes up here.
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty {
            isBusy = false
        } else {
            waiting.removeFirst().resume()
        }
    }

    /// LiteRT-LM reads these when an engine is created. Speculative decoding
    /// runs the drafter bundled in the model file ahead of the main model;
    /// benchmarking is what reports token counts and decode speed per turn.
    private nonisolated static func configureRuntime() {
        ExperimentalFlags.optIntoExperimentalAPIs()
        ExperimentalFlags.enableSpeculativeDecoding = true
        ExperimentalFlags.enableBenchmark = true
    }
}
