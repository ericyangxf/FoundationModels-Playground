import Foundation
import Testing

@testable import FM_Playground

/// The days the tools are checked on: today, as the app sees it, and fixed
/// days that bring out the edge cases — a Sunday, a year end, and a day inside
/// a span the questions name.
enum CheckDay: String, CaseIterable, CustomTestStringConvertible {
    case today
    case sunday = "Sunday 2026-10-04"
    case newYearsDay = "New Year's Day 2027"
    case midJune = "Thursday 2027-06-10"

    var testDescription: String { rawValue }

    @MainActor var reference: DateReference {
        switch self {
        case .today: DateReference()
        case .sunday: .gregorian(2026, 10, 4)
        case .newYearsDay: .gregorian(2027, 1, 1)
        case .midJune: .gregorian(2027, 6, 10)
        }
    }
}

/// Checks the date tools' arithmetic on its own: handed the arguments a
/// correct reading of each phrase would produce, each tool should answer the
/// range `ExpectedDates` works out.
///
/// No model involved, so these are instant and exact. Their job is to keep a
/// red test in `FoundationModelDateTests` meaning one thing: a session in the
/// reasoning chain picked the wrong kind or the wrong arguments, not that the
/// counting behind a right call is off. The tools take nothing else into
/// account — the scratch arguments are passed here only because every call
/// carries them.
@MainActor
struct DateToolTests {
    @Test("countBack: a span counted back from today", arguments: CheckDay.allCases)
    func countBack(on day: CheckDay) async throws {
        let reference = day.reference
        let expected = ExpectedDates(reference)
        let tool = CountBackTool(arithmetic: arithmetic(reference))
        let cases: [(count: Int, unit: DateUnit, expected: ExpectedDates.Range)] = [
            (128, .day, expected.pastDays(128)),
            (10, .week, expected.pastWeeks(10)),
            (18, .month, expected.pastMonths(18)),
            (2, .quarter, expected.pastMonths(6)),
            (2, .year, expected.pastYears(2)),
            (1, .month, expected.pastMonths(1)),
        ]
        for item in cases {
            let answer = try await tool.call(arguments: .init(number: "", count: item.count, unit: item.unit))
            #expect(answer == item.expected.answer, "\(item.count) \(item.unit)")
        }
    }

