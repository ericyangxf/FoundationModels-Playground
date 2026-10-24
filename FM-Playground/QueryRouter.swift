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
        case routed(RouteDecision, ModelRun)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    /// The decision in flight as far as it has got, for the page to show
    /// while the model thinks.
    private(set) var liveEntries: [Transcript.Entry] = []

    /// The run currently in flight, kept so clearing the search bar can drop it.
    private var activeRun: Task<Void, Never>?

    func prewarm() {
        OnDeviceModel.shared.prewarm()
    }

    func route(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            reset()
            return
        }

        activeRun?.cancel()
        liveEntries = []
        phase = .routing
        activeRun = Task { await run(question) }
    }

    /// Drops whatever is in flight and goes back to the example list — what an
    /// emptied or dismissed search bar should leave behind.
    func reset() {
        activeRun?.cancel()
        activeRun = nil
        liveEntries = []
        phase = .idle
    }

    private func run(_ question: String) async {
        // One session per question, so a previous route can't colour the next.
        let session = LanguageModelSession(
            model: OnDeviceModel.languageModel,
            instructions: Instructions(Self.instructions)
        )
        let clock = ContinuousClock()
        let start = clock.now

        do {
            let stream = session.streamResponse(
                to: question,
                generating: RouteDecision.self,
                // Greedy decoding keeps repeated runs of the same question
                // comparable, which is the whole point of a playground.
                options: GenerationOptions(samplingMode: .greedy)
            )
            for try await snapshot in stream {
                guard !Task.isCancelled else { return }
                liveEntries = Array(snapshot.transcriptEntries)
            }
            let response = try await stream.collect()
            guard !Task.isCancelled else { return }
            phase = .routed(
                response.content,
                ModelRun(latency: clock.now - start, usage: response.usage, entries: response.transcriptEntries)
            )
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Definitions rather than examples: the model thinks the question
    /// through before it picks, so it needs to know where the line is, not
    /// what sits on either side of it.
    private static let instructions = """
        You decide which of two search systems should answer a question a person typed into \
        their banking app. Pick exactly one.

        transactionSearch answers questions about the person's own card and account activity: \
        what they bought, where, when and for how much, refunds, recurring charges, or a payment \
        they are looking for. Answering one means reading their transaction history.

        coveoSearch answers everything else: products, rates and fees, policies, how-to and \
        support, branches and contact details — anything that doesn't need this person's own \
        transactions, even when it mentions money.

        The deciding question is whether answering requires looking through this person's own \
        transactions. If it does, it is transactionSearch; otherwise it is coveoSearch.
        """
}
