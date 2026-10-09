import Foundation
import FoundationModels
import Testing

@testable import FM_Playground

/// Scores the Transactions tab end to end on one hundred questions, typed the
/// way a bank client types them — casual, sometimes ungrammatical, sometimes
/// slangy — about the bundled statement.
///
/// Each test runs the same path the tab does: the Query tab's parse turns the
/// question into filters (the date reasoning chain for the dates, the model
/// for the rest), then a tool-calling session answers from the transactions those
/// filters matched. Each one writes out what a correct run looks like:
///
/// - `expecting`: the filters the question really asks for, worked out by hand
///   rather than by any code under test.
/// - `matches`: how many of the 200 transactions those filters leave.
/// - `answer`: the figure the answer has to state, computed from the JSON by
///   an independent script when the data was generated
///   (Scripts/TransactionFixtures/oracle.py — this file is its output).
///
/// `ask` then scores the run in layers, so a red test says whose fault it is:
///
/// 1. The parse has to land on the same transactions. When only the dates
///    differ, the failure names the date chain's reading and its trace; any
///    other difference is the merchant, amount, or category parse.
/// 2. The answer session has to call a tool — an answer written without
///    reading the statement is a guess, however lucky.
/// 3. The answer text has to state the expected figure. Numbers are matched
///    by value, so "$1,486.20" and "1486.2 dollars" both count; dates in any
///    common spelling; counts as digits or words.
///
/// The statement date is fixed at 2026-10-06, so the expected answers hold no
/// matter what day the suite runs.
@MainActor
@Suite(.serialized, .enabled(if: foundationModelIsAvailable()))
struct TransactionAnswerTests {
    // MARK: - How much at a merchant

    @Test("How much I spent at Uber in the past 6 months")
    func uberPastSixMonths() async throws {
        try await ask(
            "How much I spent at Uber in the past 6 months",
            expecting: .init(merchant: "Uber", dates: ("2026-04-06", "2026-10-06")),
            matches: 7,
            answer: .amount(130.49)
        )
    }

    @Test("how much have i spent on uber so far this year")
    func uberSoFarThisYear() async throws {
        try await ask(
            "how much have i spent on uber so far this year",
            expecting: .init(merchant: "Uber", dates: ("2026-01-01", "2026-12-31")),
            matches: 9,
            answer: .amount(191.27)
        )
    }

    @Test("What's my total at Tim Hortons last month?")
    func timHortonsLastMonth() async throws {
        try await ask(
            "What's my total at Tim Hortons last month?",
            expecting: .init(merchant: "Tim Hortons", dates: ("2026-09-01", "2026-09-30")),
            matches: 2,
            answer: .amount(17.05)
        )
    }

    @Test("Starbucks damage for this year?")
    func starbucksDamageThisYear() async throws {
        try await ask(
            "Starbucks damage for this year?",
            expecting: .init(merchant: "Starbucks", dates: ("2026-01-01", "2026-12-31")),
            matches: 4,
            answer: .amount(34.95)
        )
    }

    @Test("How much did I drop at the LCBO since June?")
    func lcboSinceJune() async throws {
        try await ask(
            "How much did I drop at the LCBO since June?",
            expecting: .init(merchant: "LCBO", dates: ("2026-06-01", "2026-10-06")),
            matches: 3,
            answer: .amount(175.35)
        )
    }

    @Test("Total spent at Costco in the last 3 months")
    func costcoLastThreeMonths() async throws {
        try await ask(
            "Total spent at Costco in the last 3 months",
            expecting: .init(merchant: "Costco", dates: ("2026-07-06", "2026-10-06")),
            matches: 2,
            answer: .amount(354.65)
        )
    }

    @Test("How much went to Amazon in 2025?")
    func amazonIn2025() async throws {
        try await ask(
            "How much went to Amazon in 2025?",
            expecting: .init(merchant: "Amazon", dates: ("2025-01-01", "2025-12-31")),
            matches: 1,
            answer: .amount(86.98)
        )
    }

    @Test("How much have I paid Rogers this year?")
    func rogersThisYear() async throws {
        try await ask(
            "How much have I paid Rogers this year?",
            expecting: .init(merchant: "Rogers", dates: ("2026-01-01", "2026-12-31")),
            matches: 10,
            answer: .amount(964.00)
        )
    }

