import Foundation
import FoundationModels

// A question's dates come from a chain of small sessions
// rather than one session holding every date tool.
//
// Holding five tools at once, the model had to read the question, pick a
// tool, and fill in its arguments in a single pass, and it slipped at each:
// "the past month" went to the calendar-period tool, every weekday to the
// single-day tool with the model counting the days itself, and "last month"
// came back as the current one. So the chain splits the reading from the
// counting:
//
// 1. Two extractors copy the question's time words side by side: one whole —
//    "since last Thursday" — and one leaving off since, from, or starting in
//    front — "last Thursday". Copying is what the model does most reliably,
//    as long as each session copies one thing: asked for both at once, it
//    began copying whole questions. The whole copy is the touchy one. Name
//    no opener in its prompt and it drops "since" two times in three; list
//    every time word and it writes "since" into a third of its copies; name
//    the openers and tell it to add and change nothing, and it does best.
// 2. Two readers say which of five kinds of time the shorter copy names.
//    They see those words alone, never the question: shown "since last
//    Thursday", the model read every "since …" as a span counted back from
//    today, whatever followed. They get the same instructions with the kinds
//    listed in opposite orders, because the model leans toward whichever
//    kind comes first. When the two agree, that's the kind.
// 3. When they don't, an arbiter is shown only those two kinds and the one
//    rule that tells them apart — does it name a month? a day of the week? a
//    number? — and picks.
// 4. Alongside the readers, two opener readers look at the whole copy and
//    say whether the range runs on to today — whether since, from, or
//    starting opens it — again with the two answers listed in opposite
//    orders. Left to each specialist, this came back "since" for "10 days
//    ago" and "the month before last" one question in sixteen, always the
//    same way; the range runs on to today only when both opener readers say
//    so.
// 5. A specialist for that kind gets the whole time words, instructions
//    written for that kind alone, and the one tool that counts it, told by
//    the opener readers whether the range runs on to today. It calls the
//    tool exactly once and copies the range the tool answers with.
//
// The kinds are named for the words that mark them — `pastNUnits`,
// `nUnitsAgo`, `dayOfTheWeek` — rather than for what they mean. Named
// `pastSpan`, the counted-span kind drew in every range in the past, "since
// September 15" and "May to July" included, and the arbiter chose it over
// its own rule ten times out of seventeen.
//
// What passes between the stages is structured — copied words and enums —
// and Swift does every bit of arithmetic. Nothing in the chain reads the words
// itself: which specialist runs is the models' choice, and what the tool is
// asked is the specialist's.

/// The five kinds of time a spending question names, one per specialist.
nonisolated enum TimeKind: String, CaseIterable, Sendable {
    case pastNUnits, nUnitsAgo, thisOrLastPeriod, namedDate, dayOfTheWeek

    /// How the readers describe each kind, as it looks with any since, from,
    /// or starting taken off the front.
    var definition: String {
        switch self {
        case .pastNUnits:
            #"pastNUnits: a number of days, weeks, months, quarters, or years counted back from today — "the past N days", "the last N months", "the past week", "within the last N weeks", "over the past N years"."#
        case .nUnitsAgo:
            #"nUnitsAgo: one day a number of units before today — "N days ago", "N weeks ago", "a month ago", "today", "yesterday", "the day before yesterday"."#
        case .thisOrLastPeriod:
            #"thisOrLastPeriod: a whole week, weekend, month, quarter, or year called this, last, previous, or before last, with no number — "this week", "last month", "last year", "the previous quarter", "the year before last", "so far this week", "month to date", "the start of the year"."#
        case .namedDate:
            #"namedDate: a month by its name, a date, a quarter by its number — first, second, third, or fourth — or a year by its number, or a span from one of them to another — "April", "April 12", "4/12", "the second quarter", "April last year", "April 1 to April 15", "April to June"."#
        case .dayOfTheWeek:
            #"dayOfTheWeek: a day of the week by its name — "Saturday", "last Saturday"."#
        }
    }
}

