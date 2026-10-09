import Foundation
import FoundationModels
import Synchronization

// The date tools do calendar arithmetic and nothing else. The model reads the
// question and decides what it says — how many of which unit, which period,
// which month and day, whether the range runs on to today — and passes that
// in as structured arguments. The tool counts it out and hands back both ends
// of an inclusive range, already formatted the way `TransactionQuery` wants
// them.
//
// No tool reads words, and no session sees more than one of them: the
// reasoning chain in `DateReasoningChain.swift` decides which kind of time a
// question names and hands its time words to a session holding only the tool
// for that kind. Whether since, from, or starting makes the range run on to
// today is decided by a pair of the chain's sessions and reaches the tool as
// `runsToToday`, not as an argument. A scratch argument such as `number` is
// there so the model writes those words down before deciding the rest; the
// arithmetic never looks at it. The calendar tool takes its dates in a fixed numeric notation
// — `09-03`, `2025-Q3` — which it decodes the way it would decode JSON; it
// never sees a month's name. So a range the date tests score is the model's
// own reading of the question, counted correctly.


/// The calendar arithmetic behind the date tools, pinned to one "today".
///
/// A spending question only ever looks backwards, so nothing here reaches past
/// today: a period still in progress stops at today, and a date named without
/// a year is the most recent one that has already come round.
nonisolated struct DateArithmetic: Sendable {
    let calendar: Calendar
    /// Midnight today.
    let today: Date

    var currentYear: Int { calendar.component(.year, from: today) }

    /// `yyyy-MM-dd`, read in the calendar's own time zone.
    func string(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The one shape every tool answers in, with the end cut off at today.
    func range(from start: Date, to end: Date) -> DateRange {
        DateRange(fromDate: string(for: start), toDate: string(for: min(end, today)))
    }

    func adding(_ value: Int, _ unit: DateUnit, to date: Date) -> Date {
        let (component, multiple): (Calendar.Component, Int) = switch unit {
        case .day: (.day, 1)
        case .week: (.day, 7)
        case .month: (.month, 1)
        case .quarter: (.month, 3)
        case .year: (.year, 1)
        }
        return calendar.date(byAdding: component, value: value * multiple, to: date) ?? date
    }

    /// The first and last day of the `unit` that contains `date`.
    ///
    /// `DateInterval.end` is the first instant of the *next* period, so the last
    /// day is one day back from it.
    func period(_ unit: DateUnit, containing date: Date) -> (first: Date, last: Date) {
        let first: Date
        let next: Date
        switch unit {
        case .quarter:
            // Calendar quarters start in January, April, July, and October.
            let parts = calendar.dateComponents([.year, .month], from: date)
            let startMonth = ((parts.month ?? 1) - 1) / 3 * 3 + 1
            first = calendar.date(from: DateComponents(year: parts.year, month: startMonth, day: 1)) ?? date
            next = calendar.date(byAdding: .month, value: 3, to: first) ?? first
        case .day, .week, .month, .year:
            let component: Calendar.Component = switch unit {
            case .day: .day
            case .week: .weekOfYear
            case .month: .month
            default: .year
            }
            guard let interval = calendar.dateInterval(of: component, for: date) else {
                return (date, date)
            }
            first = interval.start
            next = interval.end
        }
        return (first, calendar.date(byAdding: .day, value: -1, to: next) ?? next)
    }

    /// A Saturday and the Sunday after it.
    ///
    /// On a weekday, "this weekend" and "last weekend" both mean the one just
    /// gone — there's no spending yet in the one coming up. During a weekend,
    /// "this" is the one under way and "last" the one before it. `back` counts
    /// weekends back from the current one.
    func weekend(_ back: Int) -> (first: Date, last: Date) {
        let weekday = calendar.component(.weekday, from: today)
        let latestSaturday = adding(-(weekday % 7), .day, to: today)
        let inWeekend = weekday == 1 || weekday == 7
        let weeksBack = back - (inWeekend || back == 0 ? 0 : 1)
        let saturday = adding(-weeksBack, .week, to: latestSaturday)
        return (saturday, adding(1, .day, to: saturday))
    }

    /// A day of the month, with an out-of-range day — "June 31" — read as the
    /// month's last rather than spilling into the next one.
    func day(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month),
              let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))
        else { return nil }
        let length = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        return calendar.date(byAdding: .day, value: min(max(day, 1), length) - 1, to: first)
    }

    /// A month, or one day of it, in `year`.
    func range(year: Int, month: Int, day: Int?) -> (first: Date, last: Date)? {
        if let day {
            return self.day(year: year, month: month, day: day).map { ($0, $0) }
        }
        return self.day(year: year, month: month, day: 1).map { period(.month, containing: $0) }
    }

    /// A month, or one day of it, in `year` — or, with no year given, the most
    /// recent one that has already begun: "in December", asked in October, is
    /// the December just gone.
    func mostRecent(year: Int?, month: Int, day: Int?) -> (first: Date, last: Date)? {
        if let year { return range(year: year, month: month, day: day) }
        guard let thisYears = range(year: currentYear, month: month, day: day) else { return nil }
        return thisYears.first > today ? range(year: currentYear - 1, month: month, day: day) : thisYears
    }

    /// A month, or one day of it, the first time it comes round on or after
    /// `date`: the end of a span, as in "from November to February".
    func onOrAfter(_ date: Date, month: Int, day: Int?) -> (first: Date, last: Date)? {
        let year = calendar.component(.year, from: date)
        guard let sameYear = range(year: year, month: month, day: day) else { return nil }
        return sameYear.first < date ? range(year: year + 1, month: month, day: day) : sameYear
    }
}


