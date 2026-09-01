import Foundation
import FoundationModels

/// Runs one natural-language question through the selected engine and reports
/// both the structured result and what it cost.
@MainActor
@Observable
final class QueryParser {
    enum Phase {
        case idle
        case parsing
        case parsed(TransactionQuery, Metrics)
        case failed(String)
    }

    /// What the round trip cost. Token counts come from `Response.usage`,
    /// which is new in iOS 27.
    struct Metrics: Equatable {
        var engine: QueryEngine
        /// Wall time for the whole parse, so the two engines compare directly.
        var latency: Duration
        /// The slice of that spent in SwiftyChronoX. Nil on the Foundation
        /// Models run, which has no separate date step.
        var dateLatency: Duration?
        var inputTokens: Int
        var cachedInputTokens: Int
        var outputTokens: Int
        /// The words SwiftyChronoX matched, when it matched any.
        var datePhrase: String?

        var latencyDescription: String { latency.latencyDescription }
        var dateLatencyDescription: String? { dateLatency?.latencyDescription }

        /// Says which half of the answer came from where, and what the library
        /// keyed off — the phrase it matched is usually the thing worth arguing
        /// with. Nil on the Foundation Models run, which has no second half.
        var dateNote: String? {
            guard let dateLatency = dateLatencyDescription else { return nil }
            guard let datePhrase else {
                return "SwiftyChronoX found no date in \(dateLatency). "
                    + "Merchant and amount come from the model."
            }
            return "Dates from SwiftyChronoX in \(dateLatency), matching \u{201C}\(datePhrase)\u{201D}. "
                + "Merchant and amount come from the model."
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var engine: QueryEngine = .swiftyChronoX

    /// The most permissive guardrails Apple exposes.
    ///
    /// Spending questions trip the default filter more often than you'd expect —
    /// a merchant name alone can read as sensitive out of context — and a refusal
    /// here is a false positive, since the input is the user's own text being
    /// reshaped into filters rather than anything the model is asked to author.
    private let model = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

    private let chrono = ChronoDateResolver()
    private var chronoIsWarm = false

    /// A session built and warmed ahead of the next question.
    ///
    /// Each question gets its own session so one parse can't colour the next —
    /// a shared transcript would let a previous merchant or date range leak into
    /// the following answer. Warming the next one up front keeps that isolation
    /// from showing up as latency.
    ///
    /// The two engines carry different instructions, so a warm session is only
    /// good for the engine it was built for.
    private struct WarmSession {
        let session: LanguageModelSession
        let engine: QueryEngine
        let day: Date
    }

    private var ready: WarmSession?

    /// The parse currently in flight, kept so clearing the search bar can drop it.
    private var activeParse: Task<Void, Never>?

    var availability: SystemLanguageModel.Availability { model.availability }

    /// Builds and warms what the next question will need, if it isn't warm already.
    func prewarm() {
        guard model.isAvailable else { return }

        if engine == .swiftyChronoX && !chronoIsWarm {
            chrono.warmUp()
            chronoIsWarm = true
        }

        let reference = DateReference()
        guard ready?.engine != engine || ready?.day != reference.today else { return }

        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(Self.instructions(for: engine, reference: reference))
        )
        session.prewarm()
        ready = WarmSession(session: session, engine: engine, day: reference.today)
    }

    /// Switches engines and answers the question again with the new one — the
    /// point of the tab bar being to see the same query both ways.
    func select(_ engine: QueryEngine, rerunning text: String) {
        guard engine != self.engine else { return }
        self.engine = engine

        // Warm the new engine before re-running, so the switch itself doesn't
        // land in the latency the run is about to report.
        prewarm()

        switch phase {
        case .idle:
            break
        case .parsing, .parsed, .failed:
            // Whatever is on screen belongs to the engine we just left.
            // `parse` falls back to `reset` if the search bar is empty.
            parse(text)
        }
    }

    func parse(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            reset()
            return
        }

        activeParse?.cancel()
        phase = .parsing
        // Pinned here so a tab switch mid-flight can't retag this run.
        let selected = engine
        activeParse = Task { await run(question, using: selected) }
    }

    /// Drops whatever is in flight and goes back to the example list — what an
    /// emptied or dismissed search bar should leave behind.
    func reset() {
        activeParse?.cancel()
        activeParse = nil
        phase = .idle
        prewarm()
    }

