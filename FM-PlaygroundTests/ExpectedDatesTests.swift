import Foundation
import Testing

@testable import FM_Playground

/// Checks `ExpectedDates` against ranges worked out by hand.
///
/// Everything else in the date suites is graded by `ExpectedDates` on
/// whatever day the tests run, so this is where its arithmetic gets checked
/// against answers that weren't computed at all. That takes fixed days: one
/// ordinary Tuesday, plus a Sunday, New Year's Day, and a day in June, which
/// are where the weekend, year-end, and span rules show their edges.
@MainActor
struct ExpectedDatesTests {
    private typealias Case = (label: String, got: ExpectedDates.Range, from: String, to: String)

    private func check(_ cases: [Case]) {
        for item in cases {
            #expect(item.got == ExpectedDates.Range(from: item.from, to: item.to), "\(item.label)")
        }
    }

    @Test("Tuesday 6 October 2026")
    func tuesdayOctoberSixth() {
        let expected = ExpectedDates(.gregorian(2026, 10, 6))
        check([
            ("past 128 days", expected.pastDays(128), "2026-05-31", "2026-10-06"),
            ("past 10 weeks", expected.pastWeeks(10), "2026-07-28", "2026-10-06"),
            ("last 18 months", expected.pastMonths(18), "2025-04-06", "2026-10-06"),
            ("past 2 years", expected.pastYears(2), "2024-10-06", "2026-10-06"),
            ("past 365 days", expected.pastDays(365), "2025-10-06", "2026-10-06"),
            ("past 52 weeks", expected.pastWeeks(52), "2025-10-07", "2026-10-06"),
            ("3 days ago", expected.daysAgo(3), "2026-10-03", "2026-10-03"),
            ("this week", expected.this(.week), "2026-10-04", "2026-10-06"),
            ("last week", expected.last(.week), "2026-09-27", "2026-10-03"),
            ("the week before last", expected.last(.week, back: 2), "2026-09-20", "2026-09-26"),
            ("last month", expected.last(.month), "2026-09-01", "2026-09-30"),
            ("the month before last", expected.last(.month, back: 2), "2026-08-01", "2026-08-31"),
            ("since last month", expected.sinceLast(.month), "2026-09-01", "2026-10-06"),
            ("this quarter", expected.this(.quarter), "2026-10-01", "2026-10-06"),
            ("last quarter", expected.last(.quarter), "2026-07-01", "2026-09-30"),
            ("the quarter before last", expected.last(.quarter, back: 2), "2026-04-01", "2026-06-30"),
            ("year to date", expected.this(.year), "2026-01-01", "2026-10-06"),
            ("the year before last", expected.last(.year, back: 2), "2024-01-01", "2024-12-31"),
            ("since last year", expected.sinceLast(.year), "2025-01-01", "2026-10-06"),
            ("last weekend", expected.lastWeekend(), "2026-10-03", "2026-10-04"),
            ("in October", expected.month(10), "2026-10-01", "2026-10-06"),
            ("in December", expected.month(12), "2025-12-01", "2025-12-31"),
            ("in February 2024", expected.month(2, year: 2024), "2024-02-01", "2024-02-29"),
            ("on December 25", expected.date(12, 25), "2025-12-25", "2025-12-25"),
            ("from July 30", expected.since(7, 30), "2026-07-30", "2026-10-06"),
            ("since March", expected.sinceMonth(3), "2026-03-01", "2026-10-06"),
            ("between June 1 and June 15", expected.between((6, 1), and: (6, 15)), "2026-06-01", "2026-06-15"),
            ("from May to July", expected.months(5, through: 7), "2026-05-01", "2026-07-31"),
            ("in the first quarter", expected.quarter(1), "2026-01-01", "2026-03-31"),
            ("in the third quarter of 2025", expected.quarter(3, year: 2025), "2025-07-01", "2025-09-30"),
            ("in 2025", expected.wholeYear(2025), "2025-01-01", "2025-12-31"),
            ("last Friday", expected.previous(.friday), "2026-10-02", "2026-10-02"),
            ("last Wednesday", expected.previous(.wednesday), "2026-09-30", "2026-09-30"),
            ("last Tuesday, on a Tuesday", expected.previous(.tuesday), "2026-09-29", "2026-09-29"),
            ("since last Thursday", expected.since(.thursday), "2026-10-01", "2026-10-06"),
        ])
    }

    @Test("Sunday 4 October 2026: the week has only just started")
    func sundayOctoberFourth() {
        let expected = ExpectedDates(.gregorian(2026, 10, 4))
        check([
            ("this week", expected.this(.week), "2026-10-04", "2026-10-04"),
            ("last week", expected.last(.week), "2026-09-27", "2026-10-03"),
            ("last weekend, during one", expected.lastWeekend(), "2026-09-26", "2026-09-27"),
            ("last Sunday, on a Sunday", expected.previous(.sunday), "2026-09-27", "2026-09-27"),
            ("last Saturday", expected.previous(.saturday), "2026-10-03", "2026-10-03"),
        ])
    }

    @Test("Friday 1 January 2027: everything just rolled over a year")
    func newYearsDay() {
        let expected = ExpectedDates(.gregorian(2027, 1, 1))
        check([
            ("this week, across the year end", expected.this(.week), "2026-12-27", "2027-01-01"),
            ("last year", expected.last(.year), "2026-01-01", "2026-12-31"),
            ("last quarter", expected.last(.quarter), "2026-10-01", "2026-12-31"),
            ("in January", expected.month(1), "2027-01-01", "2027-01-01"),
            ("in December", expected.month(12), "2026-12-01", "2026-12-31"),
            ("the past month", expected.pastMonths(1), "2026-12-01", "2027-01-01"),
            ("last Friday, on a Friday", expected.previous(.friday), "2026-12-25", "2026-12-25"),
            ("last weekend", expected.lastWeekend(), "2026-12-26", "2026-12-27"),
            ("from November to February", expected.months(11, through: 2), "2026-11-01", "2027-01-01"),
        ])
    }

    @Test("Thursday 10 June 2027: inside a span the questions name")
    func midJune() {
        let expected = ExpectedDates(.gregorian(2027, 6, 10))
        check([
            ("past 128 days", expected.pastDays(128), "2027-02-02", "2027-06-10"),
            ("between June 1 and June 15", expected.between((6, 1), and: (6, 15)), "2027-06-01", "2027-06-10"),
            ("from May to July", expected.months(5, through: 7), "2027-05-01", "2027-06-10"),
            ("since September 15", expected.since(9, 15), "2026-09-15", "2027-06-10"),
            ("on June 15", expected.date(6, 15), "2026-06-15", "2026-06-15"),
            ("in December", expected.month(12), "2026-12-01", "2026-12-31"),
            ("in the first quarter", expected.quarter(1), "2027-01-01", "2027-03-31"),
            ("this quarter", expected.this(.quarter), "2027-04-01", "2027-06-10"),
            ("last Thursday, on a Thursday", expected.previous(.thursday), "2027-06-03", "2027-06-03"),
        ])
    }
}
