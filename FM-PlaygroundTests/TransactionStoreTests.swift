import Foundation
import FoundationModels
import Testing

@testable import FM_Playground

/// The parts of the Transactions tab that don't need the model: the bundled
/// statement, the filters, the arithmetic the tools do, and the scoring the
/// model tests lean on. All instant, and all runnable on a simulator.
///
/// The expected figures come from the same independent script that worked out
/// the answers in `TransactionAnswerTests`, so a pass here means the tools and
/// that script agree.
@MainActor
struct TransactionStoreTests {
    let store = TransactionStore.bundled

    // MARK: - The statement

    @Test func statementHoldsTwoHundredCanadianTransactionsFromThePastYear() {
        #expect(store.asOf == "2026-10-06")
        #expect(store.transactions.count == 200)
        #expect(Set(store.transactions.map(\.id)).count == 200)
        for transaction in store.transactions {
            #expect(transaction.country == "Canada")
            #expect(transaction.date > "2025-10-06" && transaction.date <= store.asOf, "\(transaction.id) on \(transaction.date)")
            #expect(transaction.cents > 0)
        }
    }

    @Test func everyMerchantCategoryCodeIsInTheMCCList() throws {
        let url = try #require(Bundle.main.url(forResource: "mcc_codes", withExtension: "csv"))
        let codes = Set(try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { Int($0.prefix { $0 != "," }) })
        for transaction in store.transactions {
            #expect(codes.contains(transaction.mcc), "\(transaction.merchant) uses unknown MCC \(transaction.mcc)")
        }
    }

    @Test func categoryComesFromTheCodeRanges() throws {
        let uber = try #require(store.transactions.first { $0.merchant == "Uber" })
        #expect(uber.category == .taxiAndRideshare)
        let netflix = try #require(store.transactions.first { $0.merchant == "Netflix" })
        #expect(netflix.category == .streamingAndDigitalGoods)
        let amazon = try #require(store.transactions.first { $0.merchant == "Amazon" })
        #expect(amazon.category == nil)
    }

    // MARK: - Filters

    @Test(arguments: [
        ("Uber", "uber rides", true),
        ("Tim Hortons", "Tim Horton's", true),
        ("GoodLife Fitness", "GoodLife", true),
        ("Petro-Canada", "PetroCanada", true),
        ("LCBO", "the LCBO", true),
        ("Uber", "Lyft", false),
        ("Marriott", "Montreal", false),
    ])
    func merchantMatching(name: String, query: String, matches: Bool) {
        #expect(TransactionScope.merchant(name, matches: query) == matches)
    }

    @Test func namedMerchantWinsOverCategories() {
        let parsed = ParsedQuery(
            filters: TransactionQuery(merchantName: "Canadian Tire", fromAmount: 0, toAmount: nil, fromDate: nil, toDate: nil),
            categories: [.homeImprovement]
        )
        let scope = TransactionScope(parsed)
        #expect(scope.merchant == "Canadian Tire")
        #expect(scope.categories.isEmpty)
        #expect(scope.minimumCents == nil, "a zero bound means no bound")
    }

    @Test func categoriesApplyWithoutAMerchant() {
        let parsed = ParsedQuery(
            filters: TransactionQuery(merchantName: nil, fromAmount: nil, toAmount: nil, fromDate: nil, toDate: nil),
            categories: [.furniture, .homeImprovement]
        )
        let matches = store.matching(TransactionScope(parsed))
        #expect(Set(matches.map(\.merchant)) == ["IKEA", "Home Depot"])
    }

    // MARK: - Arithmetic

    @Test func uberInThePastSixMonths() {
        let scope = TransactionScope(merchant: "Uber", fromDate: "2026-04-06", toDate: "2026-10-06")
        let summary = SpendingSummary(store.matching(scope))
        #expect(summary.count == 7)
        #expect(summary.totalCents == 13049)
        #expect(summary.latest?.date == "2026-10-03")
    }

    @Test func averageUberRide() {
        let summary = SpendingSummary(store.matching(TransactionScope(merchant: "Uber")))
        #expect(summary.averageCents == 2294)
        #expect(summary.largest?.cents == 4186)
    }

    @Test func largestEverIsTheBanffHotel() {
        let summary = SpendingSummary(store.transactions)
        #expect(summary.largest?.merchant == "Fairmont")
        #expect(summary.largest?.cents == 148620)
    }

    @Test func breakdownByCityPutsTorontoFirst() {
        let groups = TransactionStore.breakdown(store.transactions, by: .city)
        #expect(groups.first == SpendingGroup(name: "Toronto, Ontario", totalCents: 1154126, count: 160))
        #expect(groups.contains(SpendingGroup(name: "Banff, Alberta", totalCents: 169510, count: 4)))
    }

    @Test func breakdownByProvinceAddsUpQuebec() {
        let groups = TransactionStore.breakdown(store.transactions, by: .province)
        #expect(groups.first { $0.name == "Quebec" }?.totalCents == 100495)
    }

    @Test func moneyAndDatesReadTheSameEverywhere() {
        #expect(Money.format(148620) == "$1,486.20")
        #expect(Money.format(645) == "$6.45")
        #expect(Money.day("2026-10-04") == "October 4, 2026")
        #expect(Money.month("2025-12-19") == "December 2025")
    }

    // MARK: - Tool

