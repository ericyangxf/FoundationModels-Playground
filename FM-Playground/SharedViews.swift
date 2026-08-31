import FoundationModels
import SwiftUI

// The pieces both tabs put on screen: what a run cost, what to try, and the
// two ways a page can have nothing to show.

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
                .textInputAutocapitalization(.never)
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

/// What the round trip cost. Token counts are reported by the model itself, so
/// they cover the model's share of the work and nothing else.
struct MetricsCard: View {
    let title: String
    let latency: String
    let inputTokens: Int
    let cachedInputTokens: Int
    let outputTokens: Int
    /// An extra line under the numbers, for a run with a story the four stats
    /// don't tell on their own.
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                stat("Latency", latency)
                stat("Input", "\(inputTokens) tok")
                stat("Cached", "\(cachedInputTokens) tok")
                stat("Output", "\(outputTokens) tok")
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

struct UnavailableView: View {
    let reason: SystemLanguageModel.Availability.UnavailableReason

    var body: some View {
        MessageCard(
            icon: "sparkles.slash",
            tint: .secondary,
            title: "Foundation Models unavailable",
            message: explanation
        )
        .padding()
    }

    private var explanation: String {
        switch reason {
        case .deviceNotEligible:
            "This device doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in Settings to use the on-device model."
        case .modelNotReady:
            "The model is still downloading. Try again in a few minutes."
        @unknown default:
            "The on-device model isn't available right now."
        }
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