    @Test("What has Netflix cost me over the past year?")
    func netflixPastYear() async throws {
        try await ask(
            "What has Netflix cost me over the past year?",
            expecting: .init(merchant: "Netflix", dates: ("2025-10-06", "2026-10-06")),
            matches: 13,
            answer: .amount(246.87)
        )
    }

    @Test("How much have I spent at Loblaws in the last 90 days?")
    func loblawsLast90Days() async throws {
        try await ask(
            "How much have I spent at Loblaws in the last 90 days?",
            expecting: .init(merchant: "Loblaws", dates: ("2026-07-08", "2026-10-06")),
            matches: 3,
            answer: .amount(238.23)
        )
    }

    @Test("What did I spend at Shoppers Drug Mart in March?")
    func shoppersInMarch() async throws {
        try await ask(
            "What did I spend at Shoppers Drug Mart in March?",
            expecting: .init(merchant: "Shoppers Drug Mart", dates: ("2026-03-01", "2026-03-31")),
            matches: 1,
            answer: .amount(36.48)
        )
    }

    @Test("Canadian Tire spending since the start of the year")
    func canadianTireSinceStartOfYear() async throws {
        try await ask(
            "Canadian Tire spending since the start of the year",
            expecting: .init(merchant: "Canadian Tire", dates: ("2026-01-01", "2026-10-06")),
            matches: 4,
            answer: .amount(368.42)
        )
    }

    @Test("How much did I put into Petro-Canada last month?")
    func petroCanadaLastMonth() async throws {
        try await ask(
            "How much did I put into Petro-Canada last month?",
            expecting: .init(merchant: "Petro-Canada", dates: ("2026-09-01", "2026-09-30")),
            matches: 1,
            answer: .amount(64.44)
        )
    }

    @Test("What have I paid GoodLife so far this year?")
    func goodLifeSoFarThisYear() async throws {
        try await ask(
            "What have I paid GoodLife so far this year?",
            expecting: .init(merchant: "GoodLife Fitness", dates: ("2026-01-01", "2026-12-31")),
            matches: 10,
            answer: .amount(599.90)
        )
    }

    @Test("How much have I blown on DoorDash in the past 2 months?")
    func doorDashPastTwoMonths() async throws {
        try await ask(
            "How much have I blown on DoorDash in the past 2 months?",
            expecting: .init(merchant: "DoorDash", dates: ("2026-08-06", "2026-10-06")),
            matches: 1,
            answer: .amount(31.73)
        )
    }

    @Test("How much have I spent at IKEA?")
    func ikeaAllTime() async throws {
        try await ask(
            "How much have I spent at IKEA?",
            expecting: .init(merchant: "IKEA"),
            matches: 2,
            answer: .amount(631.67)
        )
    }

    @Test("What did my Air Canada flights cost in February?")
    func airCanadaInFebruary() async throws {
        try await ask(
            "What did my Air Canada flights cost in February?",
            expecting: .init(merchant: "Air Canada", dates: ("2026-02-01", "2026-02-28")),
            matches: 2,
            answer: .amount(742.21)
        )
    }

    @Test("How much did I spend at Home Depot between April and June?")
    func homeDepotAprilToJune() async throws {
        try await ask(
            "How much did I spend at Home Depot between April and June?",
            expecting: .init(merchant: "Home Depot", dates: ("2026-04-01", "2026-06-30")),
            matches: 1,
            answer: .amount(241.92)
        )
    }

    // MARK: - How many

    @Test("How many times did I go to Tim Hortons in the past 3 months?")
    func timHortonsVisitsPastThreeMonths() async throws {
        try await ask(
            "How many times did I go to Tim Hortons in the past 3 months?",
            expecting: .init(merchant: "Tim Hortons", dates: ("2026-07-06", "2026-10-06")),
            matches: 5,
            answer: .count(5)
        )
    }

    @Test("How many Uber rides did I take last month?")
    func uberRidesLastMonth() async throws {
        try await ask(
            "How many Uber rides did I take last month?",
            expecting: .init(merchant: "Uber", dates: ("2026-09-01", "2026-09-30")),
            matches: 1,
            answer: .count(1)
        )
    }

