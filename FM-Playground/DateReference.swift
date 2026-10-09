import Foundation

/// The day a question is answered against, in one calendar.
///
/// The date tools count from `today` in `calendar`, so a whole parse — and a
/// test's expectations — share one reference and can't straddle midnight.
struct DateReference {
    let calendar: Calendar
    /// Midnight today, in the user's own calendar and time zone.
    let today: Date

    init(now: Date = .now, calendar: Calendar = .current) {
        self.calendar = calendar
        self.today = calendar.startOfDay(for: now)
    }
}
