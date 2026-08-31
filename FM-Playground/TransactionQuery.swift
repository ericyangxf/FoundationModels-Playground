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
    @Guide(description: #"The merchant named in the question, spelled normally: "Starbucks", "Canadian Tire". Null if no merchant is named."#)
    var merchantName: String?

    @Guide(description: "Lower bound on the transaction amount, in dollars. Null unless the question sets a minimum.", .minimum(0))
    var fromAmount: Double?

    @Guide(description: "Upper bound on the transaction amount, in dollars. Null unless the question sets a maximum.", .minimum(0))
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
@Generable(
    description: "Merchant and amount filters extracted from a question about the user's own card transactions.",
    representNilExplicitlyInGeneratedContent: true
)
struct MerchantAmountQuery: Equatable, Sendable {
    @Guide(description: #"The merchant named in the question, spelled normally: "Starbucks", "Canadian Tire". Null if no merchant is named."#)
    var merchantName: String?

    @Guide(description: "Lower bound on the transaction amount, in dollars. Null unless the question sets a minimum.", .minimum(0))
    var fromAmount: Double?

    @Guide(description: "Upper bound on the transaction amount, in dollars. Null unless the question sets a maximum.", .minimum(0))
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
