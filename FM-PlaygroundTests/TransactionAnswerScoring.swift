import Foundation
import FoundationModels
import Testing

@testable import FM_Playground

/// The filters a question really asks for, written out by hand in each test.
struct ExpectedScope {
    var merchant: String?
    var categories: [SpendingCategory] = []
    var minimum: Double?
    var maximum: Double?
    /// Inclusive `yyyy-MM-dd` bounds.
    var dates: (from: String, to: String)?

    static let everything = ExpectedScope()

    var scope: TransactionScope {
        TransactionScope(
            merchant: merchant,
            categories: categories,
            minimumCents: minimum.map { Int(($0 * 100).rounded()) },
            maximumCents: maximum.map { Int(($0 * 100).rounded()) },
            fromDate: dates?.from,
            toDate: dates?.to
        )
    }
}

/// What the answer text has to state.
enum ExpectedAnswer: CustomStringConvertible {
    /// A total, to the cent.
    case amount(Double)
    /// An average, within a cent either way of the rounded figure.
    case average(Double)
    /// How many transactions, as digits or words.
    case count(Int)
    /// One transaction — the biggest or smallest — by merchant and amount.
    case transaction(String, Double)
    /// A `yyyy-MM-dd` day, in any common spelling.
    case date(String)
    case dateAndAmount(String, Double)
    /// Every amount in a list.
    case amounts([Double])
    /// Every day in a list.
    case dates([String])
    /// A breakdown row: its name, and its total to the cent.
    case group(String, Double)
    /// No transactions matched, and the answer says so without inventing a figure.
    case nothing

    var description: String {
        switch self {
        case .amount(let value): "amount \(value)"
        case .average(let value): "average \(value)"
        case .count(let count): "count \(count)"
        case .transaction(let merchant, let value): "\(merchant) \(value)"
        case .date(let day): "date \(day)"
        case .dateAndAmount(let day, let value): "date \(day) and amount \(value)"
        case .amounts(let values): "amounts \(values)"
        case .dates(let days): "dates \(days)"
        case .group(let name, let value): "\(name) \(value)"
        case .nothing: "nothing found"
        }
    }

    /// Every expectation the answer misses, empty when it states them all.
    func misses(in answer: AnswerText, question: String) -> [String] {
        var misses: [String] = []
        func amount(_ value: Double, tolerance: Double = 0.005) {
            if !answer.mentions(amount: value, tolerance: tolerance) {
                misses.append("doesn't state \(Money.format(Int((value * 100).rounded())))")
            }
        }
        func day(_ iso: String) {
            if !answer.mentions(date: iso) { misses.append("doesn't state the date \(Money.day(iso))") }
        }
        func name(_ keyword: String) {
            if !answer.mentions(keyword) { misses.append("doesn't name \(keyword)") }
        }

        switch self {
        case .amount(let value): amount(value)
        case .average(let value): amount(value, tolerance: 0.015)
        case .count(let count):
            if !answer.mentions(count: count) { misses.append("doesn't state the count \(count)") }
        case .transaction(let merchant, let value):
            name(merchant)
            amount(value)
        case .date(let iso): day(iso)
        case .dateAndAmount(let iso, let value):
            day(iso)
            amount(value)
        case .amounts(let values): values.forEach { amount($0) }
        case .dates(let days): days.forEach(day)
        case .group(let keyword, let value):
            name(keyword)
            amount(value)
        case .nothing:
            if !answer.saysNothing(question: question) {
                misses.append("doesn't say that nothing matched, or states a figure anyway")
            }
        }
        return misses
    }
}

/// The model's answer, with the lookups the scoring needs.
///
/// Matching is by value rather than by string, so the model's choice of
/// formatting never decides a test: "$1,486.20", "1486.2" and "1,486.20
/// dollars" are the same number.
struct AnswerText {
    let text: String
    private let folded: String

    init(_ text: String) {
        self.text = text
        self.folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }

    // MARK: Numbers

    private static let number = #/\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?/#

