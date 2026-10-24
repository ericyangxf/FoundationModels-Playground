import Foundation
import FoundationModels

/// What one model response cost and what the model thought on the way —
/// the same record for every page, whichever session produced it.
nonisolated struct ModelRun: Equatable, Sendable {
    var latency: Duration
    var inputTokens: Int
    var cachedInputTokens: Int
    /// Everything decoded, thinking included.
    var outputTokens: Int
    /// The thinking share of `outputTokens`, as the executor estimated it.
    var reasoningTokens: Int
    /// Decode speed of the response's last step, in tokens per second, when
    /// the engine measured it.
    var decodeSpeed: Double?
    /// Whether that step ran with speculative decoding. Steps held to a JSON
    /// schema run without it.
    var speculated: Bool
    /// Whether that step's free JSON didn't fit its schema and was rewritten
    /// under the constraint.
    var retriedUnderConstraint: Bool
    /// The model's thinking, one block per step of the response.
    var reasoning: [String]

    init(latency: Duration, usage: LanguageModelSession.Usage, entries: some Collection<Transcript.Entry>) {
        self.latency = latency
        inputTokens = usage.input.totalTokenCount
        cachedInputTokens = usage.input.cachedTokenCount
        outputTokens = usage.output.totalTokenCount
        reasoningTokens = usage.output.reasoningTokenCount
        decodeSpeed = usage.metadata[OnDeviceModel.decodeSpeedKey].flatMap { try? $0.value(Double.self) }
        speculated = usage.metadata[OnDeviceModel.speculativeDecodingKey]
            .flatMap { try? $0.value(Bool.self) } ?? false
        retriedUnderConstraint = usage.metadata[OnDeviceModel.constrainedRetryKey]
            .flatMap { try? $0.value(Bool.self) } ?? false
        reasoning = entries.compactMap(\.reasoningText)
    }

    @MainActor var latencyDescription: String { latency.latencyDescription }
}

extension Transcript.Entry {
    /// What the model thought, for a reasoning entry.
    nonisolated var reasoningText: String? {
        guard case .reasoning(let reasoning) = self else { return nil }
        let text = Transcript.text(of: reasoning.segments).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

extension Transcript {
    /// Text segments as written, structured ones as their JSON.
    nonisolated static func text(of segments: [Segment]) -> String {
        segments.compactMap { segment in
            switch segment {
            case .text(let text): text.content
            case .structure(let structure): structure.content.jsonString
            default: nil
            }
        }.joined(separator: "\n")
    }
}