/// What the anchor extractor copies out of the question: the time words
/// with any since, from, or starting taken off the front.
@Generable(
    description: "The time words in a question about the user's card transactions.",
    representNilExplicitlyInGeneratedContent: true
)
nonisolated struct ExtractedTime: Equatable, Sendable {
    @Guide(description: "The question's time words, copied exactly, without since, from, or starting in front of them. Null when it mentions no time.")
    var timeWords: String?
}

/// What the whole-words extractor copies out of the question.
@Generable(
    description: "The time words in a question about the user's card transactions.",
    representNilExplicitlyInGeneratedContent: true
)
nonisolated struct WholeTimeWords: Equatable, Sendable {
    @Guide(description: "The question's time words, copied exactly, with since, from, starting, on, in, or between when one comes right before them. Null when it mentions no time.")
    var timeWords: String?
}

/// The first reader's answer, with the kinds in `TimeKind` order.
@Generable(description: "The kind of time some time words name.")
nonisolated struct TimeReading: Equatable, Sendable {
    var kind: Kind

    @Generable
    nonisolated enum Kind: String, Sendable {
        case pastNUnits, nUnitsAgo, thisOrLastPeriod, namedDate, dayOfTheWeek
    }
}

/// The second reader's answer: the same, with the kinds in reverse.
@Generable(description: "The kind of time some time words name.")
nonisolated struct ReversedTimeReading: Equatable, Sendable {
    var kind: Kind

    @Generable
    nonisolated enum Kind: String, Sendable {
        case dayOfTheWeek, namedDate, thisOrLastPeriod, nUnitsAgo, pastNUnits
    }
}

/// The first opener reader's answer: does the range run on to today?
@Generable(description: "Whether some time words make a range run on to today.")
nonisolated struct OpenerReading: Equatable, Sendable {
    var reach: Reach

    @Generable
    nonisolated enum Reach: Sendable {
        case alone, sinceOrFrom
    }
}

/// The second opener reader's answer: the same, with the answers reversed.
@Generable(description: "Whether some time words make a range run on to today.")
nonisolated struct ReversedOpenerReading: Equatable, Sendable {
    var reach: Reach

    @Generable
    nonisolated enum Reach: Sendable {
        case sinceOrFrom, alone
    }
}

/// One session's share of the chain, for the trace the app and the tests show.
nonisolated struct ChainStep: Equatable, Sendable, CustomStringConvertible {
    var stage: String
    /// What the session came back with, in a line.
    var detail: String
    var latency: Duration
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int

    var description: String { "\(stage): \(detail)" }
}

/// Everything the chain worked out for one question.
nonisolated struct DateChainOutcome: Equatable, Sendable {
    var fromDate: String?
    var toDate: String?
    var steps: [ChainStep] = []
    /// Each tool call the specialist made, as `name {arguments} → answer`.
    var toolCalls: [String] = []

    var inputTokens: Int { steps.reduce(0) { $0 + $1.inputTokens } }
    var cachedInputTokens: Int { steps.reduce(0) { $0 + $1.cachedInputTokens } }
    var outputTokens: Int { steps.reduce(0) { $0 + $1.outputTokens } }
}

struct DateReasoningChain {
    let model: SystemLanguageModel
    let arithmetic: DateArithmetic

    /// The sessions that read the question before a specialist takes over:
    /// the two extractors, the two readers, and the two opener readers.
    /// Their instructions never change, so the parser can build and warm
    /// them ahead of the question.
    struct Readers {
        let extractor: LanguageModelSession
        let wholeExtractor: LanguageModelSession
        let forward: LanguageModelSession
        let reversed: LanguageModelSession
        let openerForward: LanguageModelSession
        let openerReversed: LanguageModelSession

