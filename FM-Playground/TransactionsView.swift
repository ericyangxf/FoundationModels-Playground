import FoundationModels
import SwiftUI

/// Answers questions about the bundled statement: one tool-calling session
/// picks the filters, searches the statement, and writes the answer.
struct TransactionsView: View {
    @State private var answerer = TransactionAnswerer()
    @State private var text = ""
    private let model = OnDeviceModel.shared

    /// A few of the questions the accuracy tests ask, one per kind of answer.
    static let examples = [
        "How much I spent at Uber in the past 6 months",
        "How many times did I go to Tim Hortons in the past 3 months?",
        "Which city did I spend the most in?",
        "What was my biggest purchase last month?",
        "Did Netflix charge me twice in August?",
        "Show my last 3 Uber rides",
    ]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Transactions")
                .modelStatus(model)
                .onChange(of: text) { _, query in
                    // Covers the clear "x", which empties the field on its way out.
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        answerer.reset()
                    }
                }
        }
        .task { answerer.prewarm() }
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
                switch answerer.phase {
                case .idle:
                    StatementCard(store: answerer.store)
                    ExampleList(examples: Self.examples, onPick: ask)
                case .answering:
                    LiveTraceView(entries: answerer.liveEntries)
                case .answered(let answer):
                    AnswerCard(answer: answer)
                    FiltersCard(answer: answer)
                    ReasoningCard(run: answer.run)
                    ToolCallsCard(calls: answer.toolCalls)
                    MetricsCard(
                        title: "Answer session run",
                        run: answer.run,
                        footnote: "Thinking, one call to searchTransactions, then the answer — "
                            + "all in one session."
                    )
                case .failed(let message):
                    MessageCard(
                        icon: "exclamationmark.triangle",
                        tint: .orange,
                        title: "Couldn't answer that",
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
                prompt: "Ask about your transactions",
                text: $text,
                onSubmit: ask
            )
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func ask(_ query: String) {
        text = query
        answerer.ask(query)
    }
}

// MARK: - Idle

/// What the statement holds, with a way in to every row of it.
private struct StatementCard: View {
    let store: TransactionStore

    var body: some View {
        let summary = SpendingSummary(store.transactions)
        VStack(alignment: .leading, spacing: 10) {
            Text("Statement as of \(Money.day(store.asOf))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                stat("Transactions", "\(summary.count)")
                stat("Total", Money.format(summary.totalCents))
                if let earliest = summary.earliest {
                    stat("Since", Money.day(earliest.date))
                }
            }

            NavigationLink {
                TransactionListView(transactions: store.transactions)
            } label: {
                Label("Browse all transactions", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.medium))
            }

            Text("Questions are answered as of today.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: .rect(cornerRadius: 16))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.callout.monospacedDigit().weight(.medium))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Every transaction on the statement, newest first, a section per month.
struct TransactionListView: View {
    let transactions: [Transaction]

    private var months: [(name: String, rows: [Transaction])] {
        let newestFirst = transactions.sorted { ($0.date, $0.id) > ($1.date, $1.id) }
        var sections: [(name: String, rows: [Transaction])] = []
        for transaction in newestFirst {
            let name = Money.month(transaction.date)
            if sections.last?.name == name {
                sections[sections.count - 1].rows.append(transaction)
            } else {
                sections.append((name, [transaction]))
            }
        }
        return sections
    }

    var body: some View {
        List {
            ForEach(months, id: \.name) { month in
                Section(month.name) {
                    ForEach(month.rows) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                }
            }
        }
        .navigationTitle("All Transactions")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant).font(.body.weight(.medium))
                Text("\(transaction.city), \(transaction.province) · MCC \(String(format: "%04d", transaction.mcc))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(transaction.category?.title ?? "Other")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(transaction.cents)).font(.body.monospacedDigit())
                Text(transaction.date).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Answer

/// The model's answer, as big as the page allows.
private struct AnswerCard: View {
    let answer: TransactionAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Answer", systemImage: "text.bubble")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
            Text(answer.text)
                .font(.title3)
                .textSelection(.enabled)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.12), in: .rect(cornerRadius: 16))
    }
}

/// The filters the model searched with, and how much of the statement they
/// left.
private struct FiltersCard: View {
    let answer: TransactionAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search filters")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(answer.scope?.summary ?? "The model didn't search the statement.")
                .font(.callout.monospaced())
            Text("\(answer.matches.count) of \(TransactionStore.bundled.transactions.count) transactions matched.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: .rect(cornerRadius: 16))
    }
}

/// Each tool the model called, what it asked for, and what came back.
private struct ToolCallsCard: View {
    let calls: [ToolCallRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(calls.isEmpty ? "No tool calls" : "Tool calls")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if calls.isEmpty {
                Text("The model answered without reading the statement.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            ForEach(calls) { call in
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(call.toolName)(\(call.arguments))", systemImage: "wrench.and.screwdriver")
                        .font(.callout.monospaced().weight(.medium))
                    Text(call.output)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
    }
}

#Preview {
    TransactionsView()
}
