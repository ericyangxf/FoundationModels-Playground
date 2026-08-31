import FoundationModels

/// The two search systems a question can be handed to.
///
/// The case names are what the model actually sees in the schema, so they
/// carry their own meaning rather than leaning on the descriptions alone.
@Generable(description: "The search system that should answer a question.")
enum SearchRoute: CaseIterable, Hashable, Sendable {
    /// Anything that has to be answered by reading the person's own card or
    /// account activity.
    case transactionSearch
    /// Everything else — general questions, product and policy information,
    /// how-to and support.
    case coveoSearch
}

extension SearchRoute {
    /// The name this route goes by on screen, and in the rest of the product.
    var title: String {
        switch self {
        case .transactionSearch: "Transaction Search"
        case .coveoSearch: "Coveo Search"
        }
    }

    var symbolName: String {
        switch self {
        case .transactionSearch: "creditcard"
        case .coveoSearch: "globe"
        }
    }

    /// A one-line reminder of what the route covers, for the empty state.
    var blurb: String {
        switch self {
        case .transactionSearch: "The person's own spending — merchants, amounts, dates."
        case .coveoSearch: "Everything else — products, policies, how-to, support."
        }
    }
}

/// A route plus the reason for it.
///
/// The route is generated first so the answer isn't waiting on the sentence
/// that explains it — the reason is here to be read afterwards, not to talk the
/// model into a decision it hasn't made yet.
@Generable(description: "Which search system should answer a question, and why.")
struct RouteDecision: Equatable, Sendable {
    @Guide(description: "The search system that should answer the question.")
    var route: SearchRoute

    @Guide(description: "One short sentence, at most 15 words, naming what in the question decided it.")
    var reason: String
}
