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
///
/// Dates aren't here at all: `DateAgent` works them out in sessions of its
/// own, with calendar tools, so this schema never offers a date field for the
/// model to fill when the question names no time.
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

}

/// The same filters with the merchant asked first — the second reading of
/// the merchant-and-amount pair.
///
/// Asked after `spendingKind`, the merchant goes missing whenever the
/// business comes with what was bought: "my most expensive Uber ride" puts
/// "Uber ride" in `spendingKind` and leaves `merchantName` null. Asked first,
/// it finds "Uber" there — and also writes a kind of store as a merchant,
/// which is why `spendingKind` goes first in the other reading. Where the
/// two agree, that's the merchant; where they don't, the parse declines.
@Generable(
    description: "Search filters extracted from a question about the user's own card transactions.",
    representNilExplicitlyInGeneratedContent: true
)
struct GeneratedQueryMerchantFirst: Equatable, Sendable {
    @Guide(description: #"The specific business named in the question, spelled normally: "Starbucks", "Canadian Tire". Null if no business is named — a kind of spending is not a business."#)
    var merchantName: String?

    @Guide(description: #"The kind of spending the question names, copied as written: "grocery", "flights and hotels". Null when it names none."#)
    var spendingKind: String?

    @Guide(description: #"The city, province, or country the question names, copied as written: "Halifax", "Ontario". Null when it names none."#)
    var place: String?
}

extension TransactionQuery {
    /// Keeps the filters, drops the relief valves, and takes the merchant the
    /// pair of readings settled on and the dates the date agent did.
    init(_ query: GeneratedQuery, merchant: String?, dates: CalendarRange?) {
        self.init(
            merchantName: merchant,
            fromAmount: query.fromAmount,
            toAmount: query.toAmount,
            fromDate: dates?.fromDate,
            toDate: dates?.toDate
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