    private func lookUp(
        _ scope: TransactionScope,
        groupBy: LookUpTransactionsTool.Grouping? = nil,
        listOrder: LookUpTransactionsTool.ListOrder? = nil
    ) async throws -> TransactionLookup {
        let tool = LookUpTransactionsTool(transactions: store.matching(scope), filters: scope.summary)
        return try await tool.call(arguments: .init(groupBy: groupBy, listOrder: listOrder))
    }

    @Test func toolAlwaysReturnsTheFigures() async throws {
        let lookup = try await lookUp(TransactionScope(merchant: "Uber", fromDate: "2026-04-06", toDate: "2026-10-06"))
        #expect(lookup.matchingTransactionCount == 7)
        #expect(lookup.totalSpent == 130.49)
        #expect(lookup.mostRecentTransaction == TransactionRecord(date: "2026-10-03", merchant: "Uber", amount: 18.20, city: "Toronto"))
        #expect(lookup.listedTransactions.count == 7, "a small set comes back in full unasked")
        #expect(lookup.groupTotals.isEmpty)
    }

    @Test func toolLeavesLargeSetsUnlistedUnlessAsked() async throws {
        let lookup = try await lookUp(TransactionScope(merchant: "Uber"))
        #expect(lookup.averagePerTransaction == 22.94)
        #expect(lookup.largestTransaction?.amount == 41.86)
        #expect(lookup.listedTransactions.isEmpty)
    }

    @Test func toolReturnsZeroesWhenNothingMatched() async throws {
        let lookup = try await lookUp(TransactionScope(merchant: "Spotify"))
        #expect(lookup.matchingTransactionCount == 0)
        #expect(lookup.totalSpent == 0)
        #expect(lookup.largestTransaction == nil)
    }

    @Test func toolRanksGroups() async throws {
        let lookup = try await lookUp(TransactionScope(categories: [.gasStations]), groupBy: .merchant)
        #expect(lookup.groupTotals.first == GroupTotal(name: "Petro-Canada", totalSpent: 325.09, transactionCount: 5))
    }

    @Test func toolListsInTheOrderAsked() async throws {
        let lookup = try await lookUp(TransactionScope(merchant: "Uber"), listOrder: .latest)
        #expect(lookup.listedTransactions.count == LookUpTransactionsTool.maximumListCount)
        #expect(lookup.listedTransactions.prefix(3).map(\.amount) == [18.20, 13.85, 19.47])
    }

    @Test func toolOutputReachesTheModelAsData() async throws {
        let lookup = try await lookUp(TransactionScope(merchant: "Lyft"))
        let json = lookup.generatedContent.jsonString
        #expect(json.contains("\"matchingTransactionCount\":3") || json.contains("\"matchingTransactionCount\": 3"), "\(json)")
        #expect(json.contains("Lyft"))
    }
}

/// The scoring `TransactionAnswerTests` applies to the model's text, checked
/// against answers written by hand — so a red model test is the model, not
/// the matcher.
struct AnswerTextTests {
    @Test func amountsMatchByValue() {
        let answer = AnswerText("You spent $1,486.20 at Fairmont, plus 18.2 dollars on Uber.")
        #expect(answer.mentions(amount: 1486.20))
        #expect(answer.mentions(amount: 18.20))
        #expect(!answer.mentions(amount: 1486.00))
    }

    @Test func countsIgnoreMoneyDatesAndYears() {
        let answer = AnswerText("On October 3, 2026 you paid $5.00 — 2 transactions in all.")
        #expect(answer.mentions(count: 2))
        #expect(!answer.mentions(count: 3))
        #expect(!answer.mentions(count: 5))
        #expect(AnswerText("Yes, Netflix charged you twice in August.").mentions(count: 2))
        #expect(AnswerText("You went to Tim Hortons five times.").mentions(count: 5))
    }

    @Test func datesInAnyCommonSpelling() {
        #expect(AnswerText("Your last ride was on October 3, 2026.").mentions(date: "2026-10-03"))
        #expect(AnswerText("Last seen Oct. 3rd.").mentions(date: "2026-10-03"))
        #expect(AnswerText("On 3 October you rode.").mentions(date: "2026-10-03"))
        #expect(AnswerText("Charged 2026-10-03.").mentions(date: "2026-10-03"))
        #expect(!AnswerText("On October 13, 2026.").mentions(date: "2026-10-03"))
        #expect(AnswerText("Sept 1 at Petro-Canada").mentions(date: "2026-09-01"))
    }

    @Test func namesIgnorePunctuationAndAccents() {
        #expect(AnswerText("You filled up at Petro Canada most.").mentions("Petro-Canada"))
        #expect(AnswerText("You spent $997.60 in Montréal.").mentions("Montreal"))
    }

    @Test func nothingMeansNoInventedFigures() {
        let question = "Have I ever spent more than $2,000 in one go?"
        #expect(AnswerText("No, you've never spent more than $2,000 at once.").saysNothing(question: question))
        #expect(AnswerText("I couldn't find any Walmart transactions last week.").saysNothing(question: "How much at Walmart?"))
        #expect(!AnswerText("You spent $45.20 at Walmart.").saysNothing(question: "How much at Walmart?"))
        #expect(!AnswerText("No worries — you spent $45.20.").saysNothing(question: "How much at Walmart?"))
    }
}
