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
        case parsed(ParsedQuery, Metrics)
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
        /// What the category session cost, when it answered. Nil when it failed.
        var categoryRun: CategoryRun?
        /// Why the category list came back empty-handed, when the reason is an
        /// error over there rather than a question with no category in it.
        var categoryNote: String?

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

        /// Everything the main card should say under its numbers.
        var footnote: String? {
            let parts = [dateNote, categoryNote].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: "\n")
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

    /// A warm session for the category parse. Engine- and day-independent,
    /// since its instructions never change.
    private var categoryReady: LanguageModelSession?

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

        if categoryReady == nil {
            let session = LanguageModelSession(
                model: model,
                instructions: Instructions(Self.categoryInstructions)
            )
            session.prewarm()
            categoryReady = session
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

        do {
            let (parsed, metrics) = try await parsedQuery(
                for: question,
                using: engine,
                reference: DateReference()
            )
            guard !Task.isCancelled else { return }
            phase = .parsed(parsed, metrics)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Runs one question end to end and hands back both halves of the answer
    /// along with what they cost, without touching `phase`.
    ///
    /// The view goes in through `parse(_:)`, which owns the phase and the
    /// cancellation; the accuracy tests call this directly, so what they measure
    /// is the same path the app takes.
    func parsedQuery(
        for question: String,
        using engine: QueryEngine,
        reference: DateReference
    ) async throws -> (ParsedQuery, Metrics) {
        let session = takeSession(for: engine, reference: reference)

        // Categories come from a session of their own: the taxonomy is a whole
        // schema by itself, and a separate context window keeps it from
        // crowding the merchant-and-amount parse. Started first so it runs
        // concurrently with the respond below.
        let categorySession = takeCategorySession()
        async let categoryOutcome = Self.parseCategories(question, in: categorySession)

        let clock = ContinuousClock()
        let start = clock.now

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
            // Clocked before the category await, so this stays the main
            // run's own time even when the second session finishes later.
            let latency = clock.now - start
            let outcome = await categoryOutcome
            return (
                ParsedQuery(filters: response.content, categories: outcome.categories),
                metrics(engine: engine, latency: latency, usage: usage, outcome: outcome)
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
            let latency = clock.now - start
            let outcome = await categoryOutcome
            return (
                ParsedQuery(
                    filters: TransactionQuery(response.content, dates: dates),
                    categories: outcome.categories
                ),
                metrics(
                    engine: engine,
                    latency: latency,
                    usage: usage,
                    dateLatency: dateLatency,
                    datePhrase: dates.matchedText,
                    outcome: outcome
                )
            )
        }
    }

    private func metrics(
        engine: QueryEngine,
        latency: Duration,
        usage: LanguageModelSession.Usage,
        dateLatency: Duration? = nil,
        datePhrase: String? = nil,
        outcome: CategoryOutcome
    ) -> Metrics {
        Metrics(
            engine: engine,
            latency: latency,
            dateLatency: dateLatency,
            inputTokens: usage.input.totalTokenCount,
            cachedInputTokens: usage.input.cachedTokenCount,
            outputTokens: usage.output.totalTokenCount,
            datePhrase: datePhrase,
            categoryRun: outcome.run,
            categoryNote: outcome.note
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

    private func takeCategorySession() -> LanguageModelSession {
        if let categoryReady {
            self.categoryReady = nil
            return categoryReady
        }
        return LanguageModelSession(
            model: model,
            instructions: Instructions(Self.categoryInstructions)
        )
    }

    /// Runs the category question through its own session, always coming back
    /// with an answer — a failure over here downgrades to "no categories" with
    /// a note, rather than sinking the parse carrying merchant and amounts.
    private nonisolated static func parseCategories(
        _ question: String,
        in session: LanguageModelSession
    ) async -> CategoryOutcome {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let response = try await session.respond(
                to: question,
                generating: CategoryQuery.self,
                options: GenerationOptions(samplingMode: .greedy),
                contextOptions: ContextOptions(includeSchemaInPrompt: true)
            )
            // Even greedy sampling can repeat itself inside a list.
            var seen = Set<SpendingCategory>()
            let categories = response.content.categories.filter { seen.insert($0).inserted }
            let usage = response.usage
            return CategoryOutcome(
                categories: categories,
                run: CategoryRun(
                    latency: clock.now - start,
                    inputTokens: usage.input.totalTokenCount,
                    cachedInputTokens: usage.input.cachedTokenCount,
                    outputTokens: usage.output.totalTokenCount
                )
            )
        } catch is CancellationError {
            return CategoryOutcome()
        } catch {
            return CategoryOutcome(note: "Category session failed: \(error.localizedDescription)")
        }
    }

    private static func instructions(for engine: QueryEngine, reference: DateReference) -> String {
        switch engine {
        case .foundationModels: fullInstructions(for: reference)
        case .swiftyChronoX: merchantAndAmountInstructions
        }
    }

    private static let amountRules = """
        AMOUNTS are set only by an explicit comparison in the question.
        - "above $N", "over $N", "more than $N" -> fromAmount N, toAmount null
        - "under $N", "less than $N" -> fromAmount null, toAmount N
        - "between $N and $M" -> fromAmount N, toAmount M
        - a bare amount, or a vague one like "around $N" -> both null
        """

    private static func fullInstructions(for reference: DateReference) -> String {
        """
        You turn a person's question about their own card transactions into search filters.

        Fill in only what the question actually says. Anything it does not mention stays \
        null — never invent a merchant, an amount, or a date.

        A merchant is a specific business named in the question — "Starbucks", "Canadian \
        Tire". A word for what was bought rather than for a business is never a merchant; \
        when no business is named, merchantName is null.

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

        A question can name a specific business — "Starbucks", "Canadian Tire" — or only \
        a kind of spending — "grocery", "flights". The business goes in merchantName, \
        spelled as written; a kind of spending goes in spendingKind, never in merchantName.

        amountPhrase is the question's amount words copied exactly — "under $N", "around \
        $N" — or null when it has none.

        \(amountRules)

        Ignore any dates or time periods in the question. Something else handles those, and a \
        date is never a merchant name: "Show my Starbucks spending in the past 40 days" is \
        merchantName "Starbucks" and nothing else.
        """

    /// The category session's whole prompt. The taxonomy itself rides in the
    /// generated schema, not here.
    private static let categoryInstructions = """
        You identify the kinds of spending a question about the user's own card \
        transactions refers to.

        Pick a category only when the question names a kind of spending — "flights", \
        "eating out". Pick every kind it names, in the order they appear. "rides" means \
        taxiAndRideshare, never publicTransit; "grocery" means groceries.

        Most questions name none. A business name — "Starbucks", "Walmart", "Air \
        Canada" — is not a kind of spending, and neither are amounts, dates, or \
        general words like "spending", "purchases", "everything". With none named, \
        return an empty list.
        """
}

/// The second session's own numbers, kept apart from Metrics so the main run's
/// stats still compare cleanly across engines.
nonisolated struct CategoryRun: Equatable, Sendable {
    var latency: Duration
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int

    /// Formatting rides on a main-actor helper, and only the view reads this.
    @MainActor var latencyDescription: String { latency.latencyDescription }
}

/// Whatever the category session came back with.
nonisolated struct CategoryOutcome: Sendable {
    var categories: [SpendingCategory] = []
    var run: CategoryRun?
    var note: String?
}