    @Test("countBack: turns down a negative count")
    func countBackRejectsNegative() async throws {
        let tool = CountBackTool(arithmetic: arithmetic(DateReference()))
        await #expect(throws: DateToolError.self) {
            try await tool.call(arguments: .init(number: "", count: -3, unit: .day))
        }
    }

    @Test("unitsAgo: one day back, or from it on to today", arguments: CheckDay.allCases)
    func unitsAgo(on day: CheckDay) async throws {
        let reference = day.reference
        let expected = ExpectedDates(reference)
        let single = UnitsAgoTool(arithmetic: arithmetic(reference))
        for days in [0, 1, 2, 3, 10] {
            let answer = try await single.call(arguments: .init(count: days, unit: .day))
            #expect(answer == expected.daysAgo(days).answer, "\(days) days ago")
        }
        let since = UnitsAgoTool(arithmetic: arithmetic(reference), runsToToday: true)
        let spans: [(count: Int, unit: DateUnit, expected: ExpectedDates.Range)] = [
            (3, .week, expected.pastWeeks(3)),
            (100, .day, expected.pastDays(100)),
            (6, .month, expected.pastMonths(6)),
            (1, .year, expected.pastYears(1)),
        ]
        for item in spans {
            let answer = try await since.call(arguments: .init(count: item.count, unit: item.unit))
            #expect(answer == item.expected.answer, "since \(item.count) \(item.unit) ago")
        }
    }

    @Test("calendarPeriod: whole periods, the current one cut at today", arguments: CheckDay.allCases)
    func calendarPeriod(on day: CheckDay) async throws {
        let reference = day.reference
        let expected = ExpectedDates(reference)
        let tool = CalendarPeriodTool(arithmetic: arithmetic(reference))
        let since = CalendarPeriodTool(arithmetic: arithmetic(reference), runsToToday: true)
        let cases: [(tool: CalendarPeriodTool, unit: PeriodUnit, which: WhichPeriod, expected: ExpectedDates.Range)] = [
            (tool, .week, .this, expected.this(.week)),
            (since, .week, .this, expected.this(.week)),
            (tool, .week, .last, expected.last(.week)),
            (tool, .week, .beforeLast, expected.last(.week, back: 2)),
            (tool, .weekend, .last, expected.lastWeekend()),
            (tool, .month, .this, expected.this(.month)),
            (since, .month, .this, expected.this(.month)),
            (tool, .month, .last, expected.last(.month)),
            (tool, .month, .beforeLast, expected.last(.month, back: 2)),
            (since, .month, .last, expected.sinceLast(.month)),
            (tool, .quarter, .this, expected.this(.quarter)),
            (tool, .quarter, .last, expected.last(.quarter)),
            (tool, .quarter, .beforeLast, expected.last(.quarter, back: 2)),
            (tool, .year, .this, expected.this(.year)),
            (since, .year, .this, expected.this(.year)),
            (tool, .year, .last, expected.last(.year)),
            (tool, .year, .beforeLast, expected.last(.year, back: 2)),
            (since, .year, .last, expected.sinceLast(.year)),
        ]
        for item in cases {
            let answer = try await item.tool.call(arguments: .init(unit: item.unit, which: item.which))
            #expect(answer == item.expected.answer, "\(item.which) \(item.unit), runsToToday \(item.tool.runsToToday)")
        }
    }

    @Test("calendarDate: months, days, quarters, years, and spans, with the year filled in", arguments: CheckDay.allCases)
    func calendarDate(on day: CheckDay) async throws {
        let reference = day.reference
        let expected = ExpectedDates(reference)
        let tool = CalendarDateTool(arithmetic: arithmetic(reference))
        let since = CalendarDateTool(arithmetic: arithmetic(reference), runsToToday: true)
        typealias Case = (label: String, tool: CalendarDateTool, first: String, year: Int?, second: String?, lastYear: LastYear?, expected: ExpectedDates.Range)
        let cases: [Case] = [
            ("in August", tool, "08", nil, nil, nil, expected.month(8)),
            ("in October", tool, "10", nil, nil, nil, expected.month(10)),
            ("in December", tool, "12", nil, nil, nil, expected.month(12)),
            ("in February 2024", tool, "02", 2024, nil, nil, expected.month(2, year: 2024)),
            ("in February 2024, year in front", tool, "2024-02", nil, nil, nil, expected.month(2, year: 2024)),
            ("in September last year", tool, "09", nil, nil, .lastYear, expected.month(9, year: expected.thisYear - 1)),
            ("on September 3", tool, "09-03", nil, nil, nil, expected.date(9, 3)),
            ("on December 25", tool, "12-25", nil, nil, nil, expected.date(12, 25)),
            ("on March 15, 2026", tool, "03-15", 2026, nil, nil, expected.date(3, 15, year: 2026)),
            ("from July 30", since, "07-30", nil, nil, nil, expected.since(7, 30)),
            ("since March", since, "03", nil, nil, nil, expected.sinceMonth(3)),
            ("in 2025", tool, "2025", nil, nil, nil, expected.wholeYear(2025)),
            ("in the first quarter", tool, "Q1", nil, nil, nil, expected.quarter(1)),
            ("in the third quarter of 2025", tool, "Q3", 2025, nil, nil, expected.quarter(3, year: 2025)),
            ("between June 1 and June 15", tool, "06-01", nil, "06-15", nil, expected.between((6, 1), and: (6, 15))),
            ("between 9/1 and 9/15", tool, "09-01", nil, "09-15", nil, expected.between((9, 1), and: (9, 15))),
            ("from August 15 to September 15", since, "08-15", nil, "09-15", nil, expected.between((8, 15), and: (9, 15))),
            ("from May to July", since, "05", nil, "07", nil, expected.months(5, through: 7)),
            ("from November to February", since, "11", nil, "02", nil, expected.months(11, through: 2)),
            ("from 2026-08-01 to 2026-08-15", since, "2026-08-01", nil, "2026-08-15", nil,
             ExpectedDates.Range(from: "2026-08-01", to: "2026-08-15")),
        ]
        for item in cases {
            let answer = try await item.tool.call(arguments: .init(
                first: item.first,
                year: item.year,
                second: item.second,
                lastYear: item.lastYear
            ))
            #expect(answer == item.expected.answer, "\(item.label)")
        }
    }

    @Test("calendarDate: turns down dates that aren't on the calendar or haven't come yet")
    func calendarDateRejectsInvalid() async throws {
        let reference = DateReference.gregorian(2026, 10, 6)
        let tool = CalendarDateTool(arithmetic: arithmetic(reference))
        for first in ["13", "09-00", "09-32", "Q5", "2026-12-25", "2027"] {
            await #expect(throws: DateToolError.self, "\(first)") {
                try await tool.call(arguments: .init(first: first, year: nil, second: nil, lastYear: nil))
            }
        }
    }

    @Test("CalendarNotation: every shape the guide describes decodes, and nothing else does")
    func calendarNotation() throws {
        #expect(try CalendarNotation("09") == .month(9, year: nil))
        #expect(try CalendarNotation("2024-02") == .month(2, year: 2024))
        #expect(try CalendarNotation("09-03") == .day(month: 9, day: 3, year: nil))
        #expect(try CalendarNotation("2026-03-15") == .day(month: 3, day: 15, year: 2026))
        #expect(try CalendarNotation("Q1") == .quarter(1, year: nil))
        #expect(try CalendarNotation("2025-Q3") == .quarter(3, year: 2025))
        #expect(try CalendarNotation("2025") == .year(2025))
        // A written year after the date instead of in front.
        #expect(try CalendarNotation("Q3 2025") == .quarter(3, year: 2025))
        #expect(try CalendarNotation("03, 2025") == .month(3, year: 2025))
        #expect(try CalendarNotation("03,2025") == .month(3, year: 2025))
        #expect(try CalendarNotation("03-15, 2026") == .day(month: 3, day: 15, year: 2026))
        for unreadable in ["September 3", "9/3", "", "Q", "2025-Q", "09-03-2026-01"] {
            #expect(throws: DateToolError.self, "\(unreadable)") { try CalendarNotation(unreadable) }
        }
    }

    @Test("weekday: the most recent one before today", arguments: CheckDay.allCases)
    func weekday(on day: CheckDay) async throws {
        let reference = day.reference
        let expected = ExpectedDates(reference)
        let tool = WeekdayTool(arithmetic: arithmetic(reference))
        let since = WeekdayTool(arithmetic: arithmetic(reference), runsToToday: true)
        let cases: [(tool: WeekdayTool, weekday: Weekday, expected: ExpectedDates.Range)] = [
            (tool, .friday, expected.previous(.friday)),
            (tool, .sunday, expected.previous(.sunday)),
            (tool, .tuesday, expected.previous(.tuesday)),
            (tool, .wednesday, expected.previous(.wednesday)),
            (since, .monday, expected.since(.monday)),
            (since, .thursday, expected.since(.thursday)),
        ]
        for item in cases {
            let answer = try await item.tool.call(arguments: .init(weekday: item.weekday))
            #expect(answer == item.expected.answer, "\(item.weekday), runsToToday \(item.tool.runsToToday)")
        }
    }

    @Test("OnceTool: answers the first call and turns down the second")
    func onceTool() async throws {
        let reference = DateReference()
        let tool = OnceTool(CalendarDateTool(arithmetic: arithmetic(reference)))
        let first = try await tool.call(arguments: .init(first: "05", year: nil, second: nil, lastYear: nil))
        #expect(first == ExpectedDates(reference).month(5).answer)
        await #expect(throws: DateToolError.self) {
            try await tool.call(arguments: .init(first: "07", year: nil, second: nil, lastYear: nil))
        }
    }

    private func arithmetic(_ reference: DateReference) -> DateArithmetic {
        DateArithmetic(calendar: reference.calendar, today: reference.today)
    }
}
