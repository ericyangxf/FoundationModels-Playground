import FoundationModels
import SwiftUI

// The pieces every tab puts on screen: what a run cost, what the model is
// thinking, what to try, and the ways a page can have nothing to show.

// MARK: - Search

/// The search field, pinned to the bottom of the screen above the tab bar.
///
/// `.searchable` puts its field down here on its own — but only until the page
/// is inside a `TabView`, at which point the system hands the bottom to the tab
/// bar and moves search up into the navigation bar. The one way back down is a
/// `Tab(role: .search)`, which is a single per-app slot (two of them crash) and
/// keeps the field hidden until that tab is tapped. Both pages here are driven
/// by what is typed, so the field is placed by hand and always visible.
struct QuerySearchField: View {
    let prompt: String
    @Binding var text: String
    let onSubmit: (String) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .focused($isFocused)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit {
                    // Out of the way, so the answer lands on a visible page.
                    isFocused = false
                    onSubmit(text)
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Metrics

/// What a response cost. Token counts are the engine's own, so they cover the
/// model's share of the work and nothing else.
struct MetricsCard: View {
    let title: String
    let run: ModelRun
    /// An extra line under the numbers, for a run with a story the stats
    /// don't tell on their own.
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                stat("Latency", run.latencyDescription)
                stat("Input", "\(run.inputTokens) tok")
                stat("Output", "\(run.outputTokens) tok")
                stat("Thinking", "≈\(run.reasoningTokens) tok")
            }

            if let speed = run.decodeSpeed {
                Text("Last step decoded at \(speed, format: .number.precision(.fractionLength(1))) tokens per second, \(run.speculated ? "with speculative decoding" : "without speculative decoding").\(run.retriedUnderConstraint ? " Its first JSON didn't fit the schema, so it was rewritten under the llguidance constraint." : "")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.callout.monospacedDigit().weight(.medium))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Thinking

/// The request in flight as far as it has got: the model's thinking as it
/// streams, each tool call and what came back, and the answer as it's
/// written.
struct LiveTraceView: View {
    let entries: [Transcript.Entry]
    private let activity = ModelActivity.shared

    /// The session's own entries, less a reasoning entry for the step that is
    /// still thinking — that one is shown live from `activity` instead.
    private var settled: [Transcript.Entry] {
        guard activity.isThinking, entries.last?.reasoningText != nil else { return entries }
        return Array(entries.dropLast())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if entries.isEmpty && !activity.isThinking {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading the question…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(settled) { entry in
                switch entry {
                case .reasoning:
                    ThoughtView(text: entry.reasoningText ?? "", isThinking: false)
                case .toolCalls(let calls):
                    ForEach(calls) { call in
                        Label("\(call.toolName)(\(call.arguments.jsonString))", systemImage: "wrench.and.screwdriver")
                            .font(.caption.monospaced())
                    }
                case .toolOutput(let output):
                    Label("\(output.toolName) returned its figures", systemImage: "tray.and.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .response(let response):
                    Text(Transcript.text(of: response.segments))
                        .font(.callout)
                default:
                    EmptyView()
                }
            }

            if activity.isThinking {
                ThoughtView(text: activity.thought, isThinking: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: .rect(cornerRadius: 16))
    }
}

/// One block of thinking, live or finished.
private struct ThoughtView: View {
    let text: String
    let isThinking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(isThinking ? "Thinking…" : "Thought", systemImage: "brain")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)
                if isThinking { ProgressView().controlSize(.small) }
            }
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

/// What the model thought on its way to the answer, folded away once the
/// answer is in.
struct ReasoningCard: View {
    let run: ModelRun

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if run.reasoning.isEmpty {
                    Text("No thinking was recorded for this response.")
                }
                ForEach(Array(run.reasoning.enumerated()), id: \.offset) { step, thought in
                    VStack(alignment: .leading, spacing: 4) {
                        if run.reasoning.count > 1 {
                            Text("Step \(step + 1)").font(.caption.weight(.semibold))
                        }
                        Text(thought).textSelection(.enabled)
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        } label: {
            Label("Thinking · ≈\(run.reasoningTokens) tokens", systemImage: "brain")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.purple.opacity(0.08), in: .rect(cornerRadius: 16))
    }
}

// MARK: - Empty and error states

/// The idle state: a shortcut into a question worth asking.
struct ExampleList: View {
    let examples: [String]
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try one of these")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(examples, id: \.self) { example in
                Button {
                    onPick(example)
                } label: {
                    Text(example)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Model status

extension View {
    /// Puts the on-device model's status under the navigation title: a green
    /// light and the model's name when it can run, amber while it downloads,
    /// red when it isn't on the device.
    ///
    /// The lights are emoji because the subtitle renders plain text only — it
    /// drops images and colour.
    func modelStatus(_ model: OnDeviceModel) -> some View {
        navigationSubtitle(model.statusLine)
    }
}

extension OnDeviceModel {
    var statusLine: String {
        switch status {
        case .ready: "🟢 \(displayName)"
        case .downloading(let fraction): "🟡 Downloading \(displayName) · \(Int(fraction * 100))%"
        case .notDownloaded: "🔴 \(displayName) not downloaded"
        case .failed: "🔴 \(displayName) download failed"
        }
    }
}

/// What a page shows until the model file is on the device: a way to fetch
/// it, how far along it is, or why it stopped.
struct ModelDownloadView: View {
    let model: OnDeviceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("\(model.displayName) isn't on this device yet", systemImage: "arrow.down.circle")
                .font(.headline)

            Text("""
                This app runs Google's Gemma 4 E4B on this device with LiteRT-LM, through the \
                Foundation Models API. The model is a one-time \(Self.size) download from Hugging \
                Face; keep the app open until it finishes.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)

            switch model.status {
            case .downloading(let fraction):
                ProgressView(value: fraction) {
                    Text("Downloading… \(fraction, format: .percent.precision(.fractionLength(0)))")
                        .font(.footnote)
                }
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                downloadButton("Try Again")
            case .notDownloaded:
                downloadButton("Download \(Self.size)")
            case .ready:
                EmptyView()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: .rect(cornerRadius: 16))
        .padding()
    }

    private static let size = OnDeviceModel.downloadSize.formatted(.byteCount(style: .file))

    private func downloadButton(_ title: String) -> some View {
        Button(title, systemImage: "arrow.down") {
            model.download()
        }
        .buttonStyle(.borderedProminent)
    }
}

struct MessageCard: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: .rect(cornerRadius: 16))
    }
}
