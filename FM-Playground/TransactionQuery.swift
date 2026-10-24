import FoundationModels

/// The filter set a natural-language spending question is turned into.
///
/// Every field is optional because any one query only mentions a few of them.
struct TransactionQuery: Equatable, Sendable {
    var merchantName: String?
    var fromAmount: Double?
    var toAmount: Double?
    /// First day of the date range, formatted yyyy-MM-dd.
    var fromDate: String?
    /// Last day of the date range, formatted yyyy-MM-dd.
    var toDate: String?
}

extension TransactionQuery {
    /// True when the model found nothing to filter on — usually a sign the
    /// question wasn't about transactions at all.
    var isEmpty: Bool {
        merchantName == nil && fromAmount == nil && toAmount == nil
            && fromDate == nil && toDate == nil
    }
}

/// What the model generates for a question, in one pass.
///
/// Gemma thinks before it writes this, so the scratch fields Apple's model
/// needed — somewhere to put "grocery" or "under $25" so they stayed out of
/// the merchant and the wrong bound — are gone, and the categories come back
/// in the same answer instead of from a second session.
@Generable(
    description: "Search filters for a question about the user's own card transactions.",
    representNilExplicitlyInGeneratedContent: true
)
struct GeneratedQuery: Equatable, Sendable {
    @Guide(description: "The specific business the question names, spelled as written. Null when it names none.")
    var merchantName: String?

    /// Optional because "none" is a null to the model as often as it is an
    /// empty list, and both mean the same.
    @Guide(description: "Every kind of spending the question names, in the order it names them. Empty or null when it names none.", .maximumCount(3))
    var categories: [SpendingCategory]?

    @Guide(description: "Lowest amount in dollars, from an explicit comparison. Null otherwise.", .minimum(0))
    var fromAmount: Double?

    @Guide(description: "Highest amount in dollars, from an explicit comparison. Null otherwise.", .minimum(0))
    var toAmount: Double?

    @Guide(description: "First day of the date range, yyyy-MM-dd. Null when the question names no time.")
    var fromDate: String?

    @Guide(description: "Last day of the date range, yyyy-MM-dd. Null when the question names no time.")
    var toDate: String?
}

/// How a question turns into filters, in the words both the Query tab's parse
/// and the Transactions tab's search tool are prompted with — so a question
/// is read the same way on both.
enum FilterRules {
    static let text = """
        Set only the filters the question asks for, and leave every other one null or empty.
        - Merchant: a specific business the question names — a store, restaurant, brand, airline \
        or service — spelled as written. A kind of spending ("haircuts"), a kind of store \
        ("bakery", "hardware store"), a place, or a time is never a merchant.
        - Categories: the kinds of spending the question names, picked from the list. When the \
        question names a business, leave categories empty; the business already says what it \
        is. General words such as "spending", "purchases", "money" or "everything" name no kind.
        - Amounts: only an explicit comparison sets one. "Over", "above" and "more than" set the \
        lowest amount, "under" and "less than" the highest, and "between" both. A bare or \
        approximate amount, such as "around $N", sets neither.
        """
}

/// The full answer the Query tab renders: the filters and the categories.
struct ParsedQuery: Equatable, Sendable {
    var filters: TransactionQuery
    var categories: [SpendingCategory]

    /// True when the question gave nothing to search on.
    var isEmpty: Bool { filters.isEmpty && categories.isEmpty }
}

extension ParsedQuery {
    init(_ query: GeneratedQuery) {
        // Even greedy decoding can repeat itself inside a list.
        var seen = Set<SpendingCategory>()
        self.init(
            filters: TransactionQuery(
                merchantName: query.merchantName,
                fromAmount: query.fromAmount,
                toAmount: query.toAmount,
                fromDate: query.fromDate,
                toDate: query.toDate
            ),
            categories: (query.categories ?? []).filter { seen.insert($0).inserted }
        )
    }
}