        init(model: SystemLanguageModel) {
            extractor = LanguageModelSession(
                model: model,
                instructions: Instructions(DateReasoningChain.extractorInstructions)
            )
            wholeExtractor = LanguageModelSession(
                model: model,
                instructions: Instructions(DateReasoningChain.wholeExtractorInstructions)
            )
            forward = LanguageModelSession(
                model: model,
                instructions: Instructions(DateReasoningChain.readerInstructions(TimeKind.allCases))
            )
            reversed = LanguageModelSession(
                model: model,
                instructions: Instructions(DateReasoningChain.readerInstructions(TimeKind.allCases.reversed()))
            )
            openerForward = LanguageModelSession(
                model: model,
                instructions: Instructions(DateReasoningChain.openerInstructions(sinceFirst: false))
            )
            openerReversed = LanguageModelSession(
                model: model,
                instructions: Instructions(DateReasoningChain.openerInstructions(sinceFirst: true))
            )
        }

        func prewarm() {
            extractor.prewarm()
            wholeExtractor.prewarm()
            forward.prewarm()
            reversed.prewarm()
            openerForward.prewarm()
            openerReversed.prewarm()
        }
    }

    /// Runs `question` through the readers, the arbiter when they differ, and
    /// the specialist for the kind they settle on.
    ///
    /// `readers` is a warm set, when the caller has one. A guardrail refusal
    /// in any of the chain's sessions — a false positive on a spending
    /// question — comes back as no dates and a note in the trace, so the
    /// merchant and amounts from the other session still stand.
    func resolve(_ question: String, readers: Readers? = nil) async throws -> DateChainOutcome {
        do {
            return try await chain(question, readers: readers)
        } catch let error as LanguageModelError {
            switch error {
            case .guardrailViolation, .refusal:
                return DateChainOutcome(steps: [ChainStep(
                    stage: "refused",
                    detail: error.localizedDescription,
                    latency: .zero,
                    inputTokens: 0,
                    cachedInputTokens: 0,
                    outputTokens: 0
                )])
            default:
                throw error
            }
        }
    }

