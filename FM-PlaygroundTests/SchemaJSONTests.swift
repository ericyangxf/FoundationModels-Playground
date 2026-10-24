import Foundation
import FoundationModels
import Testing

@testable import FM_Playground

/// The check that decides whether the model's free JSON is kept or rewritten
/// under the constraint — written against the app's real schemas, and against
/// the ways the model's free JSON has actually gone wrong.
struct SchemaJSONTests {
    let schema = try! SchemaJSON(SearchTransactionsTool.Arguments.generationSchema)

    @Test func acceptsEveryKeyWritten() {
        #expect(schema.accepts("""
            {"merchant": "Uber", "categories": [], "minimumAmount": null, "maximumAmount": null, \
            "fromDate": "2026-04-06", "toDate": "2026-10-06", "groupBy": null, "listOrder": null}
            """))
    }

    @Test func acceptsOptionalKeysLeftOut() {
        #expect(schema.accepts(#"{"merchant": "Rogers", "categories": [], "listOrder": "latest"}"#))
    }

    @Test func acceptsNoCategoriesAsNullOrLeftOut() {
        #expect(schema.accepts(#"{"merchant": "Uber", "categories": null}"#))
        #expect(schema.accepts(#"{"merchant": "Rogers", "listOrder": "latest"}"#))
    }

    @Test func rejectsARequiredKeyLeftOut() throws {
        let route = try SchemaJSON(RouteDecision.generationSchema)
        #expect(route.accepts(#"{"route": "transactionSearch", "reason": "It asks about a charge."}"#))
        #expect(!route.accepts(#"{"reason": "It asks about a charge."}"#))
        #expect(!route.accepts(#"{"route": null, "reason": "It asks about a charge."}"#))
    }

    @Test func rejectsACaseThatIsntOnTheList() {
        #expect(!schema.accepts(#"{"categories": [], "groupBy": "week"}"#))
        #expect(!schema.accepts(#"{"categories": ["coffee"]}"#))
    }

    @Test func rejectsTheWrongType() {
        #expect(!schema.accepts(#"{"categories": [], "minimumAmount": "250"}"#))
    }

    @Test func rejectsWhatIsntJSON() {
        #expect(!schema.accepts("call:searchTransactions{categories:[]}"))
    }
}