    @Test("How many times did I hit up Starbucks this year?")
    func starbucksVisitsThisYear() async throws {
        try await ask(
            "How many times did I hit up Starbucks this year?",
            expecting: .init(merchant: "Starbucks", dates: ("2026-01-01", "2026-12-31")),
            matches: 4,
            answer: .count(4)
        )
    }

    @Test("How many times did I fill up at Petro-Canada since January?")
    func petroCanadaFillUpsSinceJanuary() async throws {
        try await ask(
            "How many times did I fill up at Petro-Canada since January?",
            expecting: .init(merchant: "Petro-Canada", dates: ("2026-01-01", "2026-10-06")),
            matches: 2,
            answer: .count(2)
        )
    }

    @Test("How many Amazon orders did I place in the past 6 months?")
    func amazonOrdersPastSixMonths() async throws {
        try await ask(
            "How many Amazon orders did I place in the past 6 months?",
            expecting: .init(merchant: "Amazon", dates: ("2026-04-06", "2026-10-06")),
            matches: 4,
            answer: .count(4)
        )
    }

    @Test("How many times did I eat out last month?")
    func eatingOutLastMonth() async throws {
        try await ask(
            "How many times did I eat out last month?",
            expecting: .init(categories: [.restaurants], dates: ("2026-09-01", "2026-09-30")),
            matches: 4,
            answer: .count(4)
        )
    }

    @Test("How many grocery runs did I make in September?")
    func groceryRunsInSeptember() async throws {
        try await ask(
            "How many grocery runs did I make in September?",
            expecting: .init(categories: [.groceries], dates: ("2026-09-01", "2026-09-30")),
            matches: 3,
            answer: .count(3)
        )
    }

    @Test("How many purchases did I make yesterday?")
    func purchasesYesterday() async throws {
        try await ask(
            "How many purchases did I make yesterday?",
            expecting: .init(dates: ("2026-10-05", "2026-10-05")),
            matches: 2,
            answer: .count(2)
        )
    }

    @Test("How many charges over $100 did I have last month?")
    func chargesOverHundredLastMonth() async throws {
        try await ask(
            "How many charges over $100 did I have last month?",
            expecting: .init(minimum: 100, dates: ("2026-09-01", "2026-09-30")),
            matches: 2,
            answer: .count(2)
        )
    }

    @Test("How many times has Netflix charged me this year?")
    func netflixChargesThisYear() async throws {
        try await ask(
            "How many times has Netflix charged me this year?",
            expecting: .init(merchant: "Netflix", dates: ("2026-01-01", "2026-12-31")),
            matches: 10,
            answer: .count(10)
        )
    }

    @Test("Did Netflix charge me twice in August?")
    func netflixTwiceInAugust() async throws {
        try await ask(
            "Did Netflix charge me twice in August?",
            expecting: .init(merchant: "Netflix", dates: ("2026-08-01", "2026-08-31")),
            matches: 2,
            answer: .count(2)
        )
    }

    // MARK: - How much on a kind of spending

    @Test("How much did I spend on groceries last month?")
    func groceriesLastMonth() async throws {
        try await ask(
            "How much did I spend on groceries last month?",
            expecting: .init(categories: [.groceries], dates: ("2026-09-01", "2026-09-30")),
            matches: 3,
            answer: .amount(142.45)
        )
    }

    @Test("How much have I spent on gas this year?")
    func gasThisYear() async throws {
        try await ask(
            "How much have I spent on gas this year?",
            expecting: .init(categories: [.gasStations], dates: ("2026-01-01", "2026-12-31")),
            matches: 6,
            answer: .amount(348.67)
        )
    }

    @Test("What did I spend eating out in the past 30 days?")
    func eatingOutPastThirtyDays() async throws {
        try await ask(
            "What did I spend eating out in the past 30 days?",
            expecting: .init(categories: [.restaurants], dates: ("2026-09-06", "2026-10-06")),
            matches: 5,
            answer: .amount(77.80)
        )
    }

    @Test("How much did I spend on rides last month?")
    func ridesLastMonth() async throws {
        try await ask(
            "How much did I spend on rides last month?",
            expecting: .init(categories: [.taxiAndRideshare], dates: ("2026-09-01", "2026-09-30")),
            matches: 1,
            answer: .amount(13.85)
        )
    }

