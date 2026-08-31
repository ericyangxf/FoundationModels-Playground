import Foundation
import FoundationModels

/// Decides which search system a question belongs to, and reports what the
/// decision cost.
///
/// Same shape as `QueryParser`, one step earlier in the pipeline: this picks the
/// search system, and only the transaction route goes on to be parsed into
/// filters.
@MainActor
@Observable
final class QueryRouter {
    enum Phase {
        case idle
        case routing
        case routed(RouteDecision, Metrics)
        case failed(String)
    }

    /// What the round trip cost. Token counts come from `Response.usage`.
    struct Metrics: Equatable {
        var latency: Duration
        var inputTokens: Int
        var cachedInputTokens: Int
        var outputTokens: Int

        var latencyDescription: String { latency.latencyDescription }
    }

    private(set) var phase: Phase = .idle

    /// The most permissive guardrails Apple exposes, for the same reason the
    /// parser uses them: the input is the user's own question, and a refusal
    /// here would be a false positive on text nobody is asking the model to
    /// author.
    private let model = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

    /// A session built and warmed ahead of the next question.
    ///
    /// One session per question, so a previous route can't colour the next.
    /// These instructions carry no date, so unlike the parser's there is nothing
    /// to invalidate a warm session overnight.
    private var ready: LanguageModelSession?

    /// The run currently in flight, kept so clearing the search bar can drop it.
    private var activeRun: Task<Void, Never>?

    var availability: SystemLanguageModel.Availability { model.availability }

    func prewarm() {
        guard model.isAvailable, ready == nil else { return }

        let session = LanguageModelSession(
            model: model,
            instructions: Instructions(Self.instructions)
        )
        session.prewarm()
        ready = session
    }

    func route(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            reset()
            return
        }

        activeRun?.cancel()
        phase = .routing
        activeRun = Task { await run(question) }
    }

    /// Drops whatever is in flight and goes back to the example list — what an
    /// emptied or dismissed search bar should leave behind.
    func reset() {
        activeRun?.cancel()
        activeRun = nil
        phase = .idle
        prewarm()
    }

    private func run(_ question: String) async {
        // A cancelled run leaves its session spent, so the next one still needs
        // a warm replacement no matter how this one ends.
        defer { prewarm() }

        let session = takeSession()
        let clock = ContinuousClock()
        let start = clock.now

        do {
            let response = try await session.respond(
                to: question,
                generating: RouteDecision.self,
                // Greedy sampling keeps repeated runs of the same question
                // comparable, which is the whole point of a latency playground.
                options: GenerationOptions(samplingMode: .greedy),
                // A two-way choice needs the schema in the prompt but no
                // deliberation.
                contextOptions: ContextOptions(includeSchemaInPrompt: true)
            )
            let usage = response.usage
            guard !Task.isCancelled else { return }
            phase = .routed(
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

    private func takeSession() -> LanguageModelSession {
        if let ready {
            self.ready = nil
            return ready
        }
        return LanguageModelSession(
            model: model,
            instructions: Instructions(Self.instructions)
        )
    }

    /// The examples do most of the work here. The line between the two routes is
    /// easier to show than to define, and the model is being asked for one of
    /// two labels rather than a judgement it has to reason its way to.
    private static let instructions = """
        You decide which of two search systems should answer a person's question in their \
        banking app. Pick exactly one.

        TRANSACTION SEARCH answers questions about the person's own card and account \
        activity — what they bought, where, when, how much, refunds, recurring charges, a \
        payment they are looking for. Answering one means reading their transaction history.
        - "How much I spent on Starbucks this month?"
        - "Show Uber rides under $25 last week"
        - "Did my rent payment go through?"
        - "my biggest purchase last year"

        COVEO SEARCH answers everything else — general questions, product and policy \
        information, rates and fees, how-to and support, branches and contact details, and \
        anything that is not about this person's own transactions.
        - "Check credit score"
        - "How do I dispute a charge?"
        - "What is the interest rate on a TFSA?"
        - "reset my password"

        When a question could be read either way, ask whether answering it requires looking \
        through this person's own transactions. If it does, it is TRANSACTION SEARCH. \
        Otherwise it is COVEO SEARCH.

        A merchant name, an amount, or a date is a strong sign of TRANSACTION SEARCH. Asking \
        what something is, how something works, or how to do something is a strong sign of \
        COVEO SEARCH, even when it mentions money.
        """
}