/// Both ends of an inclusive range — what every date tool answers with, and
/// what the session holding the tool copies into its own answer.
@Generable(description: "An inclusive date range, both ends formatted yyyy-MM-dd.")
nonisolated struct DateRange: Equatable, Sendable {
    var fromDate: String
    var toDate: String
}

/// Arguments a tool can't count with. Thrown back to the reasoning chain,
/// which tells the session what was wrong and asks it once more.
nonisolated enum DateToolError: Error, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let reason): reason
        }
    }
}

@Generable
nonisolated enum DateUnit {
    case day, week, month, quarter, year
}

@Generable
nonisolated enum PeriodUnit {
    case week, weekend, month, quarter, year

    /// Nil for a weekend, which isn't a calendar period of its own.
    var dateUnit: DateUnit? {
        switch self {
        case .week: .week
        case .weekend: nil
        case .month: .month
        case .quarter: .quarter
        case .year: .year
        }
    }
}

/// Which period, named the way the question names it: the case names are the
/// question's own words, which is what the model matches best.
@Generable
nonisolated enum WhichPeriod {
    case this, last, beforeLast

    var periodsBack: Int {
        switch self {
        case .this: 0
        case .last: 1
        case .beforeLast: 2
        }
    }
}







/// "Last year" after a month or date: the year before this one. A single
/// case, so the model never has to know or write which year that is.
@Generable
nonisolated enum LastYear {
    case lastYear
}

