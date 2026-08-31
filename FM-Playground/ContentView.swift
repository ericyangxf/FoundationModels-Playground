import FoundationModels
import SwiftUI

struct ContentView: View {
    @State private var parser = QueryParser()
    @State private var text = ""

    private static let examples = [
        "List my Starbucks transactions that above $10 from the beginning of this year",
        "How much I spent at Canadian Tire this month?",
        "Show Uber rides under $25 last week",
        "Amazon purchases between $50 and $200 last year"
    ]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Transaction Search")
                .searchable(
                    text: $text,
                    placement: .automatic,
                    prompt: "Ask about your spending"
                )
                .onSubmit(of: .search) { search(text) }
                .onChange(of: text) { _, query in
                    // Covers both the clear "x" and the cancel button, which
                    // empty the field on their way out.
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        parser.reset()
                    }
                }
        }
        .task { parser.prewarm() }
    }

    @ViewBuilder
    private var content: some View {
        switch parser.availability {
        case .available:
            results
        case .unavailable(let reason):
            UnavailableView(reason: reason)
        }
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch parser.phase {
                case .idle:
                    ExampleList(examples: Self.examples, onPick: search)
                case .parsing:
                    ProgressView("Parsing…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                case .parsed(let query, let metrics):
                    ResultCard(query: query)
                    MetricsCard(metrics: metrics)
                case .failed(let message):
                    MessageCard(
                        icon: "exclamationmark.triangle",
                        tint: .orange,
                        title: "Couldn't parse that",
                        message: message
                    )
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func search(_ query: String) {
        text = query
        parser.parse(query)
    }
}

// MARK: - Result

/// The parsed filters, laid out one field per line.
private struct ResultCard: View {
    let query: TransactionQuery

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Merchant Name", value(query.merchantName))
            field("Amount", range(
                Self.dollars(query.fromAmount),
                Self.dollars(query.toAmount)
            ))
            field("Date", range(query.fromDate, query.toDate))

            if query.isEmpty {
                Text("Nothing to filter on — the model found no merchant, amount, or date.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: .rect(cornerRadius: 16))
    }

    /// Whole dollars print without cents, so a parsed 10 reads back as "$10"
    /// rather than "$10.00".
    private static func dollars(_ amount: Double?) -> String? {
        guard let amount else { return nil }
        return amount == amount.rounded()
            ? String(format: "$%.0f", amount)
            : String(format: "$%.2f", amount)
    }

    private func field(_ label: String, _ content: some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label + ":")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content.font(.body.monospaced())
        }
    }

    /// Missing values print as a literal `nil` so a blank field is never
    /// mistaken for an empty string.
    private func value(_ string: String?) -> Text {
        guard let string else {
            return Text("nil").foregroundStyle(.tertiary)
        }
        return Text(string)
    }

    private func range(_ from: String?, _ to: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            value(from)
            Text("to").foregroundStyle(.secondary)
            value(to)
        }
    }
}

// MARK: - Metrics

/// What the round trip cost. Token counts are reported by the model itself.
private struct MetricsCard: View {
    let metrics: QueryParser.Metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On-device run")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                stat("Latency", metrics.latencyDescription)
                stat("Input", "\(metrics.inputTokens) tok")
                stat("Cached", "\(metrics.cachedInputTokens) tok")
                stat("Output", "\(metrics.outputTokens) tok")
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

private struct ExampleList: View {
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

private struct UnavailableView: View {
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

private struct MessageCard: View {
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

#Preview {
    ContentView()
}
