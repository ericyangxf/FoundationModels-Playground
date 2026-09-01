import FoundationModels

/// The filter set we ask the on-device model to pull out of a natural-language
/// spending question.
///
/// Every field is optional because any one query only mentions a few of them.
/// `representNilExplicitlyInGeneratedContent` makes the model emit an explicit
/// null for the rest instead of quietly dropping the key, which is what keeps
/// "the query said nothing about this" distinguishable from a malformed answer.
@Generable(
    description: "Search filters extracted from a question about the user's own card transactions.",
    representNilExplicitlyInGeneratedContent: true
)
struct TransactionQuery: Equatable, Sendable {
    @Guide(description: #"The specific business named in the question, spelled normally: "Starbucks", "Canadian Tire". Null if no business is named — a word for a kind of spending is not a business."#)
    var merchantName: String?

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
    /// True when the model found nothing to filter on — usually a sign the
    /// question wasn't about transactions at all.
    var isEmpty: Bool {
        merchantName == nil && fromAmount == nil && toAmount == nil
            && fromDate == nil && toDate == nil
    }
}

/// The half of the filter set the model still owns once SwiftyChronoX is
/// handling dates.
///
/// Dropping the two date fields takes the resolved-range block out of the
/// instructions along with them, which is where most of the prompt went.
///
/// `spendingKind` and `amountPhrase` are relief valves, each generated before
/// the fields it protects: the model wants to record "grocery" or "under $25"
/// somewhere, and without a slot of their own they land in `merchantName` or
/// the wrong bound. The parse throws both away — categories come from their
/// own session, and the bounds carry the numbers.
@Generable(
    description: "Merchant and amount filters extracted from a question about the user's own card transactions.",
    representNilExplicitlyInGeneratedContent: true
)
struct MerchantAmountQuery: Equatable, Sendable {
    @Guide(description: #"The kind of spending the question names, copied as written: "grocery", "flights and hotels". Null when it names none."#)
    var spendingKind: String?

    @Guide(description: #"The specific business named in the question, spelled normally: "Starbucks", "Canadian Tire". Null if no business is named — a kind of spending is not a business."#)
    var merchantName: String?

    @Guide(description: #"The question's amount words copied exactly: "under $N", "around $N". Null when it mentions no amount."#)
    var amountPhrase: String?

    @Guide(description: #"Minimum in dollars: "above $N", "over $N", "more than $N", or the low end of "between". Null for "under", "less than", "around", or no comparison."#, .minimum(0))
    var fromAmount: Double?

    @Guide(description: #"Maximum in dollars: "under $N", "less than $N", or the high end of "between". Null for "above", "over", "more than", "around", or no comparison."#, .minimum(0))
    var toAmount: Double?
}

extension TransactionQuery {
    /// Stitches the model's half back together with the range SwiftyChronoX read.
    init(_ query: MerchantAmountQuery, dates: ChronoDateResolver.Resolution) {
        self.init(
            merchantName: query.merchantName,
            fromAmount: query.fromAmount,
            toAmount: query.toAmount,
            fromDate: dates.fromDate,
            toDate: dates.toDate
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