/// A date in the calendar tool's notation: `MM` for a month, `MM-dd` for a
/// day, `Qn` for a quarter, `yyyy` for a year, and the year in front —
/// `yyyy-MM`, `yyyy-MM-dd`, `yyyy-Qn` — when the question writes it out.
///
/// The model writes dates this way far more reliably than it fills in a
/// month, a day, a quarter, and a year as separate optional numbers: it left
/// out the month of "since March" and put a day on "in January". Decoding it
/// is format parsing, like decoding JSON — the notation is the one the guide
/// pins down, never the question's own words.
nonisolated enum CalendarNotation: Equatable, Sendable {
    case month(Int, year: Int?)
    case day(month: Int, day: Int, year: Int?)
    case quarter(Int, year: Int?)
    case year(Int)

    // No `.pattern` guide pins this down: on device, a pattern guide on a
    // tool argument — even `\d\d-\d\d` — fails the call with "Failed to parse
    // generated content", though the same guide works on a response. The
    // model writes the notation from the description alone, and anything
    // else comes back to it as an error to fix.

    init(_ text: String) throws {
        // The model sometimes puts a written year after the date — "Q3 2025",
        // "03, 2025" — rather than in front. Same numbers, other order.
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        if parts.count == 2, parts[1].count == 4, Int(parts[1]) != nil, !parts[0].contains("-") || parts[0].count <= 5 {
            try self.init("\(parts[1])-\(parts[0])")
            return
        }
        let digits = text.split(separator: "-").map(String.init)
        func number(_ part: String) -> Int? { Int(part) }
        switch digits.count {
        case 1 where digits[0].hasPrefix("Q"):
            guard let quarter = Int(digits[0].dropFirst()) else { throw Self.unreadable(text) }
            self = .quarter(quarter, year: nil)
        case 1 where digits[0].count == 4:
            guard let year = number(digits[0]) else { throw Self.unreadable(text) }
            self = .year(year)
        case 1:
            guard let month = number(digits[0]) else { throw Self.unreadable(text) }
            self = .month(month, year: nil)
        case 2 where digits[0].count == 4 && digits[1].hasPrefix("Q"):
            guard let year = number(digits[0]), let quarter = Int(digits[1].dropFirst()) else { throw Self.unreadable(text) }
            self = .quarter(quarter, year: year)
        case 2 where digits[0].count == 4:
            guard let year = number(digits[0]), let month = number(digits[1]) else { throw Self.unreadable(text) }
            self = .month(month, year: year)
        case 2:
            guard let month = number(digits[0]), let day = number(digits[1]) else { throw Self.unreadable(text) }
            self = .day(month: month, day: day, year: nil)
        case 3:
            guard let year = number(digits[0]), let month = number(digits[1]), let day = number(digits[2]) else {
                throw Self.unreadable(text)
            }
            self = .day(month: month, day: day, year: year)
        default:
            throw Self.unreadable(text)
        }
    }

    private static func unreadable(_ text: String) -> DateToolError {
        .invalid("\(text) isn't written in numbers. Write MM for a month, MM-dd for a day, Qn for a quarter, or yyyy for a year — April is 04, April 12 is 04-12, the second quarter is Q2.")
    }

    var year: Int? {
        switch self {
        case .month(_, let year), .day(_, _, let year), .quarter(_, let year): year
        case .year(let year): year
        }
    }
}

@Generable
nonisolated enum Weekday: CaseIterable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday

    /// 1 for Sunday, as `Calendar` counts them.
    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
}


/// "The past N days", "since N weeks ago": a stretch counted back from today
/// that runs up to today.
nonisolated struct CountBackTool: Tool {
    let name = "countBack"
    let description = """
        The dates of a stretch of time that ends today and starts a number of days, weeks, \
        months, quarters, or years before it.
        """

    @Generable
    nonisolated struct Arguments {
        @Guide(description: #"How many units, as the time words write it: a numeral, a number word, or "a". Write "one" when they give no number."#)
        var number: String

        @Guide(description: "That number in digits.")
        var count: Int

        @Guide(description: "The unit the time words count in.")
        var unit: DateUnit
    }

    let arithmetic: DateArithmetic

    func call(arguments: Arguments) async throws -> DateRange {
        guard arguments.count >= 0 else {
            throw DateToolError.invalid("count can't be negative: it counts back from today.")
        }
        let start = arithmetic.adding(-arguments.count, arguments.unit, to: arithmetic.today)
        return arithmetic.range(from: start, to: arithmetic.today)
    }
}

/// "Yesterday", "3 days ago", "since 3 weeks ago": a day counted back from
/// today, alone or on to today.
nonisolated struct UnitsAgoTool: Tool {
    let name = "unitsAgo"
    let description = "The date of one day a number of days, weeks, months, quarters, or years before today."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: #"How many units before today: "today" is 0 days, "yesterday" 1 day, "the day before yesterday" 2 days, and "a month ago" 1 month."#)
        var count: Int

        @Guide(description: "The unit the time words count in.")
        var unit: DateUnit
    }

    let arithmetic: DateArithmetic
    /// Whether since, from, or starting opened the time words, as the chain
    /// read it.
    var runsToToday = false

    func call(arguments: Arguments) async throws -> DateRange {
        guard arguments.count >= 0 else {
            throw DateToolError.invalid("count can't be negative: it counts back from today.")
        }
        let day = arithmetic.adding(-arguments.count, arguments.unit, to: arithmetic.today)
        return arithmetic.range(from: day, to: runsToToday ? arithmetic.today : day)
    }
}

