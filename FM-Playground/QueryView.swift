import FoundationModels
import SwiftUI

struct QueryView: View {
    @State private var parser = QueryParser()
    @State private var text = ""

    /// The questions the idle screen offers, and the same list the accuracy
    /// tests run against — not private so the tests can't drift from it.
    static let examples = [
        "List my Starbucks transactions that above $10 from the beginning of this year",
        "How much I spent at Canadian Tire this month?",
        "Show Uber rides under $25 last week",
        "Amazon purchases between $50 and $200 last year",
        "How much I spent on grocery in this year?",
        "Flights and hotels over $500 last year",
        "Public transit spending in the past 40 days"
    ]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Transaction Search")
                .onChange(of: text) { _, query in
                    // Covers the clear "x", which empties the field on its way out.
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
                case .parsed(let result, let metrics):
                    ResultCard(result: result)
                    MetricsCard(
                        title: "Inquery parsing session run",
                        latency: metrics.latencyDescription,
                        inputTokens: metrics.inputTokens,
                        cachedInputTokens: metrics.cachedInputTokens,
                        outputTokens: metrics.outputTokens,
                        footnote: metrics.footnote
                    )
                    if let categoryRun = metrics.categoryRun {
                        MetricsCard(
                            title: "Category session run",
                            latency: categoryRun.latencyDescription,
                            inputTokens: categoryRun.inputTokens,
                            cachedInputTokens: categoryRun.cachedInputTokens,
                            outputTokens: categoryRun.outputTokens,
                            footnote: "A second session matched the question against "
                                + "the category list, in parallel with the run above."
                        )
                    }
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
        .scrollDismissesKeyboard(.interactively)
        // Picker and field both live in the bottom safe area, stacked under the
        // results and above the tab bar.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                EngineTabBar(selection: parser.engine) { engine in
                    parser.select(engine, rerunning: text)
                }
                QuerySearchField(
                    prompt: "Ask about your spending",
                    text: $text,
                    onSubmit: search
                )
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func search(_ query: String) {
        text = query
        parser.parse(query)
    }
}

// MARK: - Engine picker

/// The engine picker that sits between the results and the search field.
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
    let result: ParsedQuery

    private var query: TransactionQuery { result.filters }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Merchant Name", value(query.merchantName))
            field("Category", categories)
            field("Amount", range(
                Self.dollars(query.fromAmount),
                Self.dollars(query.toAmount)
            ))
            field("Date", range(query.fromDate, query.toDate))

            if result.isEmpty {
                Text("Nothing to filter on — no merchant, category, amount, or date was found.")
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

    /// Each matched category with the code ranges the back-end will get,
    /// one per line, or a literal `nil` when the question named none.
    @ViewBuilder
    private var categories: some View {
        if result.categories.isEmpty {
            Text("nil").foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(result.categories, id: \.self) { category in
                    Text(category.summary)
                }
            }
        }
    }

    private func range(_ from: String?, _ to: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            value(from)
            Text("to").foregroundStyle(.secondary)
            value(to)
        }
    }
}

#Preview {
    QueryView()
}
