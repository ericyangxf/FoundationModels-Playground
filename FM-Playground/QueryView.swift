import FoundationModels
import SwiftUI

struct QueryView: View {
    @State private var parser = QueryParser()
    @State private var text = ""
    private let model = OnDeviceModel.shared

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
                .modelStatus(model)
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
        if model.status == .ready {
            results
        } else {
            ModelDownloadView(model: model)
        }
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch parser.phase {
                case .idle:
                    ExampleList(examples: Self.examples, onPick: search)
                case .parsing:
                    LiveTraceView(entries: parser.liveEntries)
                case .parsed(let result, let run):
                    ResultCard(result: result)
                    ReasoningCard(run: run)
                    MetricsCard(title: "Parsing session run", run: run)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            QuerySearchField(
                prompt: "Ask about your spending",
                text: $text,
                onSubmit: search
            )
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
