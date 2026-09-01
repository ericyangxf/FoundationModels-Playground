import Foundation
import FoundationModels
import Testing

@testable import FM_Playground

/// Whether the on-device model will actually answer here.
///
/// A simulator or a machine without Apple Intelligence reports unavailable, and
/// a suite of parses that cannot run should skip rather than fail.
nonisolated func foundationModelIsAvailable() -> Bool {
    SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    ).isAvailable
}

/// Scores Apple's on-device model on the questions the Query tab offers.
///
/// One test per question, named after the question, and each one written out in
/// full — the run, the expected values, the assertions. Nothing is shared
/// between them on purpose: a red test should say what the model was asked and
/// what it should have answered without sending you to a table somewhere else.
///
/// Every question runs through the `.swiftyChronoX` engine, which is the app's
/// default: the date range comes from SwiftyChronoX and the model is left with
/// the merchant, the amounts, and the category. So a failure here is the model
/// getting one of those three wrong, not a small model losing a fight with a
/// calendar.
///
/// Serialized on purpose. There is one on-device model, and seven parses racing
/// each other measure the queue rather than the answer.
@MainActor
@Suite(.serialized, .enabled(if: foundationModelIsAvailable()))
struct FoundationModelAccuracyTests {
    @Test("List my Starbucks transactions that above $10 from the beginning of this year")
    func starbucksAboveTenSinceJanuary() async throws {
        let question = "List my Starbucks transactions that above $10 from the beginning of this year"

        let parser = QueryParser()
        parser.prewarm()
        // One reference date for the run and for the expectation, so a parse
        // straddling midnight can't be scored against the following day.
        let reference = DateReference()
        let (parsed, metrics) = try await parser.parsedQuery(
            for: question,
            using: .swiftyChronoX,
            reference: reference
        )
        let filters = parsed.filters

        print("""
            \u{201C}\(question)\u{201D}
              got: merchant \(filters.merchantName ?? "nil"), \
            amount \(filters.fromAmount?.description ?? "nil")–\(filters.toAmount?.description ?? "nil"), \
            dates \(filters.fromDate ?? "nil")–\(filters.toDate ?? "nil"), \
            categories [\(parsed.categories.map(\.title).joined(separator: ", "))]
              cost: \(metrics.latencyDescription), \
            \(metrics.inputTokens) in (\(metrics.cachedInputTokens) cached), \(metrics.outputTokens) out
            """)

        // Merchant: the business the question names. Case and padding don't count.
        #expect(
            filters.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "starbucks",
            "merchantName: expected Starbucks, got \(filters.merchantName ?? "nil")"
        )