/// "Last month", "this year", "the week before last", "since last month": a
/// calendar period counted back from the current one.
nonisolated struct CalendarPeriodTool: Tool {
    let name = "calendarPeriod"
    let description = """
        The dates of a whole week, weekend, month, quarter, or year, counted from the current \
        one. A period still under way ends today.
        """

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "The kind of period.")
        var unit: PeriodUnit

        @Guide(description: #"Which one: this, last, or beforeLast for "the … before last"."#)
        var which: WhichPeriod
    }

    let arithmetic: DateArithmetic
    /// Whether since or from opened the time words: "since last month" runs
    /// from its first day on to today.
    var runsToToday = false

    func call(arguments: Arguments) async throws -> DateRange {
        let back = arguments.which.periodsBack
        let period = if let unit = arguments.unit.dateUnit {
            arithmetic.period(unit, containing: arithmetic.adding(-back, unit, to: arithmetic.today))
        } else {
            arithmetic.weekend(back)
        }
        return arithmetic.range(from: period.first, to: runsToToday ? arithmetic.today : period.last)
    }
}

/// "In August", "on September 3", "since July 30", "in the first quarter",
/// "between June 1 and June 15": months, days, quarters, and years named on
/// the calendar, without the model having to work out which year a bare one
/// falls in.
nonisolated struct CalendarDateTool: Tool {
    let name = "calendarDate"
    let description = """
        The dates of a month, a day, a quarter, or a year named on the calendar, or of a span \
        from one date to a second. Without a year, it picks the most recent one that isn't in \
        the future.
        """

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "The first or only date in numbers: MM for a month, MM-dd for a day with the month first, Qn for a quarter — April is 04, April 12 is 04-12, 12 April is 04-12, 1 April is 04-01, the second quarter is Q2. A year on its own is yyyy.")
        var first: String

        @Guide(description: "The year the time words write for the first date. Null when they write none.")
        var year: Int?

        @Guide(description: "The second date, in numbers the same way, when the time words name two — a span from the first date to it. Null otherwise.")
        var second: String?

        @Guide(description: #"lastYear when the time words say "last year" after the date. Null otherwise."#)
        var lastYear: LastYear?
    }

    let arithmetic: DateArithmetic
    /// Whether since, from, or starting opened the time words. A second date
    /// ends the range wherever it says, opener or not: "from May to July".
    var runsToToday = false

    func call(arguments: Arguments) async throws -> DateRange {
        let defaultYear = arguments.year ?? (arguments.lastYear == nil ? nil : arithmetic.currentYear - 1)
        let first = try range(of: CalendarNotation(arguments.first), defaultYear: defaultYear, onOrAfter: nil)
        if let second = arguments.second {
            let end = try range(of: CalendarNotation(second), defaultYear: defaultYear, onOrAfter: first.first)
            return arithmetic.range(from: first.first, to: end.last)
        }
        return arithmetic.range(from: first.first, to: runsToToday ? arithmetic.today : first.last)
    }

    /// The days `date` covers. With no year of its own it takes `defaultYear`;
    /// failing that, the first time it comes round on or after `onOrAfter`
    /// when there is one — the end of a span — or else the most recent one
    /// that has begun.
    private func range(of date: CalendarNotation, defaultYear: Int?, onOrAfter: Date?) throws -> (first: Date, last: Date) {
        let year = date.year ?? defaultYear
        let resolved: (first: Date, last: Date)?
        switch date {
        case .month(let month, _):
            try check(month: month)
            resolved = resolve(year, onOrAfter, month: month, day: nil)
        case .day(let month, let day, _):
            try check(month: month)
            guard (1...31).contains(day) else {
                throw DateToolError.invalid("\(day) isn't a day of the month: write MM for a whole month.")
            }
            resolved = resolve(year, onOrAfter, month: month, day: day)
        case .quarter(let quarter, _):
            guard (1...4).contains(quarter) else { throw DateToolError.invalid("Q\(quarter) isn't a quarter: use Q1 through Q4.") }
            resolved = resolve(year, onOrAfter, month: quarter * 3 - 2, day: nil).flatMap { first in
                arithmetic.onOrAfter(first.first, month: quarter * 3, day: nil).map { (first.first, $0.last) }
            }
        case .year(let year):
            resolved = arithmetic.day(year: year, month: 1, day: 1).map { arithmetic.period(.year, containing: $0) }
        }
        guard let resolved else { throw DateToolError.invalid("That isn't a date on the calendar.") }
        // A spending question only looks back, so a first date still to come
        // has a year written in rather than read. The end of a span can run
        // past today; the answer stops at today anyway.
        guard onOrAfter != nil || resolved.first <= arithmetic.today else {
            throw DateToolError.invalid("That date hasn't come yet. If the time words write no year, leave year null: the tool takes the most recent one.")
        }
        return resolved
    }

    private func resolve(_ year: Int?, _ onOrAfter: Date?, month: Int, day: Int?) -> (first: Date, last: Date)? {
        if let year { return arithmetic.range(year: year, month: month, day: day) }
        if let onOrAfter { return arithmetic.onOrAfter(onOrAfter, month: month, day: day) }
        return arithmetic.mostRecent(year: nil, month: month, day: day)
    }

    private func check(month: Int) throws {
        guard (1...12).contains(month) else {
            throw DateToolError.invalid("\(month) isn't a month: write 01 for January through 12 for December.")
        }
    }
}

