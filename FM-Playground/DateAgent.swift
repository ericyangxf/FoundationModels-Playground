import Foundation
import FoundationModels

/// Works out the date range a question covers with a Reason → Act → Observe
/// loop, run three times over as independent pipelines whose agreement is
/// the agent's confidence.
///
/// Each pipeline:
/// - Reason: a session with no tools copies the question's time words, or
///   says there are none. None means no dates — the range is never guessed.
/// - Act: a session holding the calendar tool calls it for those words
///   alone. It can also say they name no time after all.
/// - Observe: the call hands back a range, in dates and in words, or a
///   problem with the arguments — a count beside `lastMonth`, say. A problem
///   goes back to the same session, inside the same turn, for another call.
///
/// The pipelines differ in how they read and in list order: one reader
/// writes what the question asks before its time words, one after, and one
/// rewrites the question with its time words taken out; the act sessions see
/// the tool's kinds in alternating orders. A reading all three reach isn't an
/// artifact of any one of them. When they don't all agree, an arbiter
/// session sees the question and each distinct observation, labelled by the
/// call that made it, and picks one — or neither — asked with the list in
/// both orders.
///
/// The SDK exposes no token probabilities, so confidence comes from that
/// agreement instead: see `Confidence`. Below `minimumConfidence` the agent
/// declines with `AnswerDeclined` rather than pass on a reading nothing
/// confirmed. No range is better than a wrong one.
///
/// Two things were tried and dropped. A self-check — a session asked
/// whether the range it observed fits the question — called "yesterday" read
/// as October 5 a misfit, "this year" read as January through December "all
/// dates", and let "last" read as last week through. And act sessions shown
/// the whole question copied its dollar figures and this year's number into
/// every call.
///
/// The tool only counts. It never sees the question or the time words, so
/// which range a question gets is the model's own reading of it.
nonisolated struct DateAgent: Sendable {
    let model: SystemLanguageModel
    let arithmetic: CalendarArithmetic

    /// How sure the agent is of the range it settled on, from how its
    /// independent readings lined up.
    ///
    /// Measured on the 110 questions the model suites ask (one run, three
    /// pipelines): unanimous readings were right 62 times in 63. Where two
    /// pipelines agreed and the third differed, the arbiter — consistent
    /// across both orders — was right 31 times in 32, whichever side it took.
    /// Where no two pipelines agreed, its pick was wrong both times it made
    /// one. So `split` answers and `contested` declines.
    enum Confidence: Int, Comparable, Sendable, CustomStringConvertible {
        /// The arbiter picked differently in its two orders, or picked none.
        case none = 0
        /// The arbiter chose, but no reading had two pipelines behind it.
        case contested = 1
        /// Two pipelines agreed, one differed, and the arbiter chose the
        /// same reading in both orders.
        case split = 2
        /// Every pipeline read the same range.
        case unanimous = 3

        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

        var description: String {
            switch self {
            case .none: "none"
            case .contested: "contested"
            case .split: "split"
            case .unanimous: "unanimous"
            }
        }
    }

    /// Below this the agent declines.
    static let minimumConfidence = Confidence.split

    /// What the loop did, step by step, for the result screen and the tests.
    struct Trace: Sendable, Equatable {
        /// One entry per pipeline.
        var pipelines: [Pipeline] = []
        /// The arbiter's picks in its two orders, when the pipelines disagreed.
        var arbitration: [String] = []
        var confidence = Confidence.none
        /// The range the agent settled on; nil when the question names no time.
        var range: CalendarRange?

        struct Pipeline: Sendable, Equatable {
            /// What the reader copied; nil when it found no time words.
            var timeWords: String?
            var calls: [String] = []
            /// Nil only when the act session used up its calls.
            var observation: Observation?
            /// The act session called the tool more than once in a single
            /// step — it read the words as more than one range ("April and
            /// June" as April, and June) before being made to pick one.
            var splitCall = false
        }

        /// The time words the settled range came from, for the result card.
        var timeWords: String? {
            pipelines.compactMap(\.timeWords).first
        }

        var summary: String {
            let steps = pipelines.map { pipeline -> String in
                guard let words = pipeline.timeWords else { return "no time words" }
                let observed = pipeline.observation.map { "\($0.label): \($0.inWords)" } ?? "nothing"
                return "“\(words)” " + pipeline.calls.joined(separator: ", ") + " → " + observed
            }
            let settled = arbitration.isEmpty ? "" : " ⇒ arbiter: \(arbitration.joined(separator: "/"))"
            return steps.joined(separator: " | ") + settled + " ⇒ confidence: \(confidence)"
        }
    }

    /// One pipeline's result, labelled with the call that produced it.
    struct Observation: Sendable, Equatable {
        /// The kind's name and the arguments that went with it —
        /// "pastNMonths 3" — or `noDates`.
        var label: String
        /// Nil when the reading is that the question names no time.
        var range: CalendarRange?
        /// The time words it was read from; nil when the reader found none.
        var source: String?

        static let noDates = "noDates"

        var inWords: String { range?.inWords ?? "all dates — the question names no time" }
    }

    /// The range for `question`, or `AnswerDeclined` when the agent isn't
    /// confident enough in any.
    func run(_ question: String) async throws -> Trace {
        let trace = try await evaluate(question)
        guard trace.confidence >= Self.minimumConfidence else {
            throw AnswerDeclined(reason: "the readings of the dates didn't agree well enough", trace: trace.summary)
        }
        return trace
    }

    /// The whole loop and how confident it came out, without declining.
    func evaluate(_ question: String) async throws -> Trace {
        let forward = RangeKind.allCases
        async let first = pipeline(question, reading: TimeReading.self, kinds: forward)
        async let second = pipeline(question, reading: TimeFirstReading.self, kinds: RangeKind.reversed)
        async let third = pipeline(question, reading: TimeStrippedReading.self, kinds: RangeKind.monthsFirst)
        let pipelines = try await [first, second, third]
        return try await settle(pipelines, context: "Question: \(question)")
    }

    /// Reason, then act and observe.
    private func pipeline<Reading: TimeWordsReading>(
        _ question: String,
        reading: Reading.Type,
        kinds: [RangeKind]
    ) async throws -> Trace.Pipeline {
        let reader = LanguageModelSession(model: model, instructions: Instructions(Self.readerInstructions))
        let copied = try await reader.respond(
            to: question,
            generating: Reading.self,
            options: GenerationOptions(samplingMode: .greedy),
            contextOptions: ContextOptions(includeSchemaInPrompt: true)
        ).content.timeWords?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let copied, !copied.isEmpty else {
            return Trace.Pipeline(observation: Observation(label: Observation.noDates, source: nil))
        }
        return try await act(on: copied, kinds: kinds)
    }

    /// Every pipeline reading the same range settles it. Otherwise the
    /// arbiter chooses among the distinct readings, and the confidence says
    /// how much backing its choice had. A pipeline whose act session used up
    /// its calls counts as a reading of its own that nothing can match; one
    /// whose session split its call stays a candidate but backs nothing —
    /// the range it settled on is the one it was made to pick.
    private func settle(_ pipelines: [Trace.Pipeline], context: String) async throws -> Trace {
        var trace = Trace(pipelines: pipelines)
        let observed = pipelines.compactMap(\.observation)
        let backers = pipelines.filter { !$0.splitCall }.compactMap(\.observation)
        var distinct: [Observation] = []
        for observation in observed where !distinct.contains(where: { $0.range == observation.range }) {
            distinct.append(observation)
        }
        if backers.count == pipelines.count, distinct.count == 1 {
            trace.range = distinct[0].range
            trace.confidence = .unanimous
            return trace
        }
        guard !distinct.isEmpty else { return trace }

        let sources = distinct.map { reading in
            observed.filter { $0.range == reading.range }.map(\.source)
        }
        let picks = try await arbitrate(context, among: Array(zip(distinct, sources)))
        trace.arbitration = picks
        guard picks.allSatisfy({ $0 == picks[0] }),
              let chosen = distinct.first(where: { $0.label == picks[0] })
        else { return trace }
        let backing = distinct.map { reading in backers.filter { $0.range == reading.range }.count }.max() ?? 0
        trace.range = chosen.range
        trace.confidence = backing >= 2 ? .split : .contested
        return trace
    }

    /// One act session: a turn in which the model calls the tool, reads what
    /// came back, and — when that was a problem rather than a range — calls
    /// again, until a range comes back or the profile stops it.
    private func act(on timeWords: String, kinds: [RangeKind]) async throws -> Trace.Pipeline {
        let tool = DateRangeTool(arithmetic: arithmetic, kinds: kinds)
        let session = LanguageModelSession(profile: DateActProfile(
            model: model,
            instructions: Self.actInstructions(today: arithmetic),
            tool: tool
        ))
        let response = try await session.respond(
            to: "Time words: \(timeWords)",
            generating: RangeNote.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        var pipeline = Trace.Pipeline(timeWords: timeWords)
        for case .toolCalls(let calls) in response.transcriptEntries where calls.count > 1 {
            pipeline.splitCall = true
        }
        let labels = Self.labels(in: response.transcriptEntries)
        let observations = DateActProfile.observations(in: response.transcriptEntries)
        for (label, observation) in zip(labels, observations) {
            pipeline.calls.append(observation.problem.map { "\(label) ✗ \($0)" } ?? label)
            if let range = observation.range {
                pipeline.observation = range.isNone
                    ? Observation(label: Observation.noDates, source: timeWords)
                    : Observation(label: label, range: range, source: timeWords)
            }
        }
        return pipeline
    }

    /// The arbiter's picks, by label, with the observations in both orders.
    /// A pick only counts when both orders make it.
    private func arbitrate(_ context: String, among candidates: [(Observation, [String?])]) async throws -> [String] {
        async let forward = pick(context, from: candidates)
        async let backward = pick(context, from: candidates.reversed())
        return try await [forward, backward]
    }

    private static let neither = "noneOfThese"

    /// Each reading is shown with the words it was read from, so the
    /// arbiter can hold it against the question's own wording: without them
    /// it took "inYear 2026", read from a bare "year", over two readings of
    /// "past year", and "inOctober", read from the "month" in "my most
    /// expensive month", over "no time named".
    private func pick(_ context: String, from candidates: [(Observation, [String?])]) async throws -> String {
        let lines = candidates.map { observation, sources in
            var seen: [String] = []
            for source in sources.map({ $0.map { "“\($0)”" } ?? "no time words" }) where !seen.contains(source) {
                seen.append(source)
            }
            return "- \(observation.label), read from \(seen.joined(separator: " and ")): \(observation.inWords)"
        }.joined(separator: "\n")
        let arbiter = LabelledChoice(model: model, instructions: Self.arbiterInstructions(today: arithmetic))
        return try await arbiter.pick(
            among: candidates.map(\.0.label) + [Self.neither],
            prompt: "\(context)\nReadings:\n\(lines)"
        )
    }

    /// Every call made during one turn, as the kind's name and the
    /// arguments it takes: "pastNMonths 3".
    ///
    /// Arguments the kind ignores are left off. Labelled with them, the
    /// arbiter took "sinceStartOfThisMonth 2026" — this year's number riding
    /// along unused — over two readings of "sinceStartOfThisYear 1" for
    /// "since the start of the year", in two runs out of two.
    ///
    /// Worded as phrases instead — "the past day", "last week" — the
    /// readings pulled the arbiter away from "no dates" five times in seven
    /// where the question named no time, and the act's phrase list let "the
    /// past year" swallow "last year".
    private static func labels(in entries: some Collection<Transcript.Entry>) -> [String] {
        var labels: [String] = []
        for case .toolCalls(let calls) in entries {
            for call in calls {
                let arguments = call.arguments
                let name = (try? arguments.value(String.self, forProperty: "kind")) ?? "?"
                let kind = RangeKind(rawValue: name)
                var parts = [name]
                let taken = [
                    ("count", kind?.takesCount ?? true),
                    ("throughMonth", kind?.takesThroughMonth ?? true),
                    ("year", kind?.takesYear ?? true),
                ]
                for (name, takes) in taken where takes {
                    guard let value = try? arguments.value(GeneratedContent?.self, forProperty: name),
                          value.kind != .null
                    else { continue }
                    parts.append(value.jsonString.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
                }
                labels.append(parts.joined(separator: " "))
            }
        }
        return labels
    }

    // MARK: Prompts

    private static let readerInstructions = """
        You copy out the words of a question about the user's own card spending that say when \
        the spending happened.

        Time words name a stretch of the calendar: a day, a week, a weekend, a month or a \
        month's name, a year, or a number of days, weeks, months, or years. Copy them exactly \
        as the question writes them, together with the word right in front of them. Add \
        nothing, change nothing, and copy no other words of the question.

        When the question names no stretch of the calendar, timeWords is null.
        """

    private static func actInstructions(today arithmetic: CalendarArithmetic) -> String {
        """
        You work out the dates some time words cover. Today is \
        \(arithmetic.words(for: arithmetic.today)).

        Call dateRange once, with the kind of range the time words name and the number, \
        month, or year they give. The tool does all the counting — never work out a date \
        yourself.

        Some words only look like time words. Words that ask which day, month, or year — \
        rather than naming one — name no stretch of the calendar, and neither does "last" or \
        "first" with no day, week, month, or year after it, nor a day, week, month, or year \
        with nothing saying which one. For those, pick the kind named the way they are, or \
        noTimeNamed.
        """
    }

    private static func arbiterInstructions(today arithmetic: CalendarArithmetic) -> String {
        """
        Readings of when the spending in a question happened came back different, each with \
        the words it was read from. Today is \(arithmetic.words(for: arithmetic.today)). Pick \
        the reading whose dates are what the question's own words say, or noneOfThese when \
        none of them is.
        """
    }
}

// MARK: - Declining

/// An answer the pipeline won't give, because the model's own readings
/// didn't converge on one. Shown to the person as "couldn't work that out"
/// rather than as a guess.
nonisolated struct AnswerDeclined: Error, LocalizedError, Sendable {
    var reason: String
    /// What the loop did on its way there, for the tests' logs.
    var trace: String = ""

    var errorDescription: String? { "Couldn't work out a reliable answer: \(reason)." }
}

// MARK: - What the sessions generate

/// Either of the two readers' answers.
nonisolated protocol TimeWordsReading: Generable, Sendable {
    var timeWords: String? { get }
}

/// The asks-first reader: what the question wants to find out, then its time
/// words.
///
/// `asks` is a relief valve generated first. "When did I last…", "my
/// first", "which month" each carry a word the model wants to write down
/// somewhere; saying what the question wants to find out gives those words a
/// home outside `timeWords`. Asked first it can also swallow "this year" and
/// the word in front of a month — which is why it has a partner.
@Generable(
    description: "The words in a spending question that say when the spending happened.",
    representNilExplicitlyInGeneratedContent: true
)
nonisolated struct TimeReading: TimeWordsReading, Equatable {
    @Guide(description: "What the question wants to find out, in a few words.")
    var asks: String?

    @Guide(description: "The words that say when the spending happened, copied exactly as written. Null when the question names no time.")
    var timeWords: String?
}

/// The time-first reader: the same fields the other way round. It misses
/// less and lets more in.
@Generable(
    description: "The words in a spending question that say when the spending happened.",
    representNilExplicitlyInGeneratedContent: true
)
nonisolated struct TimeFirstReading: TimeWordsReading, Equatable {
    @Guide(description: "The words that say when the spending happened, copied exactly as written. Null when the question names no time.")
    var timeWords: String?

    @Guide(description: "What the question wants to find out, in a few words.")
    var asks: String?
}

/// The stripping reader: the question rewritten with its time words taken
/// out, then the words it took out. Rewriting the whole question makes it
/// look at every part of it, which is where the other two let "this year"
/// slip past after "biggest" or "which merchant".
@Generable(
    description: "A spending question with its time words taken out, and those words.",
    representNilExplicitlyInGeneratedContent: true
)
nonisolated struct TimeStrippedReading: TimeWordsReading, Equatable {
    @Guide(description: "The question rewritten with the words that say when taken out, and nothing else changed.")
    var withoutTimeWords: String

    @Guide(description: "The words that were taken out, exactly as the question wrote them. Null when nothing was.")
    var timeWords: String?
}

/// What an act session writes after its tool call. The range itself is read
/// from the tool's output, so this is only the turn's closing line.
@Generable(description: "A one-line note on the range the tool returned.")
nonisolated struct RangeNote: Equatable, Sendable {
    @Guide(description: "The range's first and last day, as the tool wrote them.")
    var note: String
}

// MARK: - The act session's setup

/// An act session: the calendar tool, called until it hands back a range.
///
/// Read fresh before every step of the turn, this profile keeps tool calling
/// required while the observations since the prompt are all problems, and
/// turns it off once one is a range — or once the turn has made
/// `maximumCalls` calls, so a session that can't find a valid call still
/// ends.
nonisolated struct DateActProfile: LanguageModelSession.DynamicProfile {
    @SessionProperty(\.history) var history

    let model: SystemLanguageModel
    let instructions: String
    let tool: DateRangeTool

    static let maximumCalls = 3

    var body: some DynamicProfile {
        let lastPrompt = history.lastIndex { entry in
            if case .prompt = entry { true } else { false }
        }
        let observations = lastPrompt.map { Self.observations(in: history[$0...]) } ?? []
        let done = observations.contains { $0.range != nil } || observations.count >= Self.maximumCalls
        LanguageModelSession.Profile {
            Instructions(instructions)
            tool
        }
        .model(model)
        .samplingMode(.greedy)
        .toolCallingMode(done ? .disallowed : .required)
    }

    /// Every observation the tool handed back in `entries`, in call order.
    static func observations(in entries: some Collection<Transcript.Entry>) -> [DateRangeObservation] {
        var observations: [DateRangeObservation] = []
        for case .toolOutput(let output) in entries {
            for case .structure(let segment) in output.segments {
                if let observation = try? DateRangeObservation(segment.content) { observations.append(observation) }
            }
        }
        return observations
    }
}
