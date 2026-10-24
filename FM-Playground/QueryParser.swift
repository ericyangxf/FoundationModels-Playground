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
        case parsed(ParsedQuery, ModelRun)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    /// The parse in flight as far as it has got — the model's thinking, then
    /// the filters as they are written — for the page to show while it works.
    private(set) var liveEntries: [Transcript.Entry] = []

    /// The parse currently in flight, kept so clearing the search bar can drop it.
    private var activeParse: Task<Void, Never>?

    /// Loads the model ahead of the first question.
    func prewarm() {
        OnDeviceModel.shared.prewarm()
    }

    func parse(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            reset()
            return
        }

        activeParse?.cancel()
        liveEntries = []
        phase = .parsing
        activeParse = Task { await run(question) }
    }

    /// Drops whatever is in flight and goes back to the example list — what an
    /// emptied or dismissed search bar should leave behind.
    func reset() {
        activeParse?.cancel()
        activeParse = nil
        liveEntries = []
        phase = .idle
    }

    private func run(_ question: String) async {
        do {
            let (parsed, run) = try await parsedQuery(for: question, reference: DateReference()) { entries in
                guard !Task.isCancelled else { return }
                self.liveEntries = entries
            }
            guard !Task.isCancelled else { return }
            phase = .parsed(parsed, run)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Runs one question end to end and hands back the filters along with
    /// what they cost, without touching `phase`.
    ///
    /// The view goes in through `parse(_:)`, which owns the phase and the
    /// cancellation; the accuracy tests call this directly, so what they
    /// measure is the same path the app takes.
    ///
    /// Each question gets a session of its own, so one parse can't colour the
    /// next through a shared transcript.
    func parsedQuery(
        for question: String,
        reference: DateReference,
        onUpdate: ([Transcript.Entry]) -> Void = { _ in }
    ) async throws -> (ParsedQuery, ModelRun) {
        let session = LanguageModelSession(
            model: OnDeviceModel.languageModel,
            instructions: Instructions(Self.instructions(for: reference))
        )

        let clock = ContinuousClock()
        let start = clock.now
        let stream = session.streamResponse(
            to: question,
            generating: GeneratedQuery.self,
            // Greedy decoding keeps repeated runs of the same question
            // comparable, which is the whole point of a playground.
            options: GenerationOptions(samplingMode: .greedy)
        )
        for try await snapshot in stream {
            onUpdate(Array(snapshot.transcriptEntries))
        }
        let response = try await stream.collect()
        let latency = clock.now - start

        return (
            ParsedQuery(response.content),
            ModelRun(latency: latency, usage: response.usage, entries: response.transcriptEntries)
        )
    }

    private static func instructions(for reference: DateReference) -> String {
        """
        You turn a person's question about their own card transactions into search filters.

        \(FilterRules.text)

        \(reference.promptRules)
        """
    }
}