    @Test("How much have I spent on flights this year?")
    func flightsThisYear() async throws {
        try await ask(
            "How much have I spent on flights this year?",
            expecting: .init(categories: [.airlines], dates: ("2026-01-01", "2026-12-31")),
            matches: 3,
            answer: .amount(1071.65)
        )
    }

    @Test("What's my phone bill total for the past 6 months?")
    func phoneBillPastSixMonths() async throws {
        try await ask(
            "What's my phone bill total for the past 6 months?",
            expecting: .init(categories: [.phoneInternetAndCable], dates: ("2026-04-06", "2026-10-06")),
            matches: 6,
            answer: .amount(584.40)
        )
    }

    @Test("How much have I spent on alcohol since June?")
    func alcoholSinceJune() async throws {
        try await ask(
            "How much have I spent on alcohol since June?",
            expecting: .init(categories: [.liquorStores], dates: ("2026-06-01", "2026-10-06")),
            matches: 4,
            answer: .amount(230.10)
        )
    }

    @Test("Pharmacy spending in the last 3 months?")
    func pharmacyLastThreeMonths() async throws {
        try await ask(
            "Pharmacy spending in the last 3 months?",
            expecting: .init(categories: [.pharmacies], dates: ("2026-07-06", "2026-10-06")),
            matches: 1,
            answer: .amount(15.02)
        )
    }

    @Test("How much am I paying for streaming this year?")
    func streamingThisYear() async throws {
        try await ask(
            "How much am I paying for streaming this year?",
            expecting: .init(categories: [.streamingAndDigitalGoods], dates: ("2026-01-01", "2026-12-31")),
            matches: 10,
            answer: .amount(189.90)
        )
    }

    @Test("How much did I spend on public transit this year?")
    func publicTransitThisYear() async throws {
        try await ask(
            "How much did I spend on public transit this year?",
            expecting: .init(categories: [.publicTransit], dates: ("2026-01-01", "2026-12-31")),
            matches: 8,
            answer: .amount(468.61)
        )
    }

    @Test("How much did hotels cost me in the past year?")
    func hotelsPastYear() async throws {
        try await ask(
            "How much did hotels cost me in the past year?",
            expecting: .init(categories: [.hotels], dates: ("2025-10-06", "2026-10-06")),
            matches: 4,
            answer: .amount(3330.44)
        )
    }

    @Test("How much have I spent on parking?")
    func parkingAllTime() async throws {
        try await ask(
            "How much have I spent on parking?",
            expecting: .init(categories: [.parkingAndTolls]),
            matches: 2,
            answer: .amount(40.51)
        )
    }

    @Test("How much did my pet cost me this year?")
    func petThisYear() async throws {
        try await ask(
            "How much did my pet cost me this year?",
            expecting: .init(categories: [.petsAndVets], dates: ("2026-01-01", "2026-12-31")),
            matches: 1,
            answer: .amount(85.18)
        )
    }

    @Test("How much did I spend on electronics?")
    func electronicsAllTime() async throws {
        try await ask(
            "How much did I spend on electronics?",
            expecting: .init(categories: [.electronics]),
            matches: 4,
            answer: .amount(1208.26)
        )
    }

    @Test("How much did I spend on clothes since January?")
    func clothesSinceJanuary() async throws {
        try await ask(
            "How much did I spend on clothes since January?",
            expecting: .init(categories: [.clothing], dates: ("2026-01-01", "2026-10-06")),
            matches: 1,
            answer: .amount(129.16)
        )
    }

    @Test("Furniture and home improvement spending this year")
    func furnitureAndHomeImprovementThisYear() async throws {
        try await ask(
            "Furniture and home improvement spending this year",
            expecting: .init(categories: [.furniture, .homeImprovement], dates: ("2026-01-01", "2026-12-31")),
            matches: 4,
            answer: .amount(1043.04)
        )
    }

    // MARK: - Amount filters

    @Test("Show me every purchase over $500")
    func everyPurchaseOverFiveHundred() async throws {
        try await ask(
            "Show me every purchase over $500",
            expecting: .init(minimum: 500),
            matches: 5,
            answer: .amounts([1486.20, 742.18, 689.40, 684.21, 538.17])
        )
    }