/// "Last Friday", "since Monday": a day of the week, taken as the most recent
/// one before today.
nonisolated struct WeekdayTool: Tool {
    let name = "weekday"
    let description = "The date of a day of the week, as the most recent one before today."

    @Generable
    nonisolated struct Arguments {
        var weekday: Weekday
    }

    let arithmetic: DateArithmetic
    /// Whether since, from, or starting opened the time words.
    var runsToToday = false

    func call(arguments: Arguments) async throws -> DateRange {
        let calendar = arithmetic.calendar
        let back = (calendar.component(.weekday, from: arithmetic.today) - arguments.weekday.number + 7) % 7
        // Today's own weekday means the one a week back: "last Tuesday", asked
        // on a Tuesday, isn't today.
        let day = arithmetic.adding(-(back == 0 ? 7 : back), .day, to: arithmetic.today)
        return arithmetic.range(from: day, to: runsToToday ? arithmetic.today : day)
    }
}

/// A specialist's tool, callable once per session.
///
/// Even with tool calling switched off after the first output, the model can
/// make two calls in one step — "from May to July" came in as one call for
/// May and one for July, and the answer took the wrong end. The second call
/// is turned down with the reason, and the chain asks again.
nonisolated struct OnceTool<Base: Tool>: Tool {
    typealias Arguments = Base.Arguments
    typealias Output = Base.Output

    let base: Base
    private let calls = CallCount()

    init(_ base: Base) { self.base = base }

    var name: String { base.name }
    var description: String { base.description }
    var parameters: GenerationSchema { base.parameters }
    var includesSchemaInInstructions: Bool { base.includesSchemaInInstructions }

    func call(arguments: Arguments) async throws -> Output {
        guard calls.next() == 1 else {
            throw DateToolError.invalid("Call \(name) only once: everything goes in one call, a second date included.")
        }
        return try await base.call(arguments: arguments)
    }
}

/// How many calls a `OnceTool` has had, shared by every copy of it.
nonisolated final class CallCount: Sendable {
    private let count = Mutex(0)

    func next() -> Int {
        count.withLock { count in
            count += 1
            return count
        }
    }
}
