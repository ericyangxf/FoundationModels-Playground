import FoundationModels
import SwiftUI

struct ContentView: View {
    @State private var parser = QueryParser()
    @State private var text = ""

    private static let examples = [
        "Show my Starbucks spending in the past 40 days",
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
        // The picker sits inside the bottom safe area, which puts it under the
        // results and above whatever room the search bar has taken.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EngineTabBar(selection: parser.engine) { engine in
                parser.select(engine, rerunning: text)
            }
        }
    }

    private func search(_ query: String) {
        text = query
        parser.parse(query)
    }
}

// MARK: - Engine picker

/// The engine picker that sits between the results and the search bar.
///
/// Not a `TabView`: the system tab bar owns the very bottom of the screen, and
/// this belongs above the search field rather than below it.
private struct EngineTabBar: View {
    let selection: QueryEngine
    let onSelect: (QueryEngine) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(QueryEngine.allCases) { engine in
                tab(engine)
            }
        }
        .animation(.snappy(duration: 0.2), value: selection)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func tab(_ engine: QueryEngine) -> some View {
        let isSelected = engine == selection
        return Button {
            onSelect(engine)
        } label: {
            Text(engine.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? Color.white : Color.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? Color.blue : Color.white, in: .capsule)
                .overlay {
                    // The border is what tells the two states apart at a glance
                    // once the fill goes white.
                    Capsule().strokeBorder(Color.blue, lineWidth: isSelected ? 0 : 1.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
                Text("Nothing to filter on — no merchant, amount, or date was found.")
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

/// What the round trip cost. Token counts are reported by the model itself, so
/// they cover the model's share of the work and nothing else — on the
/// SwiftyChronoX run the shorter prompt is the point.
private struct MetricsCard: View {
    let metrics: QueryParser.Metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(metrics.engine.runDescription)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                stat("Latency", metrics.latencyDescription)
                stat("Input", "\(metrics.inputTokens) tok")
                stat("Cached", "\(metrics.cachedInputTokens) tok")
                stat("Output", "\(metrics.outputTokens) tok")
            }

            if let dateLatency = metrics.dateLatencyDescription {
                Text(dateNote(dateLatency))
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

    /// Says which half of the answer came from where, and what the library
    /// keyed off — the phrase it matched is usually the thing worth arguing with.
    private func dateNote(_ latency: String) -> String {
        guard let phrase = metrics.datePhrase else {
            return "SwiftyChronoX found no date in \(latency). Merchant and amount come from the model."
        }
        return "Dates from SwiftyChronoX in \(latency), matching \u{201C}\(phrase)\u{201D}. "
            + "Merchant and amount come from the model."
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