        // Amounts: "above $10" is a floor and nothing else. An upper bound here
        // would be invented, and would silently narrow the search.
        // A 0 and a null both mean no bound, so either passes.
        #expect(
            filters.fromAmount == 10,
            "fromAmount: expected 10, got \(filters.fromAmount?.description ?? "nil")"
        )
        #expect(
            filters.toAmount == nil || filters.toAmount == 0,
            "toAmount: expected no bound, got \(filters.toAmount?.description ?? "nil")"
        )

        // Categories: Starbucks is a business, not a kind of spending, so the
        // category session should come back empty — though reading it as eating
        // out is a near miss rather than a wrong answer.
        let tolerated: Set<SpendingCategory> = [.restaurants]
        #expect(
            parsed.categories.allSatisfy(tolerated.contains),
            "categories: expected none, got \(parsed.categories.map(\.title))"
        )

        // Dates: SwiftyChronoX's job, so they are scored against the same
        // library reading the date phrase on its own. What can still go wrong is
        // the sentence around it — the "$10" read as a date, say.
        let dates = ChronoDateResolver().resolve("from the beginning of this year", reference: reference)
        #expect(
            filters.fromDate == dates.fromDate,
            "fromDate: expected \(dates.fromDate ?? "nil"), got \(filters.fromDate ?? "nil")"
        )
        #expect(
            filters.toDate == dates.toDate,
            "toDate: expected \(dates.toDate ?? "nil"), got \(filters.toDate ?? "nil")"
        )
        #expect(metrics.datePhrase != nil, "no date phrase matched in the question")
    }

    @Test("How much I spent at Canadian Tire this month?")
    func canadianTireThisMonth() async throws {
        let question = "How much I spent at Canadian Tire this month?"

        let parser = QueryParser()
        parser.prewarm()
        let reference = DateReference()
        let (parsed, metrics) = try await parser.parsedQuery(
            for: question,
            using: .swiftyChronoX,
            reference: reference
        )
        let filters = parsed.filters

        print("""
            \u{201C}\(question)\u{201D}
              got: merchant \(filters.merchantName ?? "nil"), \
            amount \(filters.fromAmount?.description ?? "nil")–\(filters.toAmount?.description ?? "nil"), \
            dates \(filters.fromDate ?? "nil")–\(filters.toDate ?? "nil"), \
            categories [\(parsed.categories.map(\.title).joined(separator: ", "))]
              cost: \(metrics.latencyDescription), \
            \(metrics.inputTokens) in (\(metrics.cachedInputTokens) cached), \(metrics.outputTokens) out
            """)

        // Merchant: a two-word name, which is where a model likes to keep only
        // the first word.
        #expect(
            filters.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "canadian tire",
            "merchantName: expected Canadian Tire, got \(filters.merchantName ?? "nil")"
        )

        // Amounts: the question sets no bound at all, either way.
        // A 0 and a null both mean no bound, so either passes.
        #expect(
            filters.fromAmount == nil || filters.fromAmount == 0,
            "fromAmount: expected no bound, got \(filters.fromAmount?.description ?? "nil")"
        )
        #expect(
            filters.toAmount == nil || filters.toAmount == 0,
            "toAmount: expected no bound, got \(filters.toAmount?.description ?? "nil")"
        )

        // Categories: a store name, not a kind of spending. What Canadian Tire
        // sells is a defensible guess, so those three don't count against it.
        let tolerated: Set<SpendingCategory> = [.homeImprovement, .autoPartsAndService, .sportingGoods]
        #expect(
            parsed.categories.allSatisfy(tolerated.contains),
            "categories: expected none, got \(parsed.categories.map(\.title))"
        )

        // Dates: "this month", as SwiftyChronoX reads it.
        let dates = ChronoDateResolver().resolve("this month", reference: reference)
        #expect(
            filters.fromDate == dates.fromDate,
            "fromDate: expected \(dates.fromDate ?? "nil"), got \(filters.fromDate ?? "nil")"
        )
        #expect(
            filters.toDate == dates.toDate,
            "toDate: expected \(dates.toDate ?? "nil"), got \(filters.toDate ?? "nil")"
        )
        #expect(metrics.datePhrase != nil, "no date phrase matched in the question")
    }

    @Test("Show Uber rides under $25 last week")
    func uberUnderTwentyFiveLastWeek() async throws {
        let question = "Show Uber rides under $25 last week"

        let parser = QueryParser()
        parser.prewarm()
        let reference = DateReference()
        let (parsed, metrics) = try await parser.parsedQuery(
            for: question,
            using: .swiftyChronoX,
            reference: reference
        )
        let filters = parsed.filters

        print("""
            \u{201C}\(question)\u{201D}
              got: merchant \(filters.merchantName ?? "nil"), \
            amount \(filters.fromAmount?.description ?? "nil")–\(filters.toAmount?.description ?? "nil"), \
            dates \(filters.fromDate ?? "nil")–\(filters.toDate ?? "nil"), \
            categories [\(parsed.categories.map(\.title).joined(separator: ", "))]
              cost: \(metrics.latencyDescription), \
            \(metrics.inputTokens) in (\(metrics.cachedInputTokens) cached), \(metrics.outputTokens) out
            """)

        // Merchant: "Uber", not "Uber rides" — the noun after it describes what
        // was bought, not who was paid.
        #expect(
            filters.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "uber",
            "merchantName: expected Uber, got \(filters.merchantName ?? "nil")"
        )

        // Amounts: "under $25" is a ceiling and nothing else.
        // A 0 and a null both mean no bound, so either passes.
        #expect(
            filters.fromAmount == nil || filters.fromAmount == 0,
            "fromAmount: expected no bound, got \(filters.fromAmount?.description ?? "nil")"
        )
        #expect(
            filters.toAmount == 25,
            "toAmount: expected 25, got \(filters.toAmount?.description ?? "nil")"
        )

        // Categories: "rides" is arguably a kind of spending, so either answer
        // stands here.
        let tolerated: Set<SpendingCategory> = [.taxiAndRideshare]
        #expect(
            parsed.categories.allSatisfy(tolerated.contains),
            "categories: expected none or Taxi & Rideshare, got \(parsed.categories.map(\.title))"
        )

        // Dates: "last week", as SwiftyChronoX reads it.
        let dates = ChronoDateResolver().resolve("last week", reference: reference)
        #expect(
            filters.fromDate == dates.fromDate,
            "fromDate: expected \(dates.fromDate ?? "nil"), got \(filters.fromDate ?? "nil")"
        )
        #expect(
            filters.toDate == dates.toDate,
            "toDate: expected \(dates.toDate ?? "nil"), got \(filters.toDate ?? "nil")"
        )
        #expect(metrics.datePhrase != nil, "no date phrase matched in the question")
    }

    @Test("Amazon purchases between $50 and $200 last year")
    func amazonBetweenFiftyAndTwoHundredLastYear() async throws {
        let question = "Amazon purchases between $50 and $200 last year"

        let parser = QueryParser()
        parser.prewarm()
        let reference = DateReference()
        let (parsed, metrics) = try await parser.parsedQuery(
            for: question,
            using: .swiftyChronoX,
            reference: reference
        )
        let filters = parsed.filters

        print("""
            \u{201C}\(question)\u{201D}
              got: merchant \(filters.merchantName ?? "nil"), \
            amount \(filters.fromAmount?.description ?? "nil")–\(filters.toAmount?.description ?? "nil"), \
            dates \(filters.fromDate ?? "nil")–\(filters.toDate ?? "nil"), \
            categories [\(parsed.categories.map(\.title).joined(separator: ", "))]
              cost: \(metrics.latencyDescription), \
            \(metrics.inputTokens) in (\(metrics.cachedInputTokens) cached), \(metrics.outputTokens) out
            """)

        // Merchant: the one business named.
        #expect(
            filters.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "amazon",
            "merchantName: expected Amazon, got \(filters.merchantName ?? "nil")"
        )

        // Amounts: the only example with both ends set, and the one place the
        // two bounds can come back swapped.
        #expect(
            filters.fromAmount == 50,
            "fromAmount: expected 50, got \(filters.fromAmount?.description ?? "nil")"
        )
        #expect(
            filters.toAmount == 200,
            "toAmount: expected 200, got \(filters.toAmount?.description ?? "nil")"
        )

        // Categories: a business name again. Amazon sells everything, so
        // department stores is a defensible read.
        let tolerated: Set<SpendingCategory> = [.departmentAndDiscountStores]
        #expect(
            parsed.categories.allSatisfy(tolerated.contains),
            "categories: expected none, got \(parsed.categories.map(\.title))"
        )

        // Dates: "last year", as SwiftyChronoX reads it. Two dollar figures sit
        // between the merchant and the date phrase for it to trip over.
        let dates = ChronoDateResolver().resolve("last year", reference: reference)
        #expect(
            filters.fromDate == dates.fromDate,
            "fromDate: expected \(dates.fromDate ?? "nil"), got \(filters.fromDate ?? "nil")"
        )
        #expect(
            filters.toDate == dates.toDate,
            "toDate: expected \(dates.toDate ?? "nil"), got \(filters.toDate ?? "nil")"
        )
        #expect(metrics.datePhrase != nil, "no date phrase matched in the question")
    }

    @Test("How much I spent on grocery in this year?")
    func groceriesThisYear() async throws {
        let question = "How much I spent on grocery in this year?"

        let parser = QueryParser()
        parser.prewarm()
        let reference = DateReference()
        let (parsed, metrics) = try await parser.parsedQuery(
            for: question,
            using: .swiftyChronoX,
            reference: reference
        )
        let filters = parsed.filters

        print("""
            \u{201C}\(question)\u{201D}
              got: merchant \(filters.merchantName ?? "nil"), \
            amount \(filters.fromAmount?.description ?? "nil")–\(filters.toAmount?.description ?? "nil"), \
            dates \(filters.fromDate ?? "nil")–\(filters.toDate ?? "nil"), \
            categories [\(parsed.categories.map(\.title).joined(separator: ", "))]
              cost: \(metrics.latencyDescription), \
            \(metrics.inputTokens) in (\(metrics.cachedInputTokens) cached), \(metrics.outputTokens) out
            """)

        // Merchant: the question names a kind of spending, not a business, so
        // this has to stay null. "grocery" turning up here is the failure this
        // example exists to catch.
        #expect(
            filters.merchantName == nil,
            "merchantName: expected nil, got \(filters.merchantName ?? "nil")"
        )

        // Amounts: none mentioned.
        // A 0 and a null both mean no bound, so either passes.
        #expect(
            filters.fromAmount == nil || filters.fromAmount == 0,
            "fromAmount: expected no bound, got \(filters.fromAmount?.description ?? "nil")"
        )
        #expect(
            filters.toAmount == nil || filters.toAmount == 0,
            "toAmount: expected no bound, got \(filters.toAmount?.description ?? "nil")"
        )

        // Categories: the other half of the same test — what the merchant field
        // gave up has to land here instead.
        #expect(
            parsed.categories == [.groceries],
            "categories: expected [Groceries], got \(parsed.categories.map(\.title))"
        )

        // Dates: "in this year", as SwiftyChronoX reads it.
        let dates = ChronoDateResolver().resolve("in this year", reference: reference)
        #expect(
            filters.fromDate == dates.fromDate,
            "fromDate: expected \(dates.fromDate ?? "nil"), got \(filters.fromDate ?? "nil")"
        )
        #expect(
            filters.toDate == dates.toDate,
            "toDate: expected \(dates.toDate ?? "nil"), got \(filters.toDate ?? "nil")"
        )
        #expect(metrics.datePhrase != nil, "no date phrase matched in the question")
    }

    @Test("Flights and hotels over $500 last year")
    func flightsAndHotelsOverFiveHundredLastYear() async throws {
        let question = "Flights and hotels over $500 last year"

        let parser = QueryParser()
        parser.prewarm()
        let reference = DateReference()
        let (parsed, metrics) = try await parser.parsedQuery(
            for: question,
            using: .swiftyChronoX,
            reference: reference
        )
        let filters = parsed.filters

        print("""
            \u{201C}\(question)\u{201D}
              got: merchant \(filters.merchantName ?? "nil"), \
            amount \(filters.fromAmount?.description ?? "nil")–\(filters.toAmount?.description ?? "nil"), \
            dates \(filters.fromDate ?? "nil")–\(filters.toDate ?? "nil"), \
            categories [\(parsed.categories.map(\.title).joined(separator: ", "))]
              cost: \(metrics.latencyDescription), \
            \(metrics.inputTokens) in (\(metrics.cachedInputTokens) cached), \(metrics.outputTokens) out
            """)

        // Merchant: two kinds of spending and no business at all.
        #expect(
            filters.merchantName == nil,
            "merchantName: expected nil, got \(filters.merchantName ?? "nil")"
        )

        // Amounts: "over $500" is a floor and nothing else.
        // A 0 and a null both mean no bound, so either passes.
        #expect(
            filters.fromAmount == 500,
            "fromAmount: expected 500, got \(filters.fromAmount?.description ?? "nil")"
        )
        #expect(
            filters.toAmount == nil || filters.toAmount == 0,
            "toAmount: expected no bound, got \(filters.toAmount?.description ?? "nil")"
        )

        // Categories: the only example naming two, and they have to come back
        // in the order the question names them. Travel agencies is a defensible
        // third, so it doesn't count against the answer.
        let tolerated: Set<SpendingCategory> = [.travelAgencies]
        #expect(
            parsed.categories.filter { !tolerated.contains($0) } == [.airlines, .hotels],
            "categories: expected [Airlines, Hotels & Lodging], got \(parsed.categories.map(\.title))"
        )

        // Dates: "last year", as SwiftyChronoX reads it.
        let dates = ChronoDateResolver().resolve("last year", reference: reference)
        #expect(
            filters.fromDate == dates.fromDate,
            "fromDate: expected \(dates.fromDate ?? "nil"), got \(filters.fromDate ?? "nil")"
        )
        #expect(
            filters.toDate == dates.toDate,
            "toDate: expected \(dates.toDate ?? "nil"), got \(filters.toDate ?? "nil")"
        )
        #expect(metrics.datePhrase != nil, "no date phrase matched in the question")
    }

    @Test("Public transit spending in the past 40 days")
    func starbucksPastFortyDays() async throws {
        let question = "Public transit spending in the past 40 days"

        let parser = QueryParser()
        parser.prewarm()
        let reference = DateReference()
        let (parsed, metrics) = try await parser.parsedQuery(
            for: question,
            using: .swiftyChronoX,
            reference: reference
        )
        let filters = parsed.filters

        print("""
            \u{201C}\(question)\u{201D}
              got: merchant \(filters.merchantName ?? "nil"), \
            amount \(filters.fromAmount?.description ?? "nil")–\(filters.toAmount?.description ?? "nil"), \
            dates \(filters.fromDate ?? "nil")–\(filters.toDate ?? "nil"), \
            categories [\(parsed.categories.map(\.title).joined(separator: ", "))]
              cost: \(metrics.latencyDescription), \
            \(metrics.inputTokens) in (\(metrics.cachedInputTokens) cached), \(metrics.outputTokens) out
            """)

        // Merchant: the instructions call this one out by name, because "40
        // days" is the kind of thing that ends up in the merchant field.
        #expect(
            filters.merchantName == nil,
            "merchantName: expected nil"
        )

        // Amounts: none mentioned.
        // A 0 and a null both mean no bound, so either passes.
        #expect(
            filters.fromAmount == nil || filters.fromAmount == 0,
            "fromAmount: expected no bound, got \(filters.fromAmount?.description ?? "nil")"
        )
        #expect(
            filters.toAmount == nil || filters.toAmount == 0,
            "toAmount: expected no bound, got \(filters.toAmount?.description ?? "nil")"
        )

        // Categories: a business name, with eating out as the near miss.
        let tolerated: Set<SpendingCategory> = [.publicTransit]
        #expect(
            parsed.categories.allSatisfy(tolerated.contains),
            "categories: expected none, got \(parsed.categories.map(\.title))"
        )

        // Dates: the window the Foundation Models engine can't cover — 40 days
        // is not on the list of ranges its instructions spell out, so it has to
        // round to the nearest one. This is the case that justifies the second
        // engine, and the one SwiftyChronoX has to get exactly right.
        let dates = ChronoDateResolver().resolve("in the past 40 days", reference: reference)
        #expect(
            filters.fromDate == dates.fromDate,
            "fromDate: expected \(dates.fromDate ?? "nil"), got \(filters.fromDate ?? "nil")"
        )
        #expect(
            filters.toDate == dates.toDate,
            "toDate: expected \(dates.toDate ?? "nil"), got \(filters.toDate ?? "nil")"
        )
        #expect(metrics.datePhrase != nil, "no date phrase matched in the question")
    }
}

