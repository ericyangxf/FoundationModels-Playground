import Foundation

/// The day a question is resolved against, in the user's own calendar.
///
/// The on-device model is small and unreliable at date arithmetic — asking it to
/// work out "the beginning of this year" from today's date is where it slips. So
/// the calendar tools do the arithmetic from here and leave it the part it is
/// good at: reading which range the question names.
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
}