    @Test("Any charges above $300 last month?")
    func chargesAboveThreeHundredLastMonth() async throws {
        try await ask(
            "Any charges above $300 last month?",
            expecting: .init(minimum: 300, dates: ("2026-09-01", "2026-09-30")),
            matches: 1,
            answer: .amounts([429.99])
        )
    }

    @Test("List my Uber rides under $15")
    func uberRidesUnderFifteen() async throws {
        try await ask(
            "List my Uber rides under $15",
            expecting: .init(merchant: "Uber", maximum: 15),
            matches: 4,
            answer: .amounts([13.85, 13.95, 12.70, 12.40])
        )
    }

    @Test("List my Starbucks transactions that above $10 from the beginning of this year")
    func starbucksAboveTenThisYear() async throws {
        try await ask(
            "List my Starbucks transactions that above $10 from the beginning of this year",
            expecting: .init(merchant: "Starbucks", minimum: 10, dates: ("2026-01-01", "2026-10-06")),
            matches: 1,
            answer: .amounts([13.97])
        )
    }

    @Test("How many grocery bills between $100 and $200 did I have in the past 3 months?")
    func groceryBillsHundredToTwoHundred() async throws {
        try await ask(
            "How many grocery bills between $100 and $200 did I have in the past 3 months?",
            expecting: .init(categories: [.groceries], minimum: 100, maximum: 200, dates: ("2026-07-06", "2026-10-06")),
            matches: 1,
            answer: .count(1)
        )
    }

    @Test("What did I buy for more than $250 in the past 6 months?")
    func boughtOverTwoFiftyPastSixMonths() async throws {
        try await ask(
            "What did I buy for more than $250 in the past 6 months?",
            expecting: .init(minimum: 250, dates: ("2026-04-06", "2026-10-06")),
            matches: 7,
            answer: .amounts([689.40, 429.99, 412.66, 409.09, 390.04, 329.44, 255.56])
        )
    }

    @Test("How many purchases under $5 did I make this year?")
    func purchasesUnderFiveThisYear() async throws {
        try await ask(
            "How many purchases under $5 did I make this year?",
            expecting: .init(maximum: 5, dates: ("2026-01-01", "2026-12-31")),
            matches: 1,
            answer: .count(1)
        )
    }

    @Test("Have I ever spent more than $2,000 in one go?")
    func everOverTwoThousand() async throws {
        try await ask(
            "Have I ever spent more than $2,000 in one go?",
            expecting: .init(minimum: 2000),
            matches: 0,
            answer: .nothing
        )
    }

    // MARK: - Biggest and smallest

    @Test("What was my biggest purchase last month?")
    func biggestPurchaseLastMonth() async throws {
        try await ask(
            "What was my biggest purchase last month?",
            expecting: .init(dates: ("2026-09-01", "2026-09-30")),
            matches: 17,
            answer: .transaction("Best Buy", 429.99)
        )
    }

    @Test("What's the most I've ever spent in one transaction?")
    func mostEverInOneTransaction() async throws {
        try await ask(
            "What's the most I've ever spent in one transaction?",
            expecting: .everything,
            matches: 200,
            answer: .transaction("Fairmont", 1486.20)
        )
    }

    @Test("Biggest grocery bill this year?")
    func biggestGroceryBillThisYear() async throws {
        try await ask(
            "Biggest grocery bill this year?",
            expecting: .init(categories: [.groceries], dates: ("2026-01-01", "2026-12-31")),
            matches: 19,
            answer: .transaction("Loblaws", 127.86)
        )
    }

    @Test("What was my most expensive Uber ride?")
    func mostExpensiveUberRide() async throws {
        try await ask(
            "What was my most expensive Uber ride?",
            expecting: .init(merchant: "Uber"),
            matches: 14,
            answer: .transaction("Uber", 41.86)
        )
    }

    @Test("What's the cheapest thing I bought at Costco?")
    func cheapestCostcoPurchase() async throws {
        try await ask(
            "What's the cheapest thing I bought at Costco?",
            expecting: .init(merchant: "Costco"),
            matches: 5,
            answer: .transaction("Costco", 99.09)
        )
    }