/// The behaviour the two sessions are supposed to have on top of the examples:
/// a question with nothing in it comes back empty rather than invented.
@MainActor
@Suite(.serialized, .enabled(if: foundationModelIsAvailable()))
struct FoundationModelRestraintTests {
    @Test("Show me everything")
    func showMeEverything() async throws {
        let question = "Show me everything"

        let parser = QueryParser()
        parser.prewarm()
        let (parsed, _) = try await parser.parsedQuery(
            for: question,
            using: .swiftyChronoX,
            reference: DateReference()
        )

        // Nothing to filter on: no merchant, no amount, no date, no category.
        #expect(parsed.filters.merchantName == nil, "merchantName: got \(parsed.filters.merchantName ?? "nil")")
        #expect(
            parsed.filters.fromAmount == nil || parsed.filters.fromAmount == 0,
            "fromAmount: expected no bound, got \(parsed.filters.fromAmount?.description ?? "nil")"
        )
        #expect(
            parsed.filters.toAmount == nil || parsed.filters.toAmount == 0,
            "toAmount: expected no bound, got \(parsed.filters.toAmount?.description ?? "nil")"
        )
        #expect(parsed.filters.fromDate == nil, "fromDate: got \(parsed.filters.fromDate ?? "nil")")
        #expect(parsed.filters.toDate == nil, "toDate: got \(parsed.filters.toDate ?? "nil")")
        #expect(parsed.categories.isEmpty, "categories: got \(parsed.categories.map(\.title))")
    }

    @Test("What did I spend money on?")
    func whatDidISpendMoneyOn() async throws {
        let question = "What did I spend money on?"

        let parser = QueryParser()
        parser.prewarm()
        let (parsed, _) = try await parser.parsedQuery(
            for: question,
            using: .swiftyChronoX,
            reference: DateReference()
        )

        // "spend money" names no kind of spending, and the rest names nothing
        // at all.
        #expect(parsed.filters.merchantName == nil, "merchantName: got \(parsed.filters.merchantName ?? "nil")")
        #expect(
            parsed.filters.fromAmount == nil || parsed.filters.fromAmount == 0,
            "fromAmount: expected no bound, got \(parsed.filters.fromAmount?.description ?? "nil")"
        )
        #expect(
            parsed.filters.toAmount == nil || parsed.filters.toAmount == 0,
            "toAmount: expected no bound, got \(parsed.filters.toAmount?.description ?? "nil")"
        )
        #expect(parsed.filters.fromDate == nil, "fromDate: got \(parsed.filters.fromDate ?? "nil")")
        #expect(parsed.filters.toDate == nil, "toDate: got \(parsed.filters.toDate ?? "nil")")
        #expect(parsed.categories.isEmpty, "categories: got \(parsed.categories.map(\.title))")
    }

    @Test("Starbucks purchases around $20")
    func ignoresBareAmount() async throws {
        let question = "Starbucks purchases around $20"

        let parser = QueryParser()
        parser.prewarm()
        let (parsed, _) = try await parser.parsedQuery(
            for: question,
            using: .swiftyChronoX,
            reference: DateReference()
        )

        // The merchant is still there to be found.
        #expect(
            parsed.filters.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "starbucks",
            "merchantName: expected Starbucks, got \(parsed.filters.merchantName ?? "nil")"
        )

        // But "around $20" is a vague amount with no comparison in it, so it
        // sets neither bound. This is where the model likes to fill something in.
        #expect(
            parsed.filters.fromAmount == nil || parsed.filters.fromAmount == 0,
            "fromAmount: expected no bound, got \(parsed.filters.fromAmount?.description ?? "nil")"
        )
        #expect(
            parsed.filters.toAmount == nil || parsed.filters.toAmount == 0,
            "toAmount: expected no bound, got \(parsed.filters.toAmount?.description ?? "nil")"
        )
    }
}