    private static func value(_ match: Substring) -> Double? {
        Double(match.replacingOccurrences(of: ",", with: ""))
    }

    /// Every number written in `text`.
    static func numbers(in text: String) -> [Double] {
        text.matches(of: number).compactMap { value($0.output) }
    }

    /// Every dollar figure — a number straight after a `$`.
    static func dollarFigures(in text: String) -> [Double] {
        text.matches(of: #/\$\s?(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)/#)
            .compactMap { value($0.output.1) }
    }

    func mentions(amount: Double, tolerance: Double = 0.005) -> Bool {
        Self.numbers(in: text).contains { abs($0 - amount) < tolerance }
    }

    // MARK: Counts

    private static let words = [
        "zero": 0, "no": 0, "once": 1, "one": 1, "a single": 1, "twice": 2, "two": 2,
        "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "twenty": 20,
    ]

    private static let monthPattern =
        "(?:january|february|march|april|may|june|july|august|september|october|november|december"
        + "|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec)"

    /// True when the text states `count` as a count: a bare number that isn't
    /// part of a dollar figure, a year, or a date, or the word for it.
    func mentions(count: Int) -> Bool {
        var rest = folded
        let noise = [
            #"\$\s?[\d,]+(?:\.\d+)?"#,
            #"\d{4}-\d{2}-\d{2}"#,
            "\(Self.monthPattern)\\.?\\s+\\d{1,2}(?:st|nd|rd|th)?(?:,?\\s*\\d{4})?",
            #"\d{1,2}(?:st|nd|rd|th)?\s+(?:of\s+)?"# + Self.monthPattern,
            #"\b(?:19|20)\d{2}\b"#,
            #"\d+\.\d+"#,
        ]
        for pattern in noise {
            rest = rest.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        let digits = rest.matches(of: #/\b\d+\b/#).compactMap { Int($0.output) }
        if digits.contains(count) { return true }
        return Self.words.contains { word, value in
            value == count
                && rest.range(of: "\\b\(word)\\b", options: .regularExpression) != nil
        }
    }

    // MARK: Dates

    private static let monthNames: [[String]] = [
        ["january", "jan"], ["february", "feb"], ["march", "mar"], ["april", "apr"],
        ["may"], ["june", "jun"], ["july", "jul"], ["august", "aug"],
        ["september", "sept", "sep"], ["october", "oct"], ["november", "nov"], ["december", "dec"],
    ]

    /// True when the text names the `yyyy-MM-dd` day as "October 4", "Oct.
    /// 4th", "4 October", "2026-10-04" or "10/04".
    func mentions(date iso: String) -> Bool {
        if folded.contains(iso) { return true }
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        let (month, day) = (parts[1], parts[2])
        let names = Self.monthNames[month - 1].joined(separator: "|")
        let patterns = [
            "\\b(?:\(names))\\.?\\s+0?\(day)(?:st|nd|rd|th)?\\b",
            "\\b0?\(day)(?:st|nd|rd|th)?\\s+(?:of\\s+)?(?:\(names))\\b",
            "\\b0?\(month)/0?\(day)\\b",
        ]
        return patterns.contains { folded.range(of: $0, options: .regularExpression) != nil }
    }

    // MARK: Names

    private static func compact(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Case, accents, spacing and punctuation don't count: "Petro-Canada",
    /// "petro canada" and "PetroCanada" all name the same station.
    func mentions(_ keyword: String) -> Bool {
        Self.compact(text).contains(Self.compact(keyword))
    }

    // MARK: Nothing

    private static let negations = [
        "no ", "not ", "none", "n't", "never", "nothing", "zero", "$0", "any transactions",
    ]

    /// True when the text says nothing matched and states no dollar figure
    /// beyond the ones the question itself used.
    func saysNothing(question: String) -> Bool {
        guard Self.negations.contains(where: folded.contains) else { return false }
        let asked = Self.dollarFigures(in: question)
        return Self.dollarFigures(in: text).allSatisfy { figure in
            figure == 0 || asked.contains { abs($0 - figure) < 0.005 }
        }
    }
}

// MARK: - Running a case

extension TransactionAnswerTests {
    /// Asks one question through the Transactions tab's pipeline and scores
    /// the run against what it should have found and said.
    func ask(
        _ question: String,
        expecting expected: ExpectedScope,
        matches expectedCount: Int,
        answer expectedAnswer: ExpectedAnswer
    ) async throws {
        let store = TransactionStore.bundled
        let expectedScope = expected.scope
        let expectedIDs = Set(store.matching(expectedScope).map(\.id))

        // The fixture itself: the hand-written filters have to leave the
        // number of transactions the generator counted, or the expected
        // figure below belongs to some other question.
        try #require(
            expectedIDs.count == expectedCount,
            "fixture: expected filters match \(expectedIDs.count) transactions, not \(expectedCount)"
        )

        let answerer = TransactionAnswerer(store: store)
        answerer.prewarm()
        let answer = try await answerer.answer(question)
        let actualIDs = Set(answer.matches.map(\.id))

        let calls = answer.toolCalls.map { call in
            "\(call.toolName)(\(call.arguments))"
        }
        print("""
            \u{201C}\(question)\u{201D}
              filters: \(answer.scope.summary) → \(answer.matches.count) transactions
              parsed: merchant \(answer.parsed.filters.merchantName ?? "nil"), \
            categories [\(answer.parsed.categories.map(\.title).joined(separator: ", "))]\
            \(answer.parseMetrics.categoryNote.map { " — \($0)" } ?? "")
              expected: \(expectedScope.summary) → \(expectedCount) transactions
              tools: \(calls.isEmpty ? "none" : calls.joined(separator: ", "))
              answer: \(answer.text)
              expected answer: \(expectedAnswer)
              cost: parse \(answer.parseMetrics.latencyDescription), \
            answer \(answer.latency.latencyDescription), \
            \(answer.inputTokens) in (\(answer.cachedInputTokens) cached), \(answer.outputTokens) out
            """)

        // 1. The parse has to pick the same transactions.
        if actualIDs != expectedIDs {
            var withExpectedDates = answer.scope
            withExpectedDates.fromDate = expectedScope.fromDate
            withExpectedDates.toDate = expectedScope.toDate
            let datesOnly = Set(store.matching(withExpectedDates).map(\.id)) == expectedIDs

            let parsedDates = "\(answer.scope.fromDate ?? "nil") to \(answer.scope.toDate ?? "nil")"
            let wantedDates = "\(expectedScope.fromDate ?? "nil") to \(expectedScope.toDate ?? "nil")"
            if datesOnly {
                // The dates are the model's own reading through the date chain,
                // so a wrong range is a failure like any other.
                let chain = answer.parseMetrics.dateChain.map(\.description).joined(separator: " → ")
                print("  date chain: read \(parsedDates), expected \(wantedDates)\n  chain: \(chain)")
                Issue.record("date chain read \(parsedDates); expected \(wantedDates)")
            } else {
                Issue.record("""
                    parse picked \(actualIDs.count) transactions instead of \(expectedIDs.count): \
                    got \u{201C}\(answer.scope.summary)\u{201D}, expected \u{201C}\(expectedScope.summary)\u{201D}
                    """)
            }
            return
        }
        if answer.scope.fromDate != expectedScope.fromDate || answer.scope.toDate != expectedScope.toDate {
            print("  note: dates read as \(answer.scope.fromDate ?? "nil") to \(answer.scope.toDate ?? "nil"), "
                + "which matches the same transactions")
        }

        // 2. The answer has to come from a tool.
        #expect(!answer.toolCalls.isEmpty, "answered without calling a tool: \(answer.text)")

        // 3. And it has to say the right thing.
        let misses = expectedAnswer.misses(in: AnswerText(answer.text), question: question)
        #expect(misses.isEmpty, "answer \(misses.joined(separator: "; ")): \(answer.text)")
    }
}
