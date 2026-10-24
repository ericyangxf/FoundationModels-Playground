import Foundation
import FoundationModels

// The calendar tools count and nothing else. The model reads the question,
// decides which kind of range it names, and passes the numbers, units, and
// months as structured arguments; a tool turns them into an inclusive range
// and hands it back in two forms — `yyyy-MM-dd` for the filters, and words
// for the model to check against the question. No tool ever sees the
// question's text.

/// Calendar arithmetic pinned to one today, in the user's own calendar.
nonisolated struct CalendarArithmetic: Sendable {
    let calendar: Calendar
    /// Midnight today.
    let today: Date

    var currentYear: Int { calendar.component(.year, from: today) }

    func string(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// "Tuesday, October 6, 2026".
    func words(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }

    func adding(_ value: Int, _ component: Calendar.Component, to date: Date) -> Date {
        calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    /// The first and last day of the period holding `date`. `DateInterval.end`
    /// is the first instant of the next period, so the last day is one back.
    func period(_ component: Calendar.Component, containing date: Date) -> (first: Date, last: Date) {
        guard let interval = calendar.dateInterval(of: component, for: date) else { return (date, date) }
        return (interval.start, adding(-1, .day, to: interval.end))
    }

    func firstDay(month: Int, year: Int) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }

    /// The most recent first-of-`month` that isn't after today.
    func mostRecentFirstDay(month: Int) -> Date? {
        guard let thisYears = firstDay(month: month, year: currentYear) else { return nil }
        return thisYears > today ? firstDay(month: month, year: currentYear - 1) : thisYears
    }

    /// The range both ways, with the words spelling out where it stands
    /// against today.
    func range(_ first: Date, _ last: Date) -> CalendarRange {
        func describe(_ date: Date) -> String {
            words(for: date) + (calendar.isDate(date, inSameDayAs: today) ? " (today)" : "")
        }
        let days = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        let inWords = first == last
            ? "\(describe(first)) only"
            : "\(describe(first)) through \(describe(last)), \(days) days"
        return CalendarRange(fromDate: string(for: first), toDate: string(for: last), inWords: inWords)
    }
}

extension DateReference {
    nonisolated var arithmetic: CalendarArithmetic {
        CalendarArithmetic(calendar: calendar, today: today)
    }
}

/// What every calendar tool answers with.
@Generable(description: "An inclusive date range the calendar worked out.")
nonisolated struct CalendarRange: Equatable, Sendable {
    /// First day, `yyyy-MM-dd`.
    var fromDate: String
    /// Last day, `yyyy-MM-dd`.
    var toDate: String
    /// The same range in words, for checking against the question.
    var inWords: String
}


extension CalendarRange {
    /// What the tool hands back for `noTimeNamed`.
    nonisolated static let none = CalendarRange(fromDate: "", toDate: "", inWords: "no dates")

    nonisolated var isNone: Bool { fromDate.isEmpty && toDate.isEmpty }
}

/// What the calendar tool hands back: a range, or the problem with the call
/// that kept it from counting one. A problem is an observation like any
/// other — the session reads it and calls again — so it comes back as
/// output rather than as a thrown error that would end the turn.
@Generable(
    description: "The calendar tool's answer: a date range, or what was wrong with the call.",
    representNilExplicitlyInGeneratedContent: true
)
nonisolated struct DateRangeObservation: Equatable, Sendable {
    var range: CalendarRange?
    var problem: String?
}

/// Arguments a tool can't count with.
nonisolated enum CalendarToolError: Error, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let reason): reason
        }
    }
}

@Generable
nonisolated enum MonthName: CaseIterable {
    case january, february, march, april, may, june
    case july, august, september, october, november, december

    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
}

// MARK: - The tool

