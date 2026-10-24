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
///
/// What comes back is shaped by what was asked. Ask for groups and the
/// single-transaction extremes are left out: with both in front of it the
/// model answered "which merchant" with the largest transaction's merchant
/// and amount. A grouping along a line the filters already fixed — by
/// merchant when they name one — would be a single row equal to the totals,
/// so it's answered as no grouping. With a merchant named, the question is
/// about that merchant and a merchant grouping is a stray; so is a month
/// grouping when the dates fall inside one month, and any such grouping
/// asked for beside a list order, which says the question is about single
/// transactions ("biggest grocery bill"). Otherwise — one category
/// picked and a category grouping alone — it usually means "where within
/// it", so the answer carries a note naming the groupings that would tell the
/// matches apart, and the session calls once more. (A figure-less problem in place of the
/// figures derailed counts the model had asked for with a stray `groupBy`;
/// a note after every stray merchant grouping cost dates and amounts the
/// second answer then left out.)
nonisolated struct LookUpTransactionsTool: Tool {
    let name = "lookUpTransactions"
    let description = """
        Reads the transactions that match the question's filters. Always returns how many \
        there are, the total, the average, the largest and smallest, and the earliest and most \
        recent. Can also return them in a chosen order, or totals by group.
        """

    let transactions: [Transaction]
    let filters: String
    /// The groupings the filters leave a single group in: `.merchant` when
    /// they name a merchant, `.category` when they pick one category,
    /// `.month` when the dates fall inside one month.
    var fixedGroupings: Set<Grouping> = []

    @Generable(description: "Extras to include with the matching transactions' figures.")
    struct Arguments {
        @Guide(description: "Set only when the question asks which merchant, category, city, province, or month comes out on top — or where the most went — or how much was spent in a named city or province. Null otherwise.")
        var groupBy: Grouping?

        @Guide(description: "Set only when the question asks to see or list transactions, or for its last, first, biggest, or smallest few. Null otherwise.")
        var listOrder: ListOrder?
    }

    @Generable(description: "A way to group transactions.")
    enum Grouping: CaseIterable {
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
        let grouping = arguments.groupBy.flatMap { fixedGroupings.contains($0) ? nil : $0 }
        var note: String?
        if let asked = arguments.groupBy, grouping == nil, asked == .category, arguments.listOrder == nil {
            let others = Grouping.allCases.filter { !fixedGroupings.contains($0) }.map { "\($0)" }
            note = "The filters already pick one \(asked), so grouping by \(asked) is one row — these "
                + "figures are for all of it. To see where within it, group by \(others.joined(separator: ", "))."
        }
        let summary = SpendingSummary(transactions)
        let grouped = grouping != nil

        var listed: [Transaction] = []
        if let order = arguments.listOrder {
            listed = Array(order.sorted(transactions).prefix(Self.maximumListCount))
        } else if transactions.count <= Self.automaticListLimit {
            listed = ListOrder.latest.sorted(transactions)
        }

        var groups: [GroupTotal] = []
        if let grouping = grouping?.grouping {
            groups = TransactionStore.breakdown(transactions, by: grouping)
                .prefix(Self.maximumGroups)
                .map { GroupTotal(name: $0.name, totalSpent: Money.dollars($0.totalCents), transactionCount: $0.count) }
        }

        return TransactionLookup(
            note: note,
            filtersApplied: filters,
            matchingTransactionCount: summary.count,
            totalSpent: Money.dollars(summary.totalCents),
            averagePerTransaction: Money.dollars(summary.averageCents),
            groupTotals: groups,
            largestTransaction: grouped ? nil : summary.largest.map(TransactionRecord.init),
            smallestTransaction: grouped ? nil : summary.smallest.map(TransactionRecord.init),
            earliestTransaction: grouped ? nil : summary.earliest.map(TransactionRecord.init),
            mostRecentTransaction: grouped ? nil : summary.latest.map(TransactionRecord.init),
            listedTransactions: listed.map(TransactionRecord.init)
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
    /// Something about the call worth knowing before answering from it.
    var note: String? = nil
    var filtersApplied: String = ""
    var matchingTransactionCount: Int = 0
    var totalSpent: Double = 0
    var averagePerTransaction: Double = 0
    /// Highest total first; empty unless a grouping was asked for. Ahead of
    /// the single transactions, which are left out when it isn't empty.
    var groupTotals: [GroupTotal] = []
    var largestTransaction: TransactionRecord? = nil
    var smallestTransaction: TransactionRecord? = nil
    var earliestTransaction: TransactionRecord? = nil
    var mostRecentTransaction: TransactionRecord? = nil
    /// In the order asked for; every match when there are only a few.
    var listedTransactions: [TransactionRecord] = []
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
