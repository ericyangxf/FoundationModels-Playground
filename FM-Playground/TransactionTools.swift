import Foundation
import FoundationModels

/// The tool the answer session reads the statement through: it filters the
/// statement and works out the figures.
///
/// The model picks the filters — merchant, categories, amounts and the date
/// range it worked out from today — and the tool applies them and does the
/// arithmetic. It hands back data, not prose: counts, totals and transaction
/// records in a `TransactionLookup`, which the model turns into the answer.
/// No tool here does date arithmetic; dates arrive already worked out, as
/// `yyyy-MM-dd` days.
///
/// One tool rather than one per kind of answer, so every question costs one
/// call: the figures a single-number question needs come back every time,
/// and the two extras — group totals and a list in a chosen order — are
/// optional arguments left null unless the question asks for them.
nonisolated struct SearchTransactionsTool: Tool {
    static let toolName = "searchTransactions"
    var name: String { Self.toolName }
    let description = """
        Filters the person's card statement and works out figures for the transactions that \
        match. Always returns how many matched, their total and average, the largest and \
        smallest, and the earliest and most recent. Can also list them in a chosen order, or \
        total them by group.
        """

    let store: TransactionStore

    @Generable(description: "Which transactions to read, and what to work out about them.")
    struct Arguments: Equatable {
        @Guide(description: "The specific business the question names, spelled as written. Null for any business.")
        var merchant: String?

        /// Optional because "none" is a null to the model as often as it is
        /// an empty list, and both mean the same.
        @Guide(description: "The kinds of spending the question names. Empty or null for any kind.", .maximumCount(3))
        var categories: [SpendingCategory]?

        @Guide(description: "Lowest amount to include, in dollars. Null for no lower limit.")
        var minimumAmount: Double?

        @Guide(description: "Highest amount to include, in dollars. Null for no upper limit.")
        var maximumAmount: Double?

        @Guide(description: "First day to include, yyyy-MM-dd. Null when the question sets no start.")
        var fromDate: String?

        @Guide(description: "Last day to include, yyyy-MM-dd. Null when the question sets no end.")
        var toDate: String?

        @Guide(description: "Totals by group, highest first. Set only when the question asks which merchant, category, city, province or month comes out on top, or how much was spent in a named city or province. Null otherwise.")
        var groupBy: Grouping?

        @Guide(description: "Set only when the question asks to see or list transactions, or for its latest, earliest, biggest or smallest few. Null otherwise.")
        var listOrder: ListOrder?
    }

    @Generable(description: "A way to group transactions.")
    enum Grouping {
        case merchant, category, city, province, month
    }

    /// Named for the words questions use: "my last 3 rides" is `latest`.
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
        let scope = TransactionScope(arguments)
        let transactions = store.matching(scope)
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
            filtersApplied: scope.summary,
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

extension SearchTransactionsTool.Arguments {
    /// The arguments that apply `scope`, for code that already holds one.
    nonisolated init(
        _ scope: TransactionScope,
        groupBy: SearchTransactionsTool.Grouping? = nil,
        listOrder: SearchTransactionsTool.ListOrder? = nil
    ) {
        self.init(
            merchant: scope.merchant,
            categories: scope.categories,
            minimumAmount: scope.minimumCents.map(Money.dollars),
            maximumAmount: scope.maximumCents.map(Money.dollars),
            fromDate: scope.fromDate,
            toDate: scope.toDate,
            groupBy: groupBy,
            listOrder: listOrder
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

extension SearchTransactionsTool.Grouping {
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

extension SearchTransactionsTool.ListOrder {
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