    @Test("Largest restaurant bill in the past 6 months?")
    func largestRestaurantBillPastSixMonths() async throws {
        try await ask(
            "Largest restaurant bill in the past 6 months?",
            expecting: .init(categories: [.restaurants], dates: ("2026-04-06", "2026-10-06")),
            matches: 14,
            answer: .transaction("DoorDash", 54.58)
        )
    }

    @Test("Smallest Amazon order this year?")
    func smallestAmazonOrderThisYear() async throws {
        try await ask(
            "Smallest Amazon order this year?",
            expecting: .init(merchant: "Amazon", dates: ("2026-01-01", "2026-12-31")),
            matches: 6,
            answer: .transaction("Amazon", 46.31)
        )
    }

    @Test("Priciest flight I booked this year?")
    func priciestFlightThisYear() async throws {
        try await ask(
            "Priciest flight I booked this year?",
            expecting: .init(categories: [.airlines], dates: ("2026-01-01", "2026-12-31")),
            matches: 3,
            answer: .transaction("Air Canada", 684.21)
        )
    }

    // MARK: - Averages

    @Test("What's my average Uber ride cost?")
    func averageUberRide() async throws {
        try await ask(
            "What's my average Uber ride cost?",
            expecting: .init(merchant: "Uber"),
            matches: 14,
            answer: .average(22.94)
        )
    }

    @Test("On average, how much do I spend per grocery trip?")
    func averageGroceryTrip() async throws {
        try await ask(
            "On average, how much do I spend per grocery trip?",
            expecting: .init(categories: [.groceries]),
            matches: 24,
            answer: .average(65.14)
        )
    }

    @Test("Average Tim Hortons order in the past 6 months?")
    func averageTimHortonsPastSixMonths() async throws {
        try await ask(
            "Average Tim Hortons order in the past 6 months?",
            expecting: .init(merchant: "Tim Hortons", dates: ("2026-04-06", "2026-10-06")),
            matches: 6,
            answer: .average(9.01)
        )
    }

    @Test("What was my average restaurant bill last month?")
    func averageRestaurantBillLastMonth() async throws {
        try await ask(
            "What was my average restaurant bill last month?",
            expecting: .init(categories: [.restaurants], dates: ("2026-09-01", "2026-09-30")),
            matches: 4,
            answer: .average(17.84)
        )
    }

    @Test("How much does a typical Starbucks visit cost me?")
    func typicalStarbucksVisit() async throws {
        try await ask(
            "How much does a typical Starbucks visit cost me?",
            expecting: .init(merchant: "Starbucks"),
            matches: 9,
            answer: .average(9.43)
        )
    }

    // MARK: - When

    @Test("When did I last go to Costco?")
    func lastCostcoTrip() async throws {
        try await ask(
            "When did I last go to Costco?",
            expecting: .init(merchant: "Costco"),
            matches: 5,
            answer: .date("2026-09-28")
        )
    }

    @Test("When was my last Uber ride?")
    func lastUberRide() async throws {
        try await ask(
            "When was my last Uber ride?",
            expecting: .init(merchant: "Uber"),
            matches: 14,
            answer: .date("2026-10-03")
        )
    }

    @Test("What did I last buy at Best Buy?")
    func lastBestBuyPurchase() async throws {
        try await ask(
            "What did I last buy at Best Buy?",
            expecting: .init(merchant: "Best Buy"),
            matches: 2,
            answer: .dateAndAmount("2026-09-19", 429.99)
        )
    }

    @Test("When did I last fill up on gas?")
    func lastFillUp() async throws {
        try await ask(
            "When did I last fill up on gas?",
            expecting: .init(categories: [.gasStations]),
            matches: 10,
            answer: .date("2026-09-01")
        )
    }

    @Test("When was the last time I went to the movies?")
    func lastMovieNight() async throws {
        try await ask(
            "When was the last time I went to the movies?",
            expecting: .init(categories: [.entertainment]),
            matches: 5,
            answer: .date("2026-10-04")
        )
    }

    @Test("When did Rogers last charge me?")
    func lastRogersCharge() async throws {
        try await ask(
            "When did Rogers last charge me?",
            expecting: .init(merchant: "Rogers"),
            matches: 12,
            answer: .dateAndAmount("2026-10-03", 97.40)
        )
    }

