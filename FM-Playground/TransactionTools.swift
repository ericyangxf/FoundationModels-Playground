import Foundation
import FoundationModels

/// The one tool the answer session reads the statement through.
///
/// It is built around the transactions the question's filters already matched
/// — the Query tab's parse decides *which* transactions, and the model only
/// decides *what to see* about them. It hands back data, not prose: counts,
/// totals and transaction records in a `TransactionLookup`, which the model
/// turns into the answer itself. The model never sees the rest of the
/// statement and never does the arithmetic.
///
/// One tool rather than one per kind of answer, because tool choice was where
/// the model went wrong: with separate summary, breakdown and list tools it
/// reached for the breakdown on "average", "largest" and "cheapest" questions
/// and read a group total back as the answer. Here the figures every
/// single-number question needs come back on every call, and the two extras —
/// group totals and a list in a chosen order — are optional arguments that
/// stay null unless the question asks for them, which is the model's habit
/// with optional fields.
nonisolated struct LookUpTransactionsTool: Tool {
    let name = "lookUpTransactions"
    let description = """
        Reads the transactions that match the question's filters. Always returns how many \
        there are, the total, the average, the largest and smallest, and the earliest and most \
        recent. Can also return them in a chosen order, or totals by group.
        """

    let transactions: [Transaction]
    let filters: String

    @Generable(description: "Extras to include with the matching transactions' figures.")
    struct Arguments {
        @Guide(description: "Set only when the question asks which merchant, category, city, province, or month comes out on top, or how much was spent in a named city or province. Null otherwise.")
        var groupBy: Grouping?

        @Guide(description: "Set only when the question asks to see or list transactions, or for its last, first, biggest, or smallest few. Null otherwise.")
        var listOrder: ListOrder?
    }

    @Generable(description: "A way to group transactions.")
    enum Grouping {
        case merchant, category, city, province, month
    }

    /// Named for the words questions use: "my last 3 rides" is `latest`,
    /// where `newest` and `oldest` got "last" read as the end of the list.
    @Generable(description: "Which transactions a list starts with.")
    enum ListOrder {
        case latest, earliest, largest, smallest
    }

    /// Small sets come back in full unasked, so "show me" and "what did I
    /// buy" questions have their rows even when the model leaves the list
    /// argument null.
    static let automaticListLimit = 8
    /// A list asked for in a particular order stops here; "my last 3" takes
    /// the first three.
    static let maximumListCount = 10
    /// Enough groups to answer "which one" and "how much in X" without the
    /// output crowding the context window.
    static let maximumGroups = 10

    func call(arguments: Arguments) async throws -> TransactionLookup {
        let summary = SpendingSummary(transactions)

        var listed: [Transaction] = []
        if let order = arguments.listOrder {
            listed = Array(order.sorted(transactions).prefix(Self.maximumListCount))
        } else if transactions.count <= Self.automaticListLimit {
            listed = ListOrder.latest.sorted(transactions)
        }

        var groups: [GroupTotal] = []
        if let grouping = arguments.groupBy?.grouping {
            groups = TransactionStore.breakdown(transactions, by: grouping)
                .prefix(Self.maximumGroups)
                .map { GroupTotal(name: $0.name, totalSpent: Money.dollars($0.totalCents), transactionCount: $0.count) }
        }

        return TransactionLookup(
            filtersApplied: filters,
            matchingTransactionCount: summary.count,
            totalSpent: Money.dollars(summary.totalCents),
            averagePerTransaction: Money.dollars(summary.averageCents),
            largestTransaction: summary.largest.map(TransactionRecord.init),
            smallestTransaction: summary.smallest.map(TransactionRecord.init),
            earliestTransaction: summary.earliest.map(TransactionRecord.init),
            mostRecentTransaction: summary.latest.map(TransactionRecord.init),
            listedTransactions: listed.map(TransactionRecord.init),
            groupTotals: groups
        )
    }
}

// MARK: - What the tool returns

/// Everything the tool worked out about the matching transactions. Amounts
/// are in dollars and dates are `yyyy-MM-dd`; the model does the wording.
@Generable(
    description: "Figures for the transactions that match the question's filters, worked out by the app.",
    representNilExplicitlyInGeneratedContent: true
)
nonisolated struct TransactionLookup: Equatable, Sendable {
    var filtersApplied: String
    var matchingTransactionCount: Int
    var totalSpent: Double
    var averagePerTransaction: Double
    var largestTransaction: TransactionRecord?
    var smallestTransaction: TransactionRecord?
    var earliestTransaction: TransactionRecord?
    var mostRecentTransaction: TransactionRecord?
    /// In the order asked for; every match when there are only a few.
    var listedTransactions: [TransactionRecord]
    /// Highest total first; empty unless a grouping was asked for.
    var groupTotals: [GroupTotal]
}

/// One transaction, as the model sees it.
@Generable(description: "One card transaction.")
nonisolated struct TransactionRecord: Equatable, Sendable {
    var date: String
    var merchant: String
    var amount: Double
    var city: String
}

extension TransactionRecord {
    nonisolated init(_ transaction: Transaction) {
        self.init(
            date: transaction.date,
            merchant: transaction.merchant,
            amount: Money.dollars(transaction.cents),
            city: transaction.city
        )
    }
}

/// One line of a breakdown.
@Generable(description: "The total for one group of transactions.")
nonisolated struct GroupTotal: Equatable, Sendable {
    var name: String
    var totalSpent: Double
    var transactionCount: Int
}

extension LookUpTransactionsTool.Grouping {
    nonisolated var grouping: SpendingGrouping {
        switch self {
        case .merchant: .merchant
        case .category: .category
        case .city: .city
        case .province: .province
        case .month: .month
        }
    }
}

extension LookUpTransactionsTool.ListOrder {
    /// Ties on amount go to the more recent transaction; ties on date to the
    /// later row.
    nonisolated func sorted(_ transactions: [Transaction]) -> [Transaction] {
        switch self {
        case .latest: transactions.sorted { ($0.date, $0.id) > ($1.date, $1.id) }
        case .earliest: transactions.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        case .largest: transactions.sorted { ($0.cents, $0.date) > ($1.cents, $1.date) }
        case .smallest: transactions.sorted { ($0.cents, $1.date) < ($1.cents, $0.date) }
        }
    }
}
