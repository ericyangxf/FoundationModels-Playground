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

    /// What both filtering prompts tell the model about dates: today, and
    /// which day weeks start on. How a phrase reads — the whole month or so
    /// far, the calendar week or the last seven days — is left to the model.
    /// A list of those conventions bled from one phrase into the next, and
    /// most readings Gemma picks without one are ones a search can live with.
    var promptRules: String {
        "Today is \(todayDescription). Weeks start on \(firstWeekdayName)."
    }
}