    private func run(_ question: String, using engine: QueryEngine) async {
        // A cancelled parse leaves its session spent, so the next one still
        // needs a warm replacement no matter how this run ends.
        defer { prewarm() }

        let reference = DateReference()
        let session = takeSession(for: engine, reference: reference)
        let clock = ContinuousClock()
        let start = clock.now

        do {
            switch engine {
            case .foundationModels:
                let response = try await session.respond(
                    to: question,
                    generating: TransactionQuery.self,
                    // Greedy sampling keeps repeated runs of the same question
                    // comparable, which is the whole point of a latency playground.
                    options: GenerationOptions(samplingMode: .greedy),
                    // Extraction needs the schema in the prompt but no deliberation.
                    contextOptions: ContextOptions(includeSchemaInPrompt: true)
                )
                let usage = response.usage
                guard !Task.isCancelled else { return }
                phase = .parsed(
                    response.content,
                    metrics(engine: engine, latency: clock.now - start, usage: usage)
                )

            case .swiftyChronoX:
                let dateStart = clock.now
                let dates = chrono.resolve(question, reference: reference)
                let dateLatency = clock.now - dateStart

                let response = try await session.respond(
                    to: question,
                    generating: MerchantAmountQuery.self,
                    options: GenerationOptions(samplingMode: .greedy),
                    contextOptions: ContextOptions(includeSchemaInPrompt: true)
                )
                let usage = response.usage
                guard !Task.isCancelled else { return }
                phase = .parsed(
                    TransactionQuery(response.content, dates: dates),
                    metrics(
                        engine: engine,
                        latency: clock.now - start,
                        usage: usage,
                        dateLatency: dateLatency,
                        datePhrase: dates.matchedText
                    )
                )
            }
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func metrics(
        engine: QueryEngine,
        latency: Duration,
        usage: LanguageModelSession.Usage,
        dateLatency: Duration? = nil,
        datePhrase: String? = nil
    ) -> Metrics {
        Metrics(
            engine: engine,
            latency: latency,
            dateLatency: dateLatency,
            inputTokens: usage.input.totalTokenCount,
            cachedInputTokens: usage.input.cachedTokenCount,
            outputTokens: usage.output.totalTokenCount,
            datePhrase: datePhrase
        )
    }

    private func takeSession(for engine: QueryEngine, reference: DateReference) -> LanguageModelSession {
        if let ready, ready.engine == engine, ready.day == reference.today {
            self.ready = nil
            return ready.session
        }
        return LanguageModelSession(
            model: model,
            instructions: Instructions(Self.instructions(for: engine, reference: reference))
        )
    }

    private static func instructions(for engine: QueryEngine, reference: DateReference) -> String {
        switch engine {
        case .foundationModels: fullInstructions(for: reference)
        case .swiftyChronoX: merchantAndAmountInstructions
        }
    }

    private static let amountRules = """
        AMOUNTS are numbers in dollars — never negative.
        - "above $10", "over $10", "more than $10" -> fromAmount 10, toAmount null
        - "under $50", "less than $50" -> fromAmount null, toAmount 50
        - "between $10 and $50" -> fromAmount 10, toAmount 50
        - a bare amount with no comparison, or a vague one like "around $20" -> both null
        """

    private static func fullInstructions(for reference: DateReference) -> String {
        """
        You turn a person's question about their own card transactions into search filters.

        Fill in only what the question actually says. Anything it does not mention stays \
        null — never invent a merchant, an amount, or a date.

        \(amountRules)

        DATES are always formatted yyyy-MM-dd. Do not work any date out yourself. Today is \
        \(reference.todayString), and every range you might need is already resolved here — \
        find the one the question refers to and copy its two dates exactly:

        \(reference.resolvedRanges)

        An open-ended phrase — "since", "from the beginning of", "so far this" — starts at that \
        period's first day and ends today, \(reference.todayString).

        If the question mentions no time at all, leave both dates null.
        """
    }

    /// SwiftyChronoX has already taken the dates, so this leaves them out
    /// entirely rather than asking for an answer that would be thrown away.
    private static let merchantAndAmountInstructions = """
        You turn a person's question about their own card transactions into search filters.

        Fill in only what the question actually says. Anything it does not mention stays \
        null — never invent a merchant or an amount.

        \(amountRules)

        Ignore any dates or time periods in the question. Something else handles those, and a \
        date is never a merchant name: "Show my Starbucks spending in the past 40 days" is \
        merchantName "Starbucks" and nothing else.
        """
}
