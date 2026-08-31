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
        case parsed(TransactionQuery, Metrics)
        case failed(String)
    }

    /// What the round trip cost. Token counts come from `Response.usage`,
    /// which is new in iOS 27.
    struct Metrics: Equatable {
        var latency: Duration
        var inputTokens: Int
        var cachedInputTokens: Int
        var outputTokens: Int

        var latencyDescription: String {
            let parts = latency.components
            let milliseconds = Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
            return milliseconds < 1000
                ? String(format: "%.0f ms", milliseconds)
                : String(format: "%.2f s", milliseconds / 1000)
        }
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
    private var readySession: LanguageModelSession?
    private var readySessionDay: Date?

    /// The parse currently in flight, kept so clearing the search bar can drop it.
    private var activeParse: Task<Void, Never>?

    var availability: SystemLanguageModel.Availability { model.availability }

    /// Builds and warms the session the next question will use, if there isn't
    /// already a warm one for today.
    func prewarm() {
        guard model.isAvailable else { return }
        let reference = DateReference()
        guard readySession == nil || readySessionDay != reference.today else { return }

        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(Self.instructions(for: reference))
        )
        session.prewarm()
        readySession = session
        readySessionDay = reference.today
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

        let reference = DateReference()
        let session = takeSession(for: reference)
        let clock = ContinuousClock()
        let start = clock.now

        do {
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
                Metrics(
                    latency: clock.now - start,
                    inputTokens: usage.input.totalTokenCount,
                    cachedInputTokens: usage.input.cachedTokenCount,
                    outputTokens: usage.output.totalTokenCount
                )
            )
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func takeSession(for reference: DateReference) -> LanguageModelSession {
        defer { readySession = nil }
        if let readySession, readySessionDay == reference.today {
            return readySession
        }
        return LanguageModelSession(
            model: model,
            instructions: Instructions(Self.instructions(for: reference))
        )
    }

    private static func instructions(for reference: DateReference) -> String {
        """
        You turn a person's question about their own card transactions into search filters.

        Fill in only what the question actually says. Anything it does not mention stays \
        null — never invent a merchant, an amount, or a date.

        AMOUNTS are numbers in dollars — 10, 25.50 — never text and never negative.
        - "above $10", "over $10", "more than $10" -> fromAmount 10, toAmount null
        - "under $50", "less than $50" -> fromAmount null, toAmount 50
        - "between $10 and $50" -> fromAmount 10, toAmount 50
        - a bare amount with no comparison, or a vague one like "around $20" -> both null

        DATES are always formatted yyyy-MM-dd. Do not work any date out yourself. Today is \
        \(reference.todayString), and every range you might need is already resolved here — \
        find the one the question refers to and copy its two dates exactly:

        \(reference.resolvedRanges)

        An open-ended phrase — "since", "from the beginning of", "so far this" — starts at that \
        period's first day and ends today, \(reference.todayString).

        If the question mentions no time at all, leave both dates null.
        """
    }
}