    private func chain(_ question: String, readers: Readers?) async throws -> DateChainOutcome {
        let clock = ContinuousClock()
        var outcome = DateChainOutcome()
        let readers = readers ?? Readers(model: model)

        var start = clock.now
        async let anchorResponse = readers.extractor.respond(
            to: question,
            generating: ExtractedTime.self,
            options: GenerationOptions(samplingMode: .greedy),
            contextOptions: ContextOptions(includeSchemaInPrompt: true)
        )
        async let wholeResponse = Self.wholeTimeWords(question, in: readers.wholeExtractor)
        let (extracted, whole) = try await (anchorResponse, wholeResponse)
        let extractLatency = clock.now - start
        let anchor = extracted.content.timeWords ?? ""
        let timeWords = whole.content?.timeWords.flatMap { $0.isEmpty ? nil : $0 } ?? anchor
        outcome.steps.append(ChainStep(
            stage: "extractor",
            detail: anchor.isEmpty ? "no time" : "\u{201C}\(anchor)\u{201D}",
            latency: extractLatency,
            usage: extracted.usage
        ))
        outcome.steps.append(ChainStep(
            stage: "whole extractor",
            detail: whole.content.map { $0.timeWords.map { "\u{201C}\($0)\u{201D}" } ?? "no time" } ?? "refused",
            latency: extractLatency,
            inputTokens: whole.usage?.input.totalTokenCount ?? 0,
            cachedInputTokens: whole.usage?.input.cachedTokenCount ?? 0,
            outputTokens: whole.usage?.output.totalTokenCount ?? 0
        ))
        // No time in the question, as the extractor that feeds the readers
        // sees it.
        guard !anchor.isEmpty else { return outcome }

        start = clock.now
        let readerPrompt = "Time words: \u{201C}\(anchor)\u{201D}"
        async let forwardResponse = readers.forward.respond(
            to: readerPrompt,
            generating: TimeReading.self,
            options: GenerationOptions(samplingMode: .greedy),
            contextOptions: ContextOptions(includeSchemaInPrompt: true)
        )
        async let reversedResponse = readers.reversed.respond(
            to: readerPrompt,
            generating: ReversedTimeReading.self,
            options: GenerationOptions(samplingMode: .greedy),
            contextOptions: ContextOptions(includeSchemaInPrompt: true)
        )
        let openerPrompt = "Time words: \u{201C}\(timeWords)\u{201D}"
        async let openerForwardResponse = readers.openerForward.respond(
            to: openerPrompt,
            generating: OpenerReading.self,
            options: GenerationOptions(samplingMode: .greedy),
            contextOptions: ContextOptions(includeSchemaInPrompt: true)
        )
        async let openerReversedResponse = readers.openerReversed.respond(
            to: openerPrompt,
            generating: ReversedOpenerReading.self,
            options: GenerationOptions(samplingMode: .greedy),
            contextOptions: ContextOptions(includeSchemaInPrompt: true)
        )
        let (forward, reversed, openerForward, openerReversed) = try await (
            forwardResponse, reversedResponse, openerForwardResponse, openerReversedResponse
        )
        let readerLatency = clock.now - start

        // The model leans toward "since" whichever way the answers are
        // listed, so the range runs on to today only when both readers say it
        // does: a real "since" opens the words and neither misses it.
        let firstSince = openerForward.content.reach == .sinceOrFrom
        let secondSince = openerReversed.content.reach == .sinceOrFrom
        let runsToToday = firstSince && secondSince
        outcome.steps.append(ChainStep(
            stage: "opener",
            detail: firstSince == secondSince ? (runsToToday ? "sinceOrFrom" : "alone") : "split, so alone",
            latency: readerLatency,
            inputTokens: openerForward.usage.input.totalTokenCount + openerReversed.usage.input.totalTokenCount,
            cachedInputTokens: openerForward.usage.input.cachedTokenCount + openerReversed.usage.input.cachedTokenCount,
            outputTokens: openerForward.usage.output.totalTokenCount + openerReversed.usage.output.totalTokenCount
        ))

        let firstKind = TimeKind(rawValue: forward.content.kind.rawValue) ?? .pastNUnits
        let secondKind = TimeKind(rawValue: reversed.content.kind.rawValue) ?? firstKind
        outcome.steps.append(ChainStep(stage: "reader", detail: "\(firstKind)", latency: readerLatency, usage: forward.usage))
        outcome.steps.append(ChainStep(stage: "reversed reader", detail: "\(secondKind)", latency: readerLatency, usage: reversed.usage))

        var kind = firstKind
        if secondKind != firstKind {
            start = clock.now
            let (picked, usage) = try await arbitrate(anchor: anchor, between: firstKind, and: secondKind)
            kind = picked
            outcome.steps.append(ChainStep(stage: "arbiter", detail: "\(picked)", latency: clock.now - start, usage: usage))
        }

        var feedback: String?
        var wordsOnly = false
        // Up to two more tries when the tool turns the arguments down, with its
        // reason in the prompt — the way a person would be told what was
        // wrong — or when the session refuses: the calendar specialist turned
        // down "Charges between 9/1 and 9/15" with the question in its prompt,
        // and answered with the time words alone.
        for attempt in 1...3 {
            start = clock.now
            // A fresh tool each time, so its one call is still unspent.
            let specialist = Specialist(kind, arithmetic: arithmetic, runsToToday: runsToToday)
            let session = LanguageModelSession(profile: OneToolCallProfile(
                model: model,
                instructions: specialist.instructions,
                tool: specialist.tool
            ))
            do {
                let response = try await session.respond(
                    to: Self.specialistPrompt(
                        question: wordsOnly ? nil : question,
                        timeWords: timeWords,
                        feedback: feedback
                    ),
                    generating: DateRange.self,
                    contextOptions: ContextOptions(includeSchemaInPrompt: true)
                )
                outcome.toolCalls += ToolCallTrace.calls(in: response.transcriptEntries)
                outcome.steps.append(ChainStep(
                    stage: specialist.tool.name,
                    detail: "\(response.content.fromDate)–\(response.content.toDate)",
                    latency: clock.now - start,
                    usage: response.usage
                ))
                outcome.fromDate = response.content.fromDate
                outcome.toDate = response.content.toDate
                return outcome
            } catch let error as LanguageModelSession.ToolCallError {
                // A last refusal ends the chain with no dates: a miss to
                // report, not an error that sinks the merchant and amounts.
                feedback = error.underlyingError.localizedDescription
                outcome.toolCalls += ToolCallTrace.calls(in: session.transcript)
                outcome.steps.append(ChainStep(
                    stage: specialist.tool.name,
                    detail: "rejected: \(feedback ?? "")",
                    latency: clock.now - start,
                    inputTokens: 0,
                    cachedInputTokens: 0,
                    outputTokens: 0
                ))
            } catch let error as LanguageModelError where attempt < 3 {
                switch error {
                case .guardrailViolation, .refusal:
                    wordsOnly = true
                    outcome.steps.append(ChainStep(
                        stage: specialist.tool.name,
                        detail: "refused; asking again with the time words alone",
                        latency: clock.now - start,
                        inputTokens: 0,
                        cachedInputTokens: 0,
                        outputTokens: 0
                    ))
                default:
                    throw error
                }
            }
        }
        return outcome
    }

