import Foundation
import FoundationModels

/// Answers a question about the bundled statement in two steps.
///
/// First the Query tab's own parse — the date reasoning chain for the dates,
/// the model for merchant, amounts and categories — turns the question into
/// filters.
/// Then a second model session, holding a tool built around the transactions
/// those filters matched, works out what the question asks about them and
/// writes the answer from the tool's figures.
@MainActor
@Observable
final class TransactionAnswerer {
    enum Phase {
        case idle
        case answering
        case answered(TransactionAnswer)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    let store: TransactionStore

    /// The same parser the Query tab runs, so a question is read the same way
    /// on both tabs.
    private let parser = QueryParser()

    /// The same permissive guardrails as the parse: the input is the person's
    /// own question about their own spending.
    private let model = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

    /// The answer in flight, kept so clearing the search bar can drop it.
    private var activeRun: Task<Void, Never>?

    init(store: TransactionStore = .bundled) {
        self.store = store
    }

    var availability: SystemLanguageModel.Availability { model.availability }

    var modelName: String { model.variant.displayName }

    /// Today, as far as this tab is concerned: the statement date.
    var reference: DateReference { store.reference }

    /// Warms the parse sessions. The answer session can't be warmed ahead of
    /// time — its tool is built around the transactions a question matches.
    func prewarm() {
        parser.prewarm()
    }

    func ask(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            reset()
            return
        }
        activeRun?.cancel()
        phase = .answering
        activeRun = Task { await run(question) }
    }

    func reset() {
        activeRun?.cancel()
        activeRun = nil
        phase = .idle
        prewarm()
    }

    private func run(_ question: String) async {
        defer { prewarm() }
        do {
            let answer = try await answer(question)
            guard !Task.isCancelled else { return }
            phase = .answered(answer)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Runs one question end to end without touching `phase` — the path both
    /// the view and the accuracy tests take.
    func answer(_ question: String) async throws -> TransactionAnswer {
        let reference = reference
        let (parsed, parseMetrics) = try await parser.parsedQuery(for: question, reference: reference)
        let scope = TransactionScope(parsed)
        let matches = store.matching(scope)
        let filters = scope.summary

        let session = LanguageModelSession(profile: AnswerProfile(
            model: model,
            instructions: Self.instructions,
            tool: LookUpTransactionsTool(transactions: matches, filters: filters)
        ))

        let clock = ContinuousClock()
        let start = clock.now
        let response = try await session.respond(to: Self.prompt(question: question, filters: filters))
        let latency = clock.now - start
        let usage = response.usage

        return TransactionAnswer(
            question: question,
            parsed: parsed,
            parseMetrics: parseMetrics,
            scope: scope,
            matches: matches,
            text: response.content.trimmingCharacters(in: .whitespacesAndNewlines),
            toolCalls: ToolCallRecord.records(in: response.transcriptEntries),
            latency: latency,
            inputTokens: usage.input.totalTokenCount,
            cachedInputTokens: usage.input.cachedTokenCount,
            outputTokens: usage.output.totalTokenCount
        )
    }

    private static func prompt(question: String, filters: String) -> String {
        """
        Question: \(question)
        Filters already applied: \(filters)
        """
    }

    private static let instructions = """
        You answer a person's questions about their own credit card transactions.

        The question's filters are already applied. Call lookUpTransactions to read the \
        matching transactions, then write the answer from the data it returns. Never add up, \
        filter, or work out anything yourself — every figure in your answer comes from that data.

        How to answer:
        - Start with the figure the question asks for: totalSpent for how much, \
        matchingTransactionCount for how many, averagePerTransaction for an average, or one \
        transaction's amount and date for the biggest, smallest, first, or last.
        - Which or where: name the first entry in groupTotals and its totalSpent — a group, \
        never a single transaction.
        - Show, list, or what was bought: add one line per transaction in listedTransactions, \
        each with its date, merchant, and amount.
        - When matchingTransactionCount is 0, say that no transactions matched.

        Write amounts with a dollar sign and cents, and dates as the month name, day, and year.
        """
}

/// The answer session's setup: one tool, called exactly once.
///
/// Left to choose, the model sometimes skipped the tool and invented figures —
/// mostly on yes-or-no questions. A plain `.required` tool-calling mode fixes
/// that but holds for every step of the turn, so the model called the tool
/// again and again until the context window overflowed. This profile requires
/// the call only until the transcript holds a tool output, then turns tool
/// calling off so the next step is the answer.
struct AnswerProfile: LanguageModelSession.DynamicProfile {
    @SessionProperty(\.history) var history

    let model: SystemLanguageModel
    let instructions: String
    let tool: LookUpTransactionsTool

    var body: some DynamicProfile {
        let hasLookedUp = history.contains { entry in
            if case .toolOutput = entry { true } else { false }
        }
        LanguageModelSession.Profile {
            Instructions(instructions)
            tool
        }
        .model(model)
        // Greedy sampling keeps repeated runs of the same question comparable.
        .samplingMode(.greedy)
        .toolCallingMode(hasLookedUp ? .disallowed : .required)
    }
}

/// Everything one question produced, for the result screen and the tests.
struct TransactionAnswer {
    var question: String
    var parsed: ParsedQuery
    var parseMetrics: QueryParser.Metrics
    /// The filters the parse put on the statement.
    var scope: TransactionScope
    /// The transactions those filters matched — the only ones the tools saw.
    var matches: [Transaction]
    /// The model's answer, as shown on screen.
    var text: String
    var toolCalls: [ToolCallRecord]
    /// The answer session's own wall time, after the parse.
    var latency: Duration
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
}

/// One tool call as the transcript recorded it: what the model asked for and
/// what came back.
struct ToolCallRecord: Identifiable, Equatable {
    var id: String
    var toolName: String
    /// The arguments as JSON — `{}` for a tool that takes none.
    var arguments: String
    var output: String

    static func records(in entries: some Collection<Transcript.Entry>) -> [ToolCallRecord] {
        var outputs: [String: String] = [:]
        for case .toolOutput(let output) in entries {
            outputs[output.id] = output.segments.map { segment in
                switch segment {
                case .text(let text): text.content
                case .structure(let structure): structure.content.jsonString
                default: ""
                }
            }.joined(separator: "\n")
        }
        var records: [ToolCallRecord] = []
        for case .toolCalls(let calls) in entries {
            for call in calls {
                records.append(ToolCallRecord(
                    id: call.id,
                    toolName: call.toolName,
                    arguments: call.arguments.jsonString,
                    output: outputs[call.id] ?? ""
                ))
            }
        }
        return records
    }
}
