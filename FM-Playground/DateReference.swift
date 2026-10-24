import Foundation

/// The day a question is asked on, as the model is told it.
///
/// Gemma works its date ranges out itself, thinking from today's date — the
/// prompt carries the day, its weekday, and which day weeks start on, and no
/// worked-out ranges. The app does no date arithmetic on the model's behalf.
struct DateReference {
    let calendar: Calendar
    /// Midnight today, in the user's own calendar and time zone.
    let today: Date

    init(now: Date = .now, calendar: Calendar = .current) {
        self.calendar = calendar
        self.today = calendar.startOfDay(for: now)
    }

    private static let iso: DateFormatter = formatter("yyyy-MM-dd")
    private static let spelled: DateFormatter = formatter("EEEE, MMMM d, yyyy")
    private static let weekday: DateFormatter = formatter("EEEE")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    static func string(for date: Date) -> String { iso.string(from: date) }

    var todayString: String { Self.string(for: today) }

    /// "Tuesday, October 6, 2026 (2026-10-06)".
    var todayDescription: String {
        "\(Self.spelled.string(from: today)) (\(todayString))"
    }

    /// The weekday this calendar starts its weeks on, which is what "this
    /// week" and "last week" turn on.
    var firstWeekdayName: String {
        Self.weekday.weekdaySymbols[calendar.firstWeekday - 1]
    }

    /// The date rules both filtering prompts share: today, and what the
    /// phrases whose reading is a convention rather than arithmetic mean
    /// here. The model does the working out.
    var promptRules: String {
        """
        Today is \(todayDescription). Weeks start on \(firstWeekdayName).

        Work out the dates the question's time words cover, from today, as a first and last day:
        - "this week", "this month", "this year": all of it, through its last day.
        - "so far this …", "since …", "from the beginning of …": from the start through today.
        - "last week", "last month", "last year": all of the one before the current one.
        - "the past N days", "the last N days": the N days ending today, today included.
        - "the past N weeks", "months" or "years": from the same date N weeks, months or years \
        ago through today. Without a number, N is 1.
        - A month or year named on its own is all of it. A month named without a year is the \
        most recent one that has begun.
        - No time words at all: no dates.
        """
    }
}