    /// The whole time words, or nothing when the session turns the question
    /// down — a guardrail false positive seen on "Insurance payments in the
    /// last 12 months". The chain then goes on with the shorter copy, which
    /// is the right reading whenever no since, from, or starting was there.
    private static func wholeTimeWords(
        _ question: String,
        in session: LanguageModelSession
    ) async throws -> (content: WholeTimeWords?, usage: LanguageModelSession.Usage?) {
        do {
            let response = try await session.respond(
                to: question,
                generating: WholeTimeWords.self,
                options: GenerationOptions(samplingMode: .greedy),
                contextOptions: ContextOptions(includeSchemaInPrompt: true)
            )
            return (response.content, response.usage)
        } catch let error as LanguageModelError {
            switch error {
            case .guardrailViolation, .refusal: return (nil, nil)
            default: throw error
            }
        }
    }

    /// Asks a fresh session to pick between the two kinds the readers named,
    /// told only how those two differ.
    private func arbitrate(
        anchor: String,
        between first: TimeKind,
        and second: TimeKind
    ) async throws -> (TimeKind, LanguageModelSession.Usage) {
        let rule = ArbiterRule(first, second)
        let session = LanguageModelSession(model: model, instructions: Instructions(rule.instructions))
        let schema = try GenerationSchema(
            root: DynamicGenerationSchema(
                name: "KindChoice",
                properties: [
                    DynamicGenerationSchema.Property(
                        name: "kind",
                        description: "The kind of time the time words name.",
                        schema: DynamicGenerationSchema(name: "Kind", anyOf: [rule.when.rawValue, rule.otherwise.rawValue])
                    ),
                ]
            ),
            dependencies: []
        )
        let response = try await session.respond(
            to: "Time words: \u{201C}\(anchor)\u{201D}",
            schema: schema,
            options: GenerationOptions(samplingMode: .greedy),
            contextOptions: ContextOptions(includeSchemaInPrompt: true)
        )
        let picked = try response.content.value(String.self, forProperty: "kind")
        return (TimeKind(rawValue: picked) ?? first, response.usage)
    }

    private static func specialistPrompt(question: String?, timeWords: String, feedback: String?) -> String {
        var prompt = "Time words: \u{201C}\(timeWords)\u{201D}"
        if let question {
            prompt += "\nQuestion: \(question)"
        }
        if let feedback {
            prompt += "\nYour last call was turned down: \(feedback)"
        }
        return prompt
    }

    /// The opener readers' prompt, with the two answers in either order.
    static func openerInstructions(sinceFirst: Bool) -> String {
        let alone = #"- alone: the time words don't begin with since, from, or starting — "April", "in April", "last month", "the month before last", "4 days ago", "between April 1 and April 15"."#
        let since = #"- sinceOrFrom: the time words begin with since, from, or starting — "since April", "from April 12", "since last month", "starting 4 weeks ago"."#
        return """
            You say whether some time words from a spending question begin with since, from, or \
            starting:
            \(sinceFirst ? since : alone)
            \(sinceFirst ? alone : since)
            """
    }

