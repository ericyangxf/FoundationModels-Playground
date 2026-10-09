import Foundation
import FoundationModels
import Testing

@testable import FM_Playground

/// Scores the Foundation Models engine on date phrases alone: the date
/// reasoning chain in `DateReasoningChain.swift` reads the phrase, hands it to
/// the specialist session for its kind, which calls that kind's one date tool
/// in `DateTools.swift` and copies the range it answers with.
///
/// Every question runs on the `.foundationModels` engine — SwiftyChronoX takes
/// no part — and only the two dates are scored. The merchant, amount, and
/// category in the questions are there to make the sentences realistic, and
/// the accuracy suite already covers them.
///
/// Today is the device's own date, in its own calendar, exactly as the app
/// asks on the day. Each expected range is worked out for that day by
/// `ExpectedDates`, from these conventions:
///
/// - "the past N days", "from N days ago": N whole days back, through today.
/// - "N days ago", "yesterday": that one day.
/// - "this week", "this year": the period's first day through today.
/// - "last month", "last quarter": the whole of the previous period.
/// - A month or date without a year: the most recent one not in the future.
/// - "since …", "from …": through today.
///
/// Each test is written out in full, question and answer, so a red one says
/// what the model was asked and what it should have answered. Only the
/// mechanics of running the parse are shared.
///
/// Serialized, like the accuracy suite: there is one on-device model.
@MainActor
@Suite(.serialized, .enabled(if: foundationModelIsAvailable()))
struct FoundationModelDateTests {
    /// Taken fresh for each test, which uses it for both the question and the
    /// answer, so a test straddling midnight still scores against one day.
    let reference = DateReference()

    var expected: ExpectedDates { ExpectedDates(reference) }

    // MARK: Spans counted back from today

    @Test("Public transit spending in the past 128 days")
    func pastOneHundredTwentyEightDays() async throws {
        // A count big enough that the model can't have the answer memorised.
        try await expectRange("Public transit spending in the past 128 days", expected.pastDays(128))
    }

    @Test("Uber rides in the past 10 weeks")
    func pastTenWeeks() async throws {
        // Weeks count back seven days apiece.
        try await expectRange("Uber rides in the past 10 weeks", expected.pastWeeks(10))
    }

    @Test("Grocery spending over the last 3 months")
    func lastThreeMonths() async throws {
        // Months count back on the calendar, to the same day of the month.
        try await expectRange("Grocery spending over the last 3 months", expected.pastMonths(3))
    }

    @Test("Amazon orders in the past 2 years")
    func pastTwoYears() async throws {
        try await expectRange("Amazon orders in the past 2 years", expected.pastYears(2))
    }

    @Test("Restaurant spending in the last 18 months")
    func lastEighteenMonths() async throws {
        // More months than a year has, so the year has to roll back too.
        try await expectRange("Restaurant spending in the last 18 months", expected.pastMonths(18))
    }

    @Test("Coffee purchases in the last two weeks")
    func lastTwoWeeksSpelledOut() async throws {
        // The count is a word, not a digit.
        try await expectRange("Coffee purchases in the last two weeks", expected.pastWeeks(2))
    }

    @Test("Starbucks purchases in the past 7 days")
    func pastSevenDays() async throws {
        try await expectRange("Starbucks purchases in the past 7 days", expected.pastDays(7))
    }

    @Test("Spending in the last 30 days")
    func lastThirtyDays() async throws {
        try await expectRange("Spending in the last 30 days", expected.pastDays(30))
    }

    @Test("Walmart transactions in the past 90 days")
    func pastNinetyDays() async throws {
        try await expectRange("Walmart transactions in the past 90 days", expected.pastDays(90))
    }

    @Test("Taxi rides in the last 14 days")
    func lastFourteenDays() async throws {
        try await expectRange("Taxi rides in the last 14 days", expected.pastDays(14))
    }

    @Test("Total spending in the past 365 days")
    func pastThreeHundredSixtyFiveDays() async throws {
        // Counted in days, not as a year: the two land a day apart when the
        // span takes in a February 29.
        try await expectRange("Total spending in the past 365 days", expected.pastDays(365))
    }

    @Test("Pharmacy purchases in the last 60 days")
    func lastSixtyDays() async throws {
        try await expectRange("Pharmacy purchases in the last 60 days", expected.pastDays(60))
    }

    @Test("Home Depot purchases in the last 200 days")
    func lastTwoHundredDays() async throws {
        try await expectRange("Home Depot purchases in the last 200 days", expected.pastDays(200))
    }

