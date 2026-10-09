import Foundation

@testable import FM_Playground

/// The range each date phrase should come back as, on whatever day the
/// reference says it is.
///
/// Worked straight out of `Calendar` from the conventions the date suites
/// list, rather than through `DateTools`, so the tools are graded against a
/// second reading of the rules instead of against themselves.
/// `ExpectedDatesTests` checks this reading against dates worked out by hand.
///
/// Like the tools, it never reaches past today: a period still in progress
/// stops at today, and a date named without a year is the most recent one that
/// has already come round.
@MainActor
struct ExpectedDates {
    struct Range: Equatable, CustomStringConvertible {
        var from: String
        var to: String

        /// The shape the date tools answer in.
        var answer: DateRange { DateRange(fromDate: from, toDate: to) }
        var description: String { "\(from)–\(to)" }
    }

    enum Period {
        case day, week, month, quarter, year
    }

    enum Weekday: Int {
        case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    }

    let calendar: Calendar
    let today: Date

    init(_ reference: DateReference) {
        calendar = reference.calendar
        today = reference.today
    }

    var thisYear: Int { calendar.component(.year, from: today) }

    // MARK: Spans counted back from today

    /// "the past N days", "from N days ago": N days back, through today.
    func pastDays(_ count: Int) -> Range { throughToday(from: shift(.day, -count)) }

    /// Weeks count back seven days apiece.
    func pastWeeks(_ count: Int) -> Range { pastDays(7 * count) }

    /// Months count back on the calendar, to the same day of the month.
    func pastMonths(_ count: Int) -> Range { throughToday(from: shift(.month, -count)) }

    func pastYears(_ count: Int) -> Range { throughToday(from: shift(.year, -count)) }

    // MARK: Single days

    /// "N days ago", "yesterday", "today": that one day.
    func daysAgo(_ count: Int) -> Range { on(shift(.day, -count)) }

    // MARK: Calendar periods

    /// "this week", "so far this month", "year to date": the period's first
    /// day through today.
    func this(_ period: Period) -> Range { throughToday(from: start(of: period, back: 0)) }

    /// "last month", "the quarter before last": the whole period, `back`
    /// periods before the current one.
    func last(_ period: Period, back: Int = 1) -> Range {
        let next = start(of: period, back: back - 1)
        return Range(from: string(start(of: period, back: back)), to: string(shift(.day, -1, from: next)))
    }

    /// "since last month": the first day of the last period, through today.
    func sinceLast(_ period: Period) -> Range { throughToday(from: start(of: period, back: 1)) }

    /// "last weekend": the latest Saturday and Sunday both before today.
    func lastWeekend() -> Range {
        var sunday = shift(.day, -1)
        while calendar.component(.weekday, from: sunday) != Weekday.sunday.rawValue {
            sunday = shift(.day, -1, from: sunday)
        }
        return Range(from: string(shift(.day, -1, from: sunday)), to: string(sunday))
    }

    // MARK: Months, dates, quarters, and years by name

    /// "in August", "in March 2025": the whole month.
    func month(_ month: Int, year: Int? = nil) -> Range {
        let first = mostRecent(year) { makeDate($0, month, 1) }
        return upToToday(first, shift(.day, -1, from: shift(.month, 1, from: first)))
    }

    /// "on September 3": that one day.
    func date(_ month: Int, _ day: Int, year: Int? = nil) -> Range {
        on(mostRecent(year) { makeDate($0, month, day) })
    }

    /// "since September 15", "from July 30": that day through today.
    func since(_ month: Int, _ day: Int) -> Range {
        throughToday(from: mostRecent(nil) { makeDate($0, month, day) })
    }

    /// "since March", "from July onward": the month's first day through today.
    func sinceMonth(_ month: Int) -> Range {
        throughToday(from: mostRecent(nil) { makeDate($0, month, 1) })
    }