    static let extractorInstructions = """
        You find the time words in a question about the user's own card transactions.

        Copy every word about time exactly — past, last, this, ago, before last, to date, a \
        number, a month or a day — leaving off only since, from, or starting in front of them. \
        When the question mentions no time, give null.
        """

    /// Names the openers it must keep, and no other time words: with a list
    /// of those too, the model wrote them back into its copy — "Lunch since
    /// last Tuesday" for "Lunch last Tuesday" — in 37 of 100 questions.
    static let wholeExtractorInstructions = """
        You find the time words in a question about the user's own card transactions.

        Copy them exactly as the question writes them, with since, from, starting, on, in, or \
        between when one comes right before them, and no other words of the question. Add \
        nothing and change nothing. When the question mentions no time, give null.
        """

    /// The readers' prompt, with the kinds listed in `order`.
    static func readerInstructions(_ order: [TimeKind]) -> String {
        """
        You name the kind of time some time words from a spending question refer to:
        \(order.map { "- \($0.definition)" }.joined(separator: "\n"))

        "the past …" is always pastNUnits, and so is "last" followed by a number. "last" with no \
        number is thisOrLastPeriod — "last year" is the calendar year before this one — or \
        dayOfTheWeek, as in "last Saturday". "today", "yesterday", and "the day before \
        yesterday" are nUnitsAgo.
        """
    }
}

/// What tells two kinds apart, for the arbiter: the kind that holds when one
/// thing is true of the time words, and the one that holds otherwise.
nonisolated struct ArbiterRule: Sendable {
    let when: TimeKind
    let otherwise: TimeKind
    let test: String

    init(_ a: TimeKind, _ b: TimeKind) {
        let pair = Set([a, b])
        func other(than kind: TimeKind) -> TimeKind { a == kind ? b : a }
        if pair.contains(.dayOfTheWeek) {
            when = .dayOfTheWeek
            otherwise = other(than: .dayOfTheWeek)
            test = #"the time words name a day of the week — Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, or Sunday. "week" and "weekend" are not days of the week"#
        } else if pair.contains(.namedDate) {
            when = .namedDate
            otherwise = other(than: .namedDate)
            test = #"the time words name a month by its name — January through December — a date such as "4/12" or "2024-04-12", a quarter by its number such as "the second quarter", or a year by its number such as "2024", even after since or from. "this month", "last year", and "the start of the month" name no month or year by name"#
        } else if pair.contains(.nUnitsAgo) {
            when = .nUnitsAgo
            otherwise = other(than: .nUnitsAgo)
            test = #"the time words are one day: "today", "yesterday", "the day before yesterday", or "N days ago" with nothing in front of it. "the past N days", "the last N days", "within the last N days", and "since N days ago" or "from N days ago" all run on to today"#
        } else {
            when = .thisOrLastPeriod
            otherwise = .pastNUnits
            test = #"the time words have no number and don't say "past" — "last week", "last year", "the year before last", "since last month", "this quarter". "the past year" and "the last N months" count back from today"#
        }
    }

    var instructions: String {
        """
        You decide which kind of time some time words from a spending question name. Pick \
        \(when.rawValue) when \(test). Otherwise pick \(otherwise.rawValue).
        """
    }
}

/// The session that takes over once the kind of time is settled: its one
/// tool, and instructions about that kind alone.
struct Specialist {
    let tool: any Tool
    let instructions: String