    @Test("Dining out in the past 4 weeks")
    func pastFourWeeks() async throws {
        try await expectRange("Dining out in the past 4 weeks", expected.pastWeeks(4))
    }

    @Test("Gym payments over the past 52 weeks")
    func pastFiftyTwoWeeks() async throws {
        // 52 weeks is 364 days, a day or two short of a year.
        try await expectRange("Gym payments over the past 52 weeks", expected.pastWeeks(52))
    }

    @Test("Apple purchases in the last 6 months")
    func lastSixMonths() async throws {
        try await expectRange("Apple purchases in the last 6 months", expected.pastMonths(6))
    }

    @Test("Clothing purchases in the last 9 months")
    func lastNineMonths() async throws {
        try await expectRange("Clothing purchases in the last 9 months", expected.pastMonths(9))
    }

    @Test("Insurance payments in the last 12 months")
    func lastTwelveMonths() async throws {
        try await expectRange("Insurance payments in the last 12 months", expected.pastMonths(12))
    }

    @Test("Car repairs in the past 3 years")
    func pastThreeYears() async throws {
        try await expectRange("Car repairs in the past 3 years", expected.pastYears(3))
    }

    @Test("Office supplies in the past 2 quarters")
    func pastTwoQuarters() async throws {
        // Two quarters counted back is six months.
        try await expectRange("Office supplies in the past 2 quarters", expected.pastMonths(6))
    }

    @Test("Fast food in the past 5 days")
    func pastFiveDays() async throws {
        try await expectRange("Fast food in the past 5 days", expected.pastDays(5))
    }

    @Test("Gas station visits in the last three days")
    func lastThreeDaysSpelledOut() async throws {
        try await expectRange("Gas station visits in the last three days", expected.pastDays(3))
    }

    @Test("Grocery runs in the past twenty days")
    func pastTwentyDaysSpelledOut() async throws {
        try await expectRange("Grocery runs in the past twenty days", expected.pastDays(20))
    }

    @Test("Bar tabs in the last six weeks")
    func lastSixWeeksSpelledOut() async throws {
        try await expectRange("Bar tabs in the last six weeks", expected.pastWeeks(6))
    }

    @Test("Spotify charges in the past week")
    func pastWeek() async throws {
        // "The past week" is seven days back, not last calendar week.
        try await expectRange("Spotify charges in the past week", expected.pastWeeks(1))
    }

    @Test("Shopping in the past month")
    func pastMonth() async throws {
        // "The past month" is a month back from today, not last calendar month.
        try await expectRange("Shopping in the past month", expected.pastMonths(1))
    }

    @Test("Travel spending over the past year")
    func pastYear() async throws {
        // "The past year" is a year back from today, not last calendar year.
        try await expectRange("Travel spending over the past year", expected.pastYears(1))
    }

    @Test("Parking fees in the past 45 days")
    func pastFortyFiveDays() async throws {
        try await expectRange("Parking fees in the past 45 days", expected.pastDays(45))
    }

    @Test("Purchases within the last 10 days")
    func withinLastTenDays() async throws {
        try await expectRange("Purchases within the last 10 days", expected.pastDays(10))
    }

    // MARK: Spans starting some time ago

    @Test("Costco purchases from 2 months ago")
    func fromTwoMonthsAgo() async throws {
        // "from N months ago" starts N months back and runs through today —
        // not the single month two back.
        try await expectRange("Costco purchases from 2 months ago", expected.pastMonths(2))
    }

    @Test("Netflix charges since 3 weeks ago")
    func sinceThreeWeeksAgo() async throws {
        try await expectRange("Netflix charges since 3 weeks ago", expected.pastWeeks(3))
    }

    @Test("All my spending from 100 days ago")
    func fromOneHundredDaysAgo() async throws {
        try await expectRange("All my spending from 100 days ago", expected.pastDays(100))
    }

    @Test("Uber Eats orders since 10 days ago")
    func sinceTenDaysAgo() async throws {
        try await expectRange("Uber Eats orders since 10 days ago", expected.pastDays(10))
    }

    @Test("Electricity bills starting 6 months ago")
    func startingSixMonthsAgo() async throws {
        try await expectRange("Electricity bills starting 6 months ago", expected.pastMonths(6))
    }

    @Test("Amazon purchases from a year ago until today")
    func fromAYearAgoUntilToday() async throws {
        // "a year" is a count of one.
        try await expectRange("Amazon purchases from a year ago until today", expected.pastYears(1))
    }

