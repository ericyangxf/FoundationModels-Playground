import Foundation

/// Calendar anchors computed ahead of time and handed to the model with the query.
///
/// The on-device model is small and unreliable at date arithmetic — asking it to
/// work out "the beginning of this year" from today's date is where it slips. So
/// we do the arithmetic here and leave it the part it is good at: matching a
/// phrase to one of these ranges and copying the dates out.
struct DateReference {
    let calendar: Calendar
    /// Midnight today, in the user's own calendar and time zone.
    let today: Date

    init(now: Date = .now, calendar: Calendar = .current) {
        self.calendar = calendar
        self.today = calendar.startOfDay(for: now)
    }

    private static let iso: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(for date: Date) -> String { iso.string(from: date) }

    var todayString: String { Self.string(for: today) }

    /// Midday today.
    ///
    /// SwiftyChronoX shifts the reference date it is handed by whole hours, so
    /// starting from noon keeps a daylight-saving jump from tipping a result
    /// into the day before.
    var midday: Date { calendar.date(byAdding: .hour, value: 12, to: today) ?? today }

    /// The inclusive first and last day of the calendar period containing `date`.
    ///
    /// `DateInterval.end` is the first instant of the *next* period, so the last
    /// day is one day back from it.
    private func period(_ component: Calendar.Component, containing date: Date) -> (start: String, end: String) {
        guard let interval = calendar.dateInterval(of: component, for: date) else {
            let day = Self.string(for: date)
            return (day, day)
        }
        let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return (Self.string(for: interval.start), Self.string(for: lastDay))
    }

    private func shifted(_ component: Calendar.Component, by value: Int) -> Date {
        calendar.date(byAdding: component, value: value, to: today) ?? today
    }

    private func daysAgo(_ count: Int) -> String {
        Self.string(for: shifted(.day, by: -count))
    }

    /// The block of resolved ranges that goes into the model's instructions.
    var resolvedRanges: String {
        let thisWeek = period(.weekOfYear, containing: today)
        let lastWeek = period(.weekOfYear, containing: shifted(.weekOfYear, by: -1))
        let thisMonth = period(.month, containing: today)
        let lastMonth = period(.month, containing: shifted(.month, by: -1))
        let thisYear = period(.year, containing: today)
        let lastYear = period(.year, containing: shifted(.year, by: -1))

        return """
        - today: \(todayString) to \(todayString)
        - yesterday: \(daysAgo(1)) to \(daysAgo(1))
        - this week: \(thisWeek.start) to \(thisWeek.end)
        - last week: \(lastWeek.start) to \(lastWeek.end)
        - this month: \(thisMonth.start) to \(thisMonth.end)
        - last month: \(lastMonth.start) to \(lastMonth.end)
        - this year: \(thisYear.start) to \(thisYear.end)
        - last year: \(lastYear.start) to \(lastYear.end)
        - last 7 days: \(daysAgo(6)) to \(todayString)
        - last 30 days: \(daysAgo(29)) to \(todayString)
        - last 90 days: \(daysAgo(89)) to \(todayString)
        - last 6 months: \(Self.string(for: shifted(.month, by: -6))) to \(todayString)
        - last 12 months: \(Self.string(for: shifted(.month, by: -12))) to \(todayString)
        """
    }
}