    @Test("When did I first shop at IKEA?")
    func firstIkeaTrip() async throws {
        try await ask(
            "When did I first shop at IKEA?",
            expecting: .init(merchant: "IKEA"),
            matches: 2,
            answer: .date("2026-01-28")
        )
    }

    @Test("Did my GoodLife membership come out this month?")
    func goodLifeThisMonth() async throws {
        try await ask(
            "Did my GoodLife membership come out this month?",
            expecting: .init(merchant: "GoodLife Fitness", dates: ("2026-10-01", "2026-10-31")),
            matches: 1,
            answer: .dateAndAmount("2026-10-01", 59.99)
        )
    }

    // MARK: - Show me

    @Test("Show my last 3 Uber rides")
    func lastThreeUberRides() async throws {
        try await ask(
            "Show my last 3 Uber rides",
            expecting: .init(merchant: "Uber"),
            matches: 14,
            answer: .amounts([18.20, 13.85, 19.47])
        )
    }

    @Test("Show me my Netflix charges in August")
    func netflixChargesInAugust() async throws {
        try await ask(
            "Show me my Netflix charges in August",
            expecting: .init(merchant: "Netflix", dates: ("2026-08-01", "2026-08-31")),
            matches: 2,
            answer: .dates(["2026-08-15", "2026-08-16"])
        )
    }

    @Test("What did I buy yesterday?")
    func whatDidIBuyYesterday() async throws {
        try await ask(
            "What did I buy yesterday?",
            expecting: .init(dates: ("2026-10-05", "2026-10-05")),
            matches: 2,
            answer: .amounts([6.45, 87.34])
        )
    }

    @Test("What did I spend money on last weekend?")
    func lastWeekendSpending() async throws {
        try await ask(
            "What did I spend money on last weekend?",
            expecting: .init(dates: ("2026-10-03", "2026-10-04")),
            matches: 3,
            answer: .amounts([38.50, 18.20, 97.40])
        )
    }

    @Test("List everything I bought at Cactus Club")
    func everythingAtCactusClub() async throws {
        try await ask(
            "List everything I bought at Cactus Club",
            expecting: .init(merchant: "Cactus Club Cafe"),
            matches: 3,
            answer: .amounts([142.80, 96.55, 70.48])
        )
    }

    @Test("What were my 3 biggest purchases this year?")
    func threeBiggestPurchasesThisYear() async throws {
        try await ask(
            "What were my 3 biggest purchases this year?",
            expecting: .init(dates: ("2026-01-01", "2026-12-31")),
            matches: 150,
            answer: .amounts([742.18, 689.40, 684.21])
        )
    }

    @Test("Show my Lyft rides")
    func allLyftRides() async throws {
        try await ask(
            "Show my Lyft rides",
            expecting: .init(merchant: "Lyft"),
            matches: 3,
            answer: .amounts([16.84, 27.66, 22.31])
        )
    }

    // MARK: - Where and which

    @Test("Which city did I spend the most in?")
    func topCity() async throws {
        try await ask(
            "Which city did I spend the most in?",
            expecting: .everything,
            matches: 200,
            answer: .group("Toronto", 11541.26)
        )
    }

    @Test("Where do I spend the most on groceries?")
    func topGroceryStore() async throws {
        try await ask(
            "Where do I spend the most on groceries?",
            expecting: .init(categories: [.groceries]),
            matches: 24,
            answer: .group("Loblaws", 663.44)
        )
    }

    @Test("What category ate up most of my money last month?")
    func topCategoryLastMonth() async throws {
        try await ask(
            "What category ate up most of my money last month?",
            expecting: .init(dates: ("2026-09-01", "2026-09-30")),
            matches: 17,
            answer: .group("Electronic", 429.99)
        )
    }

    @Test("Which month did I spend the most on eating out?")
    func topEatingOutMonth() async throws {
        try await ask(
            "Which month did I spend the most on eating out?",
            expecting: .init(categories: [.restaurants]),
            matches: 35,
            answer: .group("December", 346.09)
        )
    }