    @Test("Coffee spending since 5 weeks ago")
    func sinceFiveWeeksAgo() async throws {
        try await expectRange("Coffee spending since 5 weeks ago", expected.pastWeeks(5))
    }

    // MARK: Single days

    @Test("What did I buy yesterday?")
    func yesterday() async throws {
        try await expectRange("What did I buy yesterday?", expected.daysAgo(1))
    }

    @Test("How much did I spend today?")
    func today() async throws {
        try await expectRange("How much did I spend today?", expected.daysAgo(0))
    }

    @Test("Lunch spending the day before yesterday")
    func dayBeforeYesterday() async throws {
        try await expectRange("Lunch spending the day before yesterday", expected.daysAgo(2))
    }

    @Test("What did I spend 3 days ago?")
    func threeDaysAgo() async throws {
        // Without "from" or "since", "N days ago" is that one day, not a span
        // up to today.
        try await expectRange("What did I spend 3 days ago?", expected.daysAgo(3))
    }

    @Test("What did I pay for 5 days ago?")
    func fiveDaysAgo() async throws {
        try await expectRange("What did I pay for 5 days ago?", expected.daysAgo(5))
    }

    @Test("Charges on my card 10 days ago")
    func tenDaysAgo() async throws {
        try await expectRange("Charges on my card 10 days ago", expected.daysAgo(10))
    }

    @Test("Restaurant bill two days ago")
    func twoDaysAgoSpelledOut() async throws {
        try await expectRange("Restaurant bill two days ago", expected.daysAgo(2))
    }

    // MARK: Calendar periods

    @Test("Uber rides this week")
    func thisWeek() async throws {
        // The week so far: its first day, as the calendar counts weeks, through
        // today.
        try await expectRange("Uber rides this week", expected.this(.week))
    }

    @Test("Dining out last week")
    func lastWeek() async throws {
        // The whole previous calendar week, not the past seven days.
        try await expectRange("Dining out last week", expected.last(.week))
    }

    @Test("Takeout the week before last")
    func weekBeforeLast() async throws {
        try await expectRange("Takeout the week before last", expected.last(.week, back: 2))
    }

    @Test("Spending so far this week")
    func soFarThisWeek() async throws {
        try await expectRange("Spending so far this week", expected.this(.week))
    }

    @Test("Purchases since the start of the week")
    func sinceStartOfWeek() async throws {
        try await expectRange("Purchases since the start of the week", expected.this(.week))
    }

    @Test("Shopping this month")
    func thisMonth() async throws {
        try await expectRange("Shopping this month", expected.this(.month))
    }

    @Test("Hotel spending last month")
    func lastMonth() async throws {
        // The whole of last month, to its last day — 30th or 31st, which the
        // model is likeliest to round.
        try await expectRange("Hotel spending last month", expected.last(.month))
    }

    @Test("Groceries the month before last")
    func monthBeforeLast() async throws {
        try await expectRange("Groceries the month before last", expected.last(.month, back: 2))
    }

    @Test("Phone bill for the previous month")
    func previousMonth() async throws {
        try await expectRange("Phone bill for the previous month", expected.last(.month))
    }

    @Test("How much have I spent so far this month?")
    func soFarThisMonth() async throws {
        try await expectRange("How much have I spent so far this month?", expected.this(.month))
    }

    @Test("Month to date restaurant spending")
    func monthToDate() async throws {
        try await expectRange("Month to date restaurant spending", expected.this(.month))
    }

    @Test("Spending since the start of the month")
    func sinceStartOfMonth() async throws {
        try await expectRange("Spending since the start of the month", expected.this(.month))
    }

    @Test("Grocery spending since last month")
    func sinceLastMonth() async throws {
        // "since last month" starts on the first of last month and runs
        // through today, not just to that month's end.
        try await expectRange("Grocery spending since last month", expected.sinceLast(.month))
    }

    @Test("Spending this quarter")
    func thisQuarter() async throws {
        try await expectRange("Spending this quarter", expected.this(.quarter))
    }

    @Test("Utility bills last quarter")
    func lastQuarter() async throws {
        // The whole previous calendar quarter.
        try await expectRange("Utility bills last quarter", expected.last(.quarter))
    }

    @Test("Advertising costs the quarter before last")
    func quarterBeforeLast() async throws {
        try await expectRange("Advertising costs the quarter before last", expected.last(.quarter, back: 2))
    }

    @Test("Spending in the first quarter")
    func firstQuarter() async throws {
        // A quarter named by number rather than counted back from this one.
        try await expectRange("Spending in the first quarter", expected.quarter(1))
    }

