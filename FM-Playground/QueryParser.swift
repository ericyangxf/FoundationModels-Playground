import Foundation
import FoundationModels

/// Runs one natural-language question through the on-device model and reports
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
        var latency: Duration
        var inputTokens: Int
        var cachedInputTokens: Int
        var outputTokens: Int
        /// What the category session cost, when it answered. Nil when it failed.
        var categoryRun: CategoryRun?
        /// Why the category list came back empty-handed, when the reason is an
        /// error over there rather than a question with no category in it.
        var categoryNote: String?

        var latencyDescription: String { latency.latencyDescription }

        /// Everything the main card should say under its numbers.
        var footnote: String? { categoryNote }
    }

    private(set) var phase: Phase = .idle

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

    /// A session built and warmed ahead of the next question.
    ///
    /// Each question gets its own session so one parse can't colour the next —
    /// a shared transcript would let a previous merchant or date range leak into
    /// the following answer. Warming the next one up front keeps that isolation
    /// from showing up as latency.
    ///
    /// The instructions spell out the date ranges for one day, so a warm
    /// session is only good for the day it was built for.
    private struct WarmSession {
        let session: LanguageModelSession
        let day: Date
    }

    private var ready: WarmSession?

    /// A warm session for the category parse. Day-independent, since its
    /// instructions never change.
    private var categoryReady: LanguageModelSession?

    /// The parse currently in flight, kept so clearing the search bar can drop it.
    private var activeParse: Task<Void, Never>?

    var availability: SystemLanguageModel.Availability { model.availability }

    /// The user-facing name of the on-device model behind this page, such as
    /// "AFM 3 Core Advanced".
    var modelName: String { model.variant.displayName }

    /// Builds and warms what the next question will need, if it isn't warm already.
    ///
    /// `reference` is the day the next question will be resolved against —
    /// today on the Query tab, the statement date on the Transactions tab.
    func prewarm(reference: DateReference? = nil) {
        guard model.isAvailable else { return }

        if categoryReady == nil {
            let session = LanguageModelSession(
                model: model,
                instructions: Instructions(Self.categoryInstructions)
            )
            session.prewarm()
            categoryReady = session
        }

        let reference = reference ?? DateReference()
        guard ready?.day != reference.today else { return }

        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(Self.instructions(for: reference))
        )
        session.prewarm()
        ready = WarmSession(session: session, day: reference.today)
    }

    func parse(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            reset()
            return
        }

        activeParse?.cancel()
        phase = .parsing
        activeParse = Task { await run(question) }
    }

    /// Drops whatever is in flight and goes back to the example list — what an
    /// emptied or dismissed search bar should leave behind.
    func reset() {
        activeParse?.cancel()
        activeParse = nil
        phase = .idle
        prewarm()
    }

    private func run(_ question: String) async {
        // A cancelled parse leaves its session spent, so the next one still
        // needs a warm replacement no matter how this run ends.
        defer { prewarm() }

        do {
            let (parsed, metrics) = try await parsedQuery(
                for: question,
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
        reference: DateReference
    ) async throws -> (ParsedQuery, Metrics) {
        let session = takeSession(for: reference)

        // Categories come from a session of their own: the taxonomy is a whole
        // schema by itself, and a separate context window keeps it from
        // crowding the merchant, amount and date parse. Started first so it
        // runs concurrently with the respond below.
        let categorySession = takeCategorySession()
        async let categoryOutcome = Self.parseCategories(question, in: categorySession)

        let clock = ContinuousClock()
        let start = clock.now

        let response = try await session.respond(
            to: question,
            generating: GeneratedQuery.self,
            // Greedy sampling keeps repeated runs of the same question
            // comparable, which is the whole point of a latency playground.
            options: GenerationOptions(samplingMode: .greedy),
            // Extraction needs the schema in the prompt but no deliberation.
            contextOptions: ContextOptions(includeSchemaInPrompt: true)
        )
        let usage = response.usage
        // Clocked before the category await, so this stays the main run's own
        // time even when the second session finishes later.
        let latency = clock.now - start
        let outcome = await categoryOutcome
        return (
            ParsedQuery(filters: TransactionQuery(response.content), categories: outcome.categories),
            Metrics(
                latency: latency,
                inputTokens: usage.input.totalTokenCount,
                cachedInputTokens: usage.input.cachedTokenCount,
                outputTokens: usage.output.totalTokenCount,
                categoryRun: outcome.run,
                categoryNote: outcome.note
            )
        )
    }

    private func takeSession(for reference: DateReference) -> LanguageModelSession {
        if let ready, ready.day == reference.today {
            self.ready = nil
            return ready.session
        }
        return LanguageModelSession(
            model: model,
            instructions: Instructions(Self.instructions(for: reference))
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

    private static func instructions(for reference: DateReference) -> String {
        """
        You turn a person's question about their own card transactions into search filters.

        Fill in only what the question actually says. Anything it does not mention stays \
        null — never invent a merchant, an amount, or a date.

        A question can name a specific business — "Starbucks", "Canadian Tire" — or only \
        a kind of spending — "grocery", "flights". The business goes in merchantName, \
        spelled as written; a kind of spending goes in spendingKind, never in merchantName. \
        A kind of store — "bakery", "hardware store" — is a kind of spending too. A city, \
        province, or country goes in place, never in merchantName. A date or time period \
        is never a merchant name.

        amountPhrase is the question's amount words copied exactly — "under $N", "around \
        $N" — or null when it has none.

        AMOUNTS are set only by an explicit comparison in the question.
        - "above $N", "over $N", "more than $N" -> fromAmount N, toAmount null
        - "under $N", "less than $N" -> fromAmount null, toAmount N
        - "between $N and $M" -> fromAmount N, toAmount M
        - a bare amount, or a vague one like "around $N" -> both null

        DATES are always formatted yyyy-MM-dd. Do not work any date out yourself. Today is \
        \(reference.todayString), and every range you might need is already resolved here — \
        find the one the question refers to and copy its two dates exactly:

        \(reference.resolvedRanges)

        An open-ended phrase — "since", "from the beginning of", "so far this" — starts at that \
        period's first day and ends today, \(reference.todayString).

        If the question mentions no time at all, leave both dates null.
        """
    }

    /// The category session's whole prompt. The taxonomy itself rides in the
    /// generated schema, not here.
    private static let categoryInstructions = """
        You identify the kinds of spending a question about the user's own card \
        transactions refers to.

        First copy the question's words for what the money went on into spendingWords, then \
        pick the categories those words name. Pick a category only when the question names a \
        kind of spending. Pick every kind it names, in the order they appear.

        Everyday words and the categories they mean:
        - flights → airlines; hotel → hotels; rental car → carRental; rides, taxi, rideshare → \
        taxiAndRideshare, never publicTransit; bus, subway, transit → publicTransit; parking, \
        tolls → parkingAndTolls; gas, fuel → gasStations
        - grocery → groceries; eating out, dining, takeout → restaurants; alcohol, beer, \
        wine → liquorStores
        - clothes, shoes → clothing; gadgets → electronics; hardware → homeImprovement; \
        books → booksAndNews; toys → toysAndHobbies
        - phone bill, internet → phoneInternetAndCable; streaming, music or video \
        subscriptions → streamingAndDigitalGoods; hydro, electricity → utilities
        - pharmacy, prescriptions → pharmacies; doctor, dentist → healthcare; gym → \
        gymsAndFitness; pet, vet → petsAndVets; haircut, salon → beautyAndSpa
        - movies, concerts, shows → entertainment; donations → charity; tuition → education; \
        daycare → childcare; taxes → government

        Most questions name none. A business name — "Starbucks", "Walmart", "Air \
        Canada" — is not a kind of spending, and neither are amounts, dates, or \
        general words like "spending", "purchases", "money", "everything". A question asking \
        which category comes out on top names none itself. With none named, return an empty \
        list.
        """
}

/// The second session's own numbers, kept apart from Metrics so the main run's
/// stats stay its own.
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