    /// `runsToToday` is the opener readers' answer, handed to the tool
    /// rather than asked of the specialist again.
    init(_ kind: TimeKind, arithmetic: DateArithmetic, runsToToday: Bool) {
        let copy = "then answer with the fromDate and toDate it returns, copied exactly."
        switch kind {
        case .pastNUnits:
            tool = OnceTool(CountBackTool(arithmetic: arithmetic))
            instructions = """
                The time words count a number of units back from today. Call countBack once \
                with the number of units and the unit they count in, \(copy)

                Count in the unit the time words name, never converted to days. A stretch with no \
                number, such as "the past quarter", is one of its unit.
                """
        case .nUnitsAgo:
            tool = OnceTool(UnitsAgoTool(arithmetic: arithmetic, runsToToday: runsToToday))
            instructions = """
                The time words name a day counted back from today. Call unitsAgo once with how \
                many days, weeks, months, quarters, or years before today it is, \(copy)
                """
        case .thisOrLastPeriod:
            tool = OnceTool(CalendarPeriodTool(arithmetic: arithmetic, runsToToday: runsToToday))
            instructions = """
                The time words name a whole week, weekend, month, quarter, or year, counted from \
                the current one. Call calendarPeriod once with the kind of period and which one \
                it is, \(copy)

                Pick which from the time words:
                - this: "this …", "so far this …", "… to date", "the start of the …", "the \
                beginning of the …"
                - last: "last …", "the previous …"
                - beforeLast: "the … before last"
                """
        case .namedDate:
            tool = OnceTool(CalendarDateTool(arithmetic: arithmetic, runsToToday: runsToToday))
            instructions = """
                The time words name dates on the calendar. Call calendarDate once with what they \
                name, \(copy)

                Write each date in numbers: a month as MM, a day as MM-dd, a quarter as Qn. Give \
                its year only when the time words write one; without one, the tool finds the most \
                recent date. This year is \(arithmetic.currentYear). When the time words name a \
                second date, it goes in second, in the same call.
                """
        case .dayOfTheWeek:
            tool = OnceTool(WeekdayTool(arithmetic: arithmetic, runsToToday: runsToToday))
            instructions = """
                The time words name a day of the week. Call weekday once with that day, \(copy)
                """
        }
    }
}

/// A specialist's setup: one tool, called exactly once.
///
/// Left to choose, the model can skip a tool and write dates of its own; a
/// plain `.required` tool-calling mode holds for every step of the turn, so it
/// calls the tool over and over until the context window overflows. This
/// profile requires the call only until the transcript holds a tool output,
/// then turns tool calling off so the next step is the answer.
struct OneToolCallProfile: LanguageModelSession.DynamicProfile {
    @SessionProperty(\.history) var history

    let model: SystemLanguageModel
    let instructions: String
    let tool: any Tool

    var body: some DynamicProfile {
        let hasCalled = history.contains { entry in
            if case .toolOutput = entry { true } else { false }
        }
        LanguageModelSession.Profile {
            Instructions(instructions)
            [tool]
        }
        .model(model)
        // Greedy sampling keeps repeated runs of the same question comparable.
        .samplingMode(.greedy)
        .toolCallingMode(hasCalled ? .disallowed : .required)
    }
}

/// Reads tool calls out of a transcript for display.
nonisolated enum ToolCallTrace {
    /// Each tool call, paired with the answer it got back.
    ///
    /// Outputs land in the transcript in the order the calls were made, so the
    /// nth output answers the nth call.
    static func calls(in entries: some Collection<Transcript.Entry>) -> [String] {
        let calls = entries.flatMap { entry -> [Transcript.ToolCall] in
            if case .toolCalls(let calls) = entry { Array(calls) } else { [] }
        }
        let answers = entries.compactMap { entry -> String? in
            guard case .toolOutput(let output) = entry else { return nil }
            return output.segments.map { segment -> String in
                switch segment {
                case .text(let text): text.content
                case .structure(let structure): structure.content.jsonString
                default: ""
                }
            }.joined()
        }
        return calls.enumerated().map { index, call in
            let answer = index < answers.count ? " → \(answers[index])" : ""
            return "\(call.toolName) \(call.arguments.jsonString)\(answer)"
        }
    }
}

extension ChainStep {
    init(stage: String, detail: String, latency: Duration, usage: LanguageModelSession.Usage) {
        self.init(
            stage: stage,
            detail: detail,
            latency: latency,
            inputTokens: usage.input.totalTokenCount,
            cachedInputTokens: usage.input.cachedTokenCount,
            outputTokens: usage.output.totalTokenCount
        )
    }
}