/// The kinds of range the calendar knows, each named the way questions say
/// it — down to one case per month, so "since June" is `sinceJune` rather
/// than a since-a-month kind plus a month argument. The model matches time
/// words against literal names far better than against abstract ones: with
/// five tools named for what they count it sent "last month" to a counted
/// span, and with one `sinceMonthName` case it read "since June" as
/// `sinceStartOfThisMonth` in both orders.
nonisolated enum RangeKind: String, CaseIterable, Sendable {
    case today, yesterday
    case thisWeek, lastWeek, thisWeekend, lastWeekend
    case thisMonth, lastMonth, thisYear, lastYear
    case pastNDays, pastNWeeks, pastNMonths, pastNYears
    case sinceStartOfThisWeek, sinceStartOfThisMonth, sinceStartOfThisYear
    // The same three, under the other names questions give them. Votes
    // compare ranges rather than names, so an alias never splits a vote.
    case soFarThisWeek, soFarThisMonth, soFarThisYear
    case fromTheBeginningOfThisWeek, fromTheBeginningOfThisMonth, fromTheBeginningOfThisYear
    case sinceJanuary, sinceFebruary, sinceMarch, sinceApril, sinceMay, sinceJune
    case sinceJuly, sinceAugust, sinceSeptember, sinceOctober, sinceNovember, sinceDecember
    case inJanuary, inFebruary, inMarch, inApril, inMay, inJune
    case inJuly, inAugust, inSeptember, inOctober, inNovember, inDecember
    case inYear
    /// Words that don't name a stretch of the calendar after all — "last"
    /// in "when did I last…", "month" in "which month…". The reader can copy
    /// them, and the act sessions only see what it copied, so these get kinds
    /// of their own, named the way they're written: told in the instructions
    /// that "which month" names no range, the model still read it as this
    /// month, but it matches a kind called `whichMonth` the way it matches
    /// `sinceJune`. All of them mean no dates.
    case month, whichDay, whichWeek, whichMonth, whichYear, last, first, lastTime
    case noTimeNamed

    /// The kinds that mean the words name no range.
    var namesNoRange: Bool {
        [.month, .whichDay, .whichWeek, .whichMonth, .whichYear, .last, .first, .lastTime, .noTimeNamed].contains(self)
    }

    /// A third order for a third reading: the single months first, then the
    /// rest as declared. The other two readings see the declared order and
    /// its reverse, which put the since-a-month kinds ahead of the in-a-month
    /// ones and behind them — and each pulled a bare month name its own way.
    static let monthsFirst: [RangeKind] = {
        let months = ranges.filter { $0.rawValue.hasPrefix("in") && $0.namedMonth != nil }
        return months + ranges.filter { !months.contains($0) } + nonRanges
    }()

    /// The declared order reversed — with the kinds that name no range left
    /// at the end, as in every order. Moved to the front by the reversal,
    /// they took bare month and year names: "March" as `whichMonth`, "2025"
    /// as `whichYear`.
    static let reversed: [RangeKind] = ranges.reversed() + nonRanges

    private static let ranges = allCases.filter { !$0.namesNoRange }
    private static let nonRanges = allCases.filter(\.namesNoRange)

    /// The `pastN` kind counting in this kind's unit, for a count that came
    /// with a single-period kind: "lastMonth, 3" means `pastNMonths`.
    var countedKind: RangeKind? {
        switch self {
        case .today, .yesterday: .pastNDays
        case .thisWeek, .lastWeek, .thisWeekend, .lastWeekend: .pastNWeeks
        case .thisMonth, .lastMonth, .month: .pastNMonths
        case .thisYear, .lastYear: .pastNYears
        default: nil
        }
    }

    /// The month a `sinceX` or `inX` case names.
    var namedMonth: Int? {
        let name = rawValue.hasPrefix("since") ? rawValue.dropFirst(5) : rawValue.hasPrefix("in") ? rawValue.dropFirst(2) : ""
        return MonthName.allCases.firstIndex { "\($0)".caseInsensitiveCompare(name) == .orderedSame }.map { $0 + 1 }
    }

    var takesCount: Bool { [.pastNDays, .pastNWeeks, .pastNMonths, .pastNYears].contains(self) }

    /// About ten years of whichever unit.
    var maximumCount: Int {
        switch self {
        case .pastNDays: 3660
        case .pastNWeeks: 520
        case .pastNMonths: 120
        default: 10
        }
    }
    /// "Between April and June" is `inApril` through June.
    var takesThroughMonth: Bool { namedMonth != nil && rawValue.hasPrefix("in") }
    /// A year can go with a named month — "in March 2025", "since June
    /// 2025" — or stand alone.
    var takesYear: Bool { (rawValue.hasPrefix("in") || namedMonth != nil) && !namesNoRange }

    /// The year `thisYear` and `lastYear` already mean, so a year written
    /// beside them can be checked rather than refused.
    func impliedYear(currentYear: Int) -> Int? {
        switch self {
        case .thisYear: currentYear
        case .lastYear: currentYear - 1
        default: nil
        }
    }
}