    @Test("Fuel costs in the third quarter of 2025")
    func thirdQuarterWithYear() async throws {
        try await expectRange("Fuel costs in the third quarter of 2025", expected.quarter(3, year: 2025))
    }

    @Test("Charity donations this year")
    func thisYear() async throws {
        try await expectRange("Charity donations this year", expected.this(.year))
    }

    @Test("Travel spending last year")
    func lastYear() async throws {
        try await expectRange("Travel spending last year", expected.last(.year))
    }

    @Test("Vacation spending the year before last")
    func yearBeforeLast() async throws {
        try await expectRange("Vacation spending the year before last", expected.last(.year, back: 2))
    }

    @Test("Total spending since the beginning of the year")
    func sinceBeginningOfYear() async throws {
        try await expectRange("Total spending since the beginning of the year", expected.this(.year))
    }

    @Test("Year to date spending on fuel")
    func yearToDate() async throws {
        try await expectRange("Year to date spending on fuel", expected.this(.year))
    }

    @Test("Amazon spending since last year")
    func sinceLastYear() async throws {
        // "since last year" starts on the first day of last year and runs
        // through today.
        try await expectRange("Amazon spending since last year", expected.sinceLast(.year))
    }

    @Test("Bar spending last weekend")
    func lastWeekend() async throws {
        // The latest Saturday and Sunday that are both over.
        try await expectRange("Bar spending last weekend", expected.lastWeekend())
    }

    // MARK: Months and dates on the calendar

    @Test("Starbucks transactions from July 30")
    func fromJulyThirty() async throws {
        try await expectRange("Starbucks transactions from July 30", expected.since(7, 30))
    }

    @Test("How much did I spend in August?")
    func inAugust() async throws {
        // Without a year, the most recent August that has begun — the one
        // under way, if it's August now, stops at today.
        try await expectRange("How much did I spend in August?", expected.month(8))
    }

    @Test("Electronics purchases in March 2025")
    func inMarchWithYear() async throws {
        // The year is given, so it overrides the most-recent-March rule.
        try await expectRange("Electronics purchases in March 2025", expected.month(3, year: 2025))
    }

    @Test("Gift shopping in December")
    func inDecember() async throws {
        // Until December comes round, this is last year's.
        try await expectRange("Gift shopping in December", expected.month(12))
    }

    @Test("Payments between June 1 and June 15")
    func betweenTwoJuneDates() async throws {
        // Both ends named outright: one tool call can't answer both. Asked in
        // early June, it's this June, up to today.
        try await expectRange("Payments between June 1 and June 15", expected.between((6, 1), and: (6, 15)))
    }

    @Test("Gas spending since September 15")
    func sinceSeptemberFifteen() async throws {
        try await expectRange("Gas spending since September 15", expected.since(9, 15))
    }

    @Test("What did I buy on September 3?")
    func onSeptemberThird() async throws {
        try await expectRange("What did I buy on September 3?", expected.date(9, 3))
    }

    @Test("Gym fees in January")
    func inJanuary() async throws {
        try await expectRange("Gym fees in January", expected.month(1))
    }

    @Test("Spending in October")
    func inOctober() async throws {
        try await expectRange("Spending in October", expected.month(10))
    }

    @Test("Online shopping in November")
    func inNovember() async throws {
        try await expectRange("Online shopping in November", expected.month(11))
    }

    @Test("Rent in February 2024")
    func inFebruaryLeapYear() async throws {
        // 2024 was a leap year: February ends on the 29th.
        try await expectRange("Rent in February 2024", expected.month(2, year: 2024))
    }

    @Test("Heating bills in February")
    func inFebruary() async throws {
        try await expectRange("Heating bills in February", expected.month(2))
    }

    @Test("Spending in 2025")
    func inYear() async throws {
        // A bare year is all twelve months of it.
        try await expectRange("Spending in 2025", expected.wholeYear(2025))
    }

    @Test("Utility bills in September last year")
    func inSeptemberLastYear() async throws {
        try await expectRange("Utility bills in September last year", expected.month(9, year: expected.thisYear - 1))
    }

    @Test("Streaming subscriptions since March")
    func sinceMarch() async throws {
        try await expectRange("Streaming subscriptions since March", expected.sinceMonth(3))
    }

    @Test("Restaurant spending from July onward")
    func fromJulyOnward() async throws {
        try await expectRange("Restaurant spending from July onward", expected.sinceMonth(7))
    }