    /// "between June 1 and June 15": the first date, and the first time the
    /// second comes round after it.
    func between(_ start: (month: Int, day: Int), and end: (month: Int, day: Int)) -> Range {
        let first = mostRecent(nil) { makeDate($0, start.month, start.day) }
        let year = calendar.component(.year, from: first)
        var last = makeDate(year, end.month, end.day)
        if last < first {
            last = makeDate(year + 1, end.month, end.day)
        }
        return upToToday(first, last)
    }

    /// "from May to July": the first of one month through the last of the
    /// next one named.
    func months(_ start: Int, through end: Int) -> Range {
        let first = mostRecent(nil) { makeDate($0, start, 1) }
        let year = calendar.component(.year, from: first)
        var lastMonth = makeDate(year, end, 1)
        if lastMonth < first {
            lastMonth = makeDate(year + 1, end, 1)
        }
        return upToToday(first, shift(.day, -1, from: shift(.month, 1, from: lastMonth)))
    }

    /// "in the first quarter", "in the third quarter of 2025".
    func quarter(_ quarter: Int, year: Int? = nil) -> Range {
        let first = mostRecent(year) { makeDate($0, quarter * 3 - 2, 1) }
        return upToToday(first, shift(.day, -1, from: shift(.month, 3, from: first)))
    }

    /// "in 2025": all of it.
    func wholeYear(_ year: Int) -> Range {
        upToToday(makeDate(year, 1, 1), makeDate(year, 12, 31))
    }

    // MARK: Days of the week

    /// "last Friday", "on Sunday": the latest one before today — a week back,
    /// when it's today's own weekday.
    func previous(_ weekday: Weekday) -> Range { on(latest(weekday)) }

    /// "since Monday": the latest one before today, through today.
    func since(_ weekday: Weekday) -> Range { throughToday(from: latest(weekday)) }

    // MARK: -

    private func shift(_ component: Calendar.Component, _ value: Int, from date: Date? = nil) -> Date {
        calendar.date(byAdding: component, value: value, to: date ?? today)!
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func string(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private func on(_ day: Date) -> Range { Range(from: string(day), to: string(day)) }

    private func throughToday(from start: Date) -> Range { Range(from: string(start), to: string(today)) }

    private func upToToday(_ first: Date, _ last: Date) -> Range {
        Range(from: string(first), to: string(min(last, today)))
    }

    /// In `year`, or with none given, this year's — unless that's still to
    /// come, in which case last year's.
    private func mostRecent(_ year: Int?, _ make: (Int) -> Date) -> Date {
        if let year { return make(year) }
        let thisYears = make(thisYear)
        return thisYears > today ? make(thisYear - 1) : thisYears
    }

    /// The first day of the `period` that's `back` periods before the
    /// current one.
    private func start(of period: Period, back: Int) -> Date {
        switch period {
        case .day:
            return shift(.day, -back)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: shift(.day, -7 * back))!.start
        case .month:
            let parts = calendar.dateComponents([.year, .month], from: shift(.month, -back))
            return makeDate(parts.year!, parts.month!, 1)
        case .quarter:
            let parts = calendar.dateComponents([.year, .month], from: shift(.month, -3 * back))
            return makeDate(parts.year!, (parts.month! - 1) / 3 * 3 + 1, 1)
        case .year:
            return makeDate(thisYear - back, 1, 1)
        }
    }

    private func latest(_ weekday: Weekday) -> Date {
        var day = shift(.day, -1)
        while calendar.component(.weekday, from: day) != weekday.rawValue {
            day = shift(.day, -1, from: day)
        }
        return day
    }
}

extension DateReference {
    /// Noon on a fixed day, in a Gregorian calendar whose weeks start on
    /// Sunday — for the model-free suites, which check the date rules on days
    /// that bring out their edge cases as well as on today.
    static func gregorian(_ year: Int, _ month: Int, _ day: Int) -> DateReference {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return DateReference(now: noon, calendar: calendar)
    }
}