    @Test("How much did I spend in Quebec?")
    func spentInQuebec() async throws {
        try await ask(
            "How much did I spend in Quebec?",
            expecting: .everything,
            matches: 200,
            answer: .group("Quebec", 1004.95)
        )
    }

    @Test("How much did I spend while I was in Vancouver?")
    func spentInVancouver() async throws {
        try await ask(
            "How much did I spend while I was in Vancouver?",
            expecting: .everything,
            matches: 200,
            answer: .group("Vancouver", 1040.21)
        )
    }

    @Test("How much did I spend in Montreal?")
    func spentInMontreal() async throws {
        try await ask(
            "How much did I spend in Montreal?",
            expecting: .everything,
            matches: 200,
            answer: .group("Montreal", 997.60)
        )
    }

    @Test("Which store did I spend the most at this year?")
    func topStoreThisYear() async throws {
        try await ask(
            "Which store did I spend the most at this year?",
            expecting: .init(dates: ("2026-01-01", "2026-12-31")),
            matches: 150,
            answer: .group("Marriott", 1102.06)
        )
    }

    @Test("Where did most of my rideshare money go?")
    func topRideshare() async throws {
        try await ask(
            "Where did most of my rideshare money go?",
            expecting: .init(categories: [.taxiAndRideshare]),
            matches: 17,
            answer: .group("Uber", 321.20)
        )
    }

    @Test("Which gas station do I use the most?")
    func topGasStation() async throws {
        try await ask(
            "Which gas station do I use the most?",
            expecting: .init(categories: [.gasStations]),
            matches: 10,
            answer: .group("Petro-Canada", 325.09)
        )
    }

    @Test("Break down my August spending by category")
    func augustByCategory() async throws {
        try await ask(
            "Break down my August spending by category",
            expecting: .init(dates: ("2026-08-01", "2026-08-31")),
            matches: 20,
            answer: .group("Hotel", 412.66)
        )
    }

    @Test("What was my most expensive month?")
    func mostExpensiveMonth() async throws {
        try await ask(
            "What was my most expensive month?",
            expecting: .everything,
            matches: 200,
            answer: .group("December", 3062.17)
        )
    }

    @Test("In which city did I spend the most on Uber?")
    func topUberCity() async throws {
        try await ask(
            "In which city did I spend the most on Uber?",
            expecting: .init(merchant: "Uber"),
            matches: 14,
            answer: .group("Toronto", 194.20)
        )
    }

    @Test("How much did I spend in Banff?")
    func spentInBanff() async throws {
        try await ask(
            "How much did I spend in Banff?",
            expecting: .everything,
            matches: 200,
            answer: .group("Banff", 1695.10)
        )
    }

    // MARK: - Nothing there

    @Test("How much did I spend at Walmart last week?")
    func walmartLastWeek() async throws {
        try await ask(
            "How much did I spend at Walmart last week?",
            expecting: .init(merchant: "Walmart", dates: ("2026-09-27", "2026-10-03")),
            matches: 0,
            answer: .nothing
        )
    }

    @Test("Did I spend anything at the Apple Store this month?")
    func appleStoreThisMonth() async throws {
        try await ask(
            "Did I spend anything at the Apple Store this month?",
            expecting: .init(merchant: "Apple Store", dates: ("2026-10-01", "2026-10-31")),
            matches: 0,
            answer: .nothing
        )
    }

    @Test("Any Lyft rides in the past month?")
    func lyftPastMonth() async throws {
        try await ask(
            "Any Lyft rides in the past month?",
            expecting: .init(merchant: "Lyft", dates: ("2026-09-06", "2026-10-06")),
            matches: 0,
            answer: .nothing
        )
    }

    @Test("Did I buy anything at Sephora last month?")
    func sephoraLastMonth() async throws {
        try await ask(
            "Did I buy anything at Sephora last month?",
            expecting: .init(merchant: "Sephora", dates: ("2026-09-01", "2026-09-30")),
            matches: 0,
            answer: .nothing
        )
    }

    @Test("Did Spotify charge me this year?")
    func spotifyThisYear() async throws {
        try await ask(
            "Did Spotify charge me this year?",
            expecting: .init(merchant: "Spotify", dates: ("2026-01-01", "2026-12-31")),
            matches: 0,
            answer: .nothing
        )
    }
}
