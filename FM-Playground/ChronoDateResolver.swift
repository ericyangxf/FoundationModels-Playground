import Foundation
import SwiftyChronoX

/// Reads the date range out of a question with SwiftyChronoX instead of the model.
///
/// SwiftyChronoX matches the phrase and does the calendar arithmetic in one
/// step, so an open-ended window like "the past 40 days" resolves as readily as
/// "last week" — no list of pre-computed ranges for the query to fall off the
/// end of.
struct ChronoDateResolver {
    /// A resolved range, already in the `yyyy-MM-dd` shape `TransactionQuery` wants.
    struct Resolution: Equatable {
        var fromDate: String?
        var toDate: String?
        /// The words SwiftyChronoX recognised — "past 40 days" — so the run can
        /// show what it keyed off. Nil when it found no date at all.
        var matchedText: String?

        static let none = Resolution()
    }

    /// A spending question always looks backwards, so a bare month or weekday
    /// means the most recent one. Without this, "since March" asked in August
    /// lands in *next* March.
    private static let options: [OptionType: Int] = [.backwardDate: 1]

    private let chrono = Chrono(preferredLanguage: .english)

    /// Compiles the parsers' expressions so the first real question doesn't pay
    /// for them — the same reason the model session gets prewarmed.
    func warmUp() {
        _ = chrono.parse(text: "last week", refDate: .now, opt: Self.options)
    }

    func resolve(_ text: String, reference: DateReference) -> Resolution {
        // Results come back sorted by where they appear in the sentence, and the
        // range refiners have already merged "from X to Y" into a single one, so
        // the first is the range the question is about.
        guard let result = chrono
            .parse(text: text, refDate: reference.midday, opt: Self.options)
            .first
        else {
            return .none
        }

        let from = DateReference.string(for: result.start.date)
        return Resolution(fromDate: from, toDate: end(of: result, from: from, reference: reference), matchedText: result.text)
    }

    /// The last day of the range.
    ///
    /// A period — "last week", "this month", "yesterday" — comes back with both
    /// ends filled in. A lookback window like "past 40 days" or "last 3 weeks"
    /// only carries the day it starts on and runs up to today. Anything else
    /// with one date is a single day.
    private func end(of result: ParsedResult, from: String, reference: DateReference) -> String {
        if let end = result.end {
            return DateReference.string(for: end.date)
        }
        // The `start <= today` check keeps a forward-looking phrase from
        // producing a range that ends before it begins.
        if result.tags[.enRelativeDateFormatParser] == true, result.start.date <= reference.midday {
            return reference.todayString
        }
        return from
    }
}