    @Test("Medical expenses since January 1")
    func sinceJanuaryFirst() async throws {
        try await expectRange("Medical expenses since January 1", expected.since(1, 1))
    }

    @Test("Travel expenses from May to July")
    func fromMayToJuly() async throws {
        // A span of whole months: the first of May to the last of July.
        try await expectRange("Travel expenses from May to July", expected.months(5, through: 7))
    }

    @Test("Purchases from August 15 to September 15")
    func fromAugustFifteenToSeptemberFifteen() async throws {
        try await expectRange("Purchases from August 15 to September 15", expected.between((8, 15), and: (9, 15)))
    }

    @Test("What did I spend on October 1?")
    func onOctoberFirst() async throws {
        try await expectRange("What did I spend on October 1?", expected.date(10, 1))
    }

    @Test("Spending on December 25")
    func onDecemberTwentyFifth() async throws {
        // Until it comes round, this year's is still to come, so it's last
        // year's.
        try await expectRange("Spending on December 25", expected.date(12, 25))
    }

    @Test("What did I buy on March 15, 2026?")
    func onDateWithYear() async throws {
        try await expectRange("What did I buy on March 15, 2026?", expected.date(3, 15, year: 2026))
    }

    @Test("Transactions from 2026-08-01 to 2026-08-15")
    func isoDates() async throws {
        // Already in the output format: nothing to work out, only to copy.
        try await expectRange(
            "Transactions from 2026-08-01 to 2026-08-15",
            ExpectedDates.Range(from: "2026-08-01", to: "2026-08-15")
        )
    }

    @Test("Charges between 9/1 and 9/15")
    func numericDates() async throws {
        // Month first, the US way.
        try await expectRange("Charges between 9/1 and 9/15", expected.between((9, 1), and: (9, 15)))
    }

    @Test("Spending since 1 September")
    func dayFirstDate() async throws {
        try await expectRange("Spending since 1 September", expected.since(9, 1))
    }

    @Test("Coffee on Sept 30")
    func abbreviatedMonth() async throws {
        try await expectRange("Coffee on Sept 30", expected.date(9, 30))
    }

    // MARK: Days of the week

    @Test("Coffee last Friday")
    func lastFriday() async throws {
        // The latest Friday before today.
        try await expectRange("Coffee last Friday", expected.previous(.friday))
    }

    @Test("Spending since Monday")
    func sinceMonday() async throws {
        try await expectRange("Spending since Monday", expected.since(.monday))
    }

    @Test("Brunch on Sunday")
    func onSunday() async throws {
        try await expectRange("Brunch on Sunday", expected.previous(.sunday))
    }

    @Test("Groceries last Wednesday")
    func lastWednesday() async throws {
        try await expectRange("Groceries last Wednesday", expected.previous(.wednesday))
    }

    @Test("Spending since last Thursday")
    func sinceLastThursday() async throws {
        try await expectRange("Spending since last Thursday", expected.since(.thursday))
    }

    @Test("Lunch last Tuesday")
    func lastTuesday() async throws {
        // Asked on a Tuesday, a week back rather than today.
        try await expectRange("Lunch last Tuesday", expected.previous(.tuesday))
    }

    // MARK: -

    /// Runs `question` through the Foundation Models engine and checks the
    /// range it settles on, reporting any miss at the caller.
    private func expectRange(
        _ question: String,
        _ expected: ExpectedDates.Range,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let parser = QueryParser()
        parser.prewarm()
        let (parsed, metrics) = try await parser.parsedQuery(
            for: question,
            using: .foundationModels,
            reference: reference
        )
        let filters = parsed.filters

        print("""
            \u{201C}\(question)\u{201D}
              got: dates \(filters.fromDate ?? "nil")–\(filters.toDate ?? "nil"), expected \(expected)
              chain: \(metrics.dateChain.map(\.description).joined(separator: " → "))
              tools: \(metrics.toolCalls.isEmpty ? "none" : metrics.toolCalls.joined(separator: " | "))
              cost: \(metrics.latencyDescription), \
            \(metrics.inputTokens) in (\(metrics.cachedInputTokens) cached), \(metrics.outputTokens) out
            """)

        #expect(
            filters.fromDate == expected.from,
            "fromDate: expected \(expected.from), got \(filters.fromDate ?? "nil")",
            sourceLocation: sourceLocation
        )
        #expect(
            filters.toDate == expected.to,
            "toDate: expected \(expected.to), got \(filters.toDate ?? "nil")",
            sourceLocation: sourceLocation
        )
    }
}