/// The one calendar tool: a kind of range plus whichever number, months, or
/// year that kind needs.
///
/// The kinds reach the model as a list whose order the caller picks, so two
/// sessions can read the same time words with the list in opposite orders —
/// a choice that survives both orders isn't an artifact of which name came
/// first.
///
/// Arguments a kind doesn't take come back as a problem naming what that
/// kind does take. The problem is the model's observation to act on; the
/// tool never guesses what was meant.
nonisolated struct DateRangeTool: Tool {
    typealias Arguments = GeneratedContent

    /// Read to catch several calls made in one step: each would be a
    /// different reading, so all of them get the same problem back and the
    /// model calls again, once.
    @SessionProperty(\.history) var history

    let name = "dateRange"
    let description = """
        Counts out the dates a kind of range covers, as of today. pastN kinds end today; \
        since kinds run from their first day on to today.
        """

    let arithmetic: CalendarArithmetic
    let kinds: [RangeKind]

    var parameters: GenerationSchema {
        GenerationSchema(
            type: GeneratedContent.self,
            description: "A kind of range and what it needs.",
            properties: [
                GenerationSchema.Property(
                    name: "kind",
                    description: "The kind of range, named the way the time words say it.",
                    type: String.self,
                    guides: [.anyOf(kinds.map(\.rawValue))]
                ),
                GenerationSchema.Property(
                    name: "count",
                    description: "For a pastN kind, the number the time words give, or 1 when they give none. Null for other kinds.",
                    type: Int?.self
                ),
                GenerationSchema.Property(
                    name: "throughMonth",
                    description: "For a run of months, the month it ends with: the second month the time words name. Null for one month.",
                    type: MonthName?.self
                ),
                GenerationSchema.Property(
                    name: "year",
                    description: "A year the time words write as a number. Null when they write none.",
                    type: Int?.self
                ),
            ]
        )
    }

    func call(arguments: GeneratedContent) async throws -> DateRangeObservation {
        let lastCalls = history.last { entry in
            if case .toolCalls = entry { true } else { false }
        }
        if case .toolCalls(let calls) = lastCalls, calls.count > 1 {
            return DateRangeObservation(problem: "dateRange was called \(calls.count) times at once. Call it once, with the one kind the time words name.")
        }
        do {
            let raw = try arguments.value(String.self, forProperty: "kind")
            guard let kind = RangeKind(rawValue: raw) else {
                throw CalendarToolError.invalid("kind must be one of the listed kinds.")
            }
            return DateRangeObservation(range: try range(
                kind,
                count: (try? arguments.value(Int?.self, forProperty: "count")) ?? nil,
                throughMonth: (try? arguments.value(MonthName?.self, forProperty: "throughMonth")) ?? nil,
                year: (try? arguments.value(Int?.self, forProperty: "year")) ?? nil
            ))
        } catch {
            return DateRangeObservation(problem: error.localizedDescription)
        }
    }

    /// The arithmetic for one kind. A missing count is 1 — "the past year"
    /// is one year.
    func range(
        _ kind: RangeKind,
        count: Int? = nil,
        throughMonth: MonthName? = nil,
        year: Int? = nil
    ) throws -> CalendarRange {
        // Arguments that only restate the kind — a count of 1 beside
        // `lastMonth`, this year's number beside `thisYear` — are let
        // through; arguments that contradict it come back as a problem.
        // The problem names the call that would take this count — worked out
        // from the kind's own unit, never from the time words.
        if let count, count > 1, !kind.takesCount {
            let fix = kind.countedKind.map { " That is \($0.rawValue) with count \(count)." } ?? ""
            throw CalendarToolError.invalid("\(kind.rawValue) is one period, not \(count) of them. A number of units back from today is a pastN kind.\(fix)")
        }
        // Without a count a pastN kind would quietly count one: after a
        // problem the model kept the kind and dropped the number, so "the
        // past 3 months" came back as one month.
        if count == nil, kind.takesCount {
            throw CalendarToolError.invalid("\(kind.rawValue) needs count: how many the time words say, or 1 when they give no number.")
        }
        // A count is how many units back; one that reaches back past any
        // card statement is a year or a slip, not a count.
        if let count, kind.takesCount, !(1...kind.maximumCount).contains(count) {
            throw CalendarToolError.invalid("\(kind.rawValue) counts 1 to \(kind.maximumCount) units back, not \(count). A year written as a number is inYear.")
        }
        if throughMonth != nil, !kind.takesThroughMonth {
            throw CalendarToolError.invalid("\(kind.rawValue) takes no throughMonth. A run of months is the inX kind for its first month, through the last.")
        }
        if let year, !kind.takesYear,
           year != (kind.impliedYear(currentYear: arithmetic.currentYear) ?? arithmetic.currentYear) {
            throw CalendarToolError.invalid("\(kind.rawValue) isn't in \(year). A year written as a number is inYear.")
        }

        let today = arithmetic.today
        let count = max(count ?? 1, 1)
        func period(_ component: Calendar.Component, back: Int) -> CalendarRange {
            let period = arithmetic.period(component, containing: arithmetic.adding(-back, component, to: today))
            return arithmetic.range(period.first, period.last)
        }
        func since(_ first: Date) -> CalendarRange { arithmetic.range(first, today) }
        /// Whole months from `first` through `last`; without a year, the
        /// most recent run that has already begun.
        func months(_ first: Int, through last: Int) -> CalendarRange? {
            let startYear: Int
            if let year {
                startYear = year
            } else {
                guard let mostRecent = arithmetic.mostRecentFirstDay(month: first) else { return nil }
                startYear = arithmetic.calendar.component(.year, from: mostRecent)
            }
            // November through February crosses into the next year.
            let endYear = last < first ? startYear + 1 : startYear
            guard let firstDay = arithmetic.firstDay(month: first, year: startYear),
                  let lastStart = arithmetic.firstDay(month: last, year: endYear)
            else { return nil }
            return arithmetic.range(firstDay, arithmetic.period(.month, containing: lastStart).last)
        }

        switch kind {
        case .today: return period(.day, back: 0)
        case .yesterday: return period(.day, back: 1)
        case .thisWeek: return period(.weekOfYear, back: 0)
        case .lastWeek: return period(.weekOfYear, back: 1)
        case .thisWeekend: return weekend(back: 0)
        case .lastWeekend: return weekend(back: 1)
        case .thisMonth: return period(.month, back: 0)
        case .lastMonth: return period(.month, back: 1)
        case .thisYear: return period(.year, back: 0)
        case .lastYear: return period(.year, back: 1)
        // N days ending today, today included; months and years go back to
        // the same day of the month.
        case .pastNDays: return since(arithmetic.adding(-(count - 1), .day, to: today))
        case .pastNWeeks: return since(arithmetic.adding(-(count * 7 - 1), .day, to: today))
        case .pastNMonths: return since(arithmetic.adding(-count, .month, to: today))
        case .pastNYears: return since(arithmetic.adding(-count, .year, to: today))
        case .sinceStartOfThisWeek, .soFarThisWeek, .fromTheBeginningOfThisWeek:
            return since(arithmetic.period(.weekOfYear, containing: today).first)
        case .sinceStartOfThisMonth, .soFarThisMonth, .fromTheBeginningOfThisMonth:
            return since(arithmetic.period(.month, containing: today).first)
        case .sinceStartOfThisYear, .soFarThisYear, .fromTheBeginningOfThisYear:
            return since(arithmetic.period(.year, containing: today).first)
        case .sinceJanuary, .sinceFebruary, .sinceMarch, .sinceApril, .sinceMay, .sinceJune,
             .sinceJuly, .sinceAugust, .sinceSeptember, .sinceOctober, .sinceNovember, .sinceDecember:
            if let month = kind.namedMonth,
               let first = year.flatMap({ arithmetic.firstDay(month: month, year: $0) })
                ?? arithmetic.mostRecentFirstDay(month: month) {
                return since(first)
            }
        case .inJanuary, .inFebruary, .inMarch, .inApril, .inMay, .inJune,
             .inJuly, .inAugust, .inSeptember, .inOctober, .inNovember, .inDecember:
            if let month = kind.namedMonth, let range = months(month, through: throughMonth?.number ?? month) {
                return range
            }
        case .inYear:
            guard let year else {
                throw CalendarToolError.invalid("inYear needs year: the year the time words write.")
            }
            if let first = arithmetic.firstDay(month: 1, year: year) {
                return arithmetic.range(first, arithmetic.period(.year, containing: first).last)
            }
        case .month, .whichDay, .whichWeek, .whichMonth, .whichYear, .last, .first, .lastTime, .noTimeNamed:
            return CalendarRange.none
        }
        throw CalendarToolError.invalid("Those arguments aren't on the calendar.")
    }

    /// A Saturday and the Sunday after it. During a weekend "this" is the one
    /// under way; on a weekday both "this" and "last" are the one just gone,
    /// since the coming one has no spending yet.
    private func weekend(back: Int) -> CalendarRange {
        let today = arithmetic.today
        let weekday = arithmetic.calendar.component(.weekday, from: today)
        let latestSaturday = arithmetic.adding(-(weekday % 7), .day, to: today)
        let inWeekend = weekday == 1 || weekday == 7
        let saturday = arithmetic.adding(-7 * (inWeekend ? back : 0), .day, to: latestSaturday)
        return arithmetic.range(saturday, arithmetic.adding(1, .day, to: saturday))
    }
}
