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

/// What the on-device model generates for a question.
///
/// `representNilExplicitlyInGeneratedContent` makes the model emit an explicit
/// null for anything the question leaves out instead of quietly dropping the
/// key, which is what keeps "the query said nothing about this"
/// distinguishable from a malformed answer.
///
/// `spendingKind`, `place` and `amountPhrase` are relief valves, each
/// generated before the fields it protects: the model wants to record
/// "grocery", "Montreal" or "under $25" somewhere, and without a slot of their
/// own they land in `merchantName` or the wrong bound. The parse throws all
/// three away — categories come from their own session, and the bounds carry
/// the numbers.
@Generable(
    description: "Search filters extracted from a question about the user's own card transactions.",
    representNilExplicitlyInGeneratedContent: true
)
struct GeneratedQuery: Equatable, Sendable {
    @Guide(description: #"The kind of spending the question names, copied as written: "grocery", "flights and hotels". Null when it names none."#)
    var spendingKind: String?

    @Guide(description: #"The city, province, or country the question names, copied as written: "Halifax", "Ontario". Null when it names none."#)
    var place: String?

    @Guide(description: #"The specific business named in the question, spelled normally: "Starbucks", "Canadian Tire". Null if no business is named — a kind of spending is not a business."#)
    var merchantName: String?

    @Guide(description: #"The question's amount words copied exactly: "under $N", "around $N". Null when it mentions no amount."#)
    var amountPhrase: String?

    @Guide(description: #"Minimum in dollars: "above $N", "over $N", "more than $N", or the low end of "between". Null for "under", "less than", "around", or no comparison."#, .minimum(0))
    var fromAmount: Double?

    @Guide(description: #"Maximum in dollars: "under $N", "less than $N", or the high end of "between". Null for "above", "over", "more than", "around", or no comparison."#, .minimum(0))
    var toAmount: Double?

    @Guide(description: "First day of the date range, formatted yyyy-MM-dd. Null if the question implies no start date.")
    var fromDate: String?

    @Guide(description: "Last day of the date range, formatted yyyy-MM-dd. Null if the question implies no end date.")
    var toDate: String?
}

extension TransactionQuery {
    /// Keeps the filters and drops the relief valves.
    init(_ query: GeneratedQuery) {
        self.init(
            merchantName: query.merchantName,
            fromAmount: query.fromAmount,
            toAmount: query.toAmount,
            fromDate: query.fromDate,
            toDate: query.toDate
        )
    }
}

/// The full answer the Query tab renders: the filters the main parse produced
/// plus whatever the category session matched.
struct ParsedQuery: Equatable, Sendable {
    var filters: TransactionQuery
    var categories: [SpendingCategory]

    /// True when neither session found anything to search on.
    var isEmpty: Bool { filters.isEmpty && categories.isEmpty }
}
