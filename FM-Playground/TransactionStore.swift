import Foundation

/// One card transaction from the bundled statement.
nonisolated struct Transaction: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    /// `yyyy-MM-dd`, which sorts and compares correctly as a plain string.
    let date: String
    let merchant: String
    /// Whole cents, so a total over two hundred rows never picks up
    /// floating-point dust.
    let cents: Int
    let city: String
    let province: String
    let country: String
    let mcc: Int

    /// The spending category whose code ranges hold this MCC, if any does.
    var category: SpendingCategory? {
        SpendingCategory.allCases.first { category in
            category.codeRanges.contains { $0.contains(mcc) }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, merchant, amount, city, province, country, mcc
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = try container.decode(String.self, forKey: .date)
        merchant = try container.decode(String.self, forKey: .merchant)
        cents = Int((try container.decode(Double.self, forKey: .amount) * 100).rounded())
        city = try container.decode(String.self, forKey: .city)
        province = try container.decode(String.self, forKey: .province)
        country = try container.decode(String.self, forKey: .country)
        mcc = try container.decode(Int.self, forKey: .mcc)
    }
}

/// The statement the Transactions tab answers questions about: two hundred
/// card transactions from transactions.json, all in Canada, covering the
/// twelve months up to `asOf`.
nonisolated struct TransactionStore: Sendable {
    /// The statement date, `yyyy-MM-dd`. Questions are answered as if asked on
    /// this day, so "last month" means the same thing in the app and in the
    /// tests no matter when either runs.
    let asOf: String
    /// Oldest first.
    let transactions: [Transaction]

    private struct File: Decodable {
        var asOf: String
        var transactions: [Transaction]
    }

    init(asOf: String, transactions: [Transaction]) {
        self.asOf = asOf
        self.transactions = transactions.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        self.init(asOf: file.asOf, transactions: file.transactions)
    }

    /// The copy bundled with the app. A missing or malformed file is a build
    /// problem rather than something a user can recover from.
    static let bundled: TransactionStore = {
        guard let url = Bundle.main.url(forResource: "transactions", withExtension: "json") else {
            fatalError("transactions.json is missing from the app bundle")
        }
        do {
            return try TransactionStore(data: Data(contentsOf: url))
        } catch {
            fatalError("transactions.json failed to decode: \(error)")
        }
    }()

    /// Midday on the statement date in the user's calendar — the "today" every
    /// question on the Transactions tab is resolved against.
    @MainActor var reference: DateReference {
        let parts = asOf.split(separator: "-").compactMap { Int($0) }
        let noon = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        return DateReference(now: Calendar.current.date(from: noon) ?? .now)
    }

    func matching(_ scope: TransactionScope) -> [Transaction] {
        transactions.filter(scope.matches)
    }
}

// MARK: - Scope

/// The filters a parsed question puts on the statement.
///
/// Built straight from the Query tab's parse, so the transaction answer reads
/// the same merchant, amounts, dates and categories that tab shows.
nonisolated struct TransactionScope: Equatable, Sendable {
    var merchant: String?
    var categories: [SpendingCategory]
    var minimumCents: Int?
    var maximumCents: Int?
    var fromDate: String?
    var toDate: String?

    init(
        merchant: String? = nil,
        categories: [SpendingCategory] = [],
        minimumCents: Int? = nil,
        maximumCents: Int? = nil,
        fromDate: String? = nil,
        toDate: String? = nil
    ) {
        self.merchant = merchant
        self.categories = categories
        self.minimumCents = minimumCents
        self.maximumCents = maximumCents
        self.fromDate = fromDate
        self.toDate = toDate
    }

    /// A named business wins over categories. The category session reads
    /// "Starbucks" as eating out and "Canadian Tire" as home improvement; with
    /// a merchant already pinning the search, that guess could only narrow it
    /// by mistake.
    ///
    /// A zero bound is the model's way of writing "no bound", the same reading
    /// the Query tab's tests give it.
    init(_ parsed: ParsedQuery) {
        let filters = parsed.filters
        let merchant = filters.merchantName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.merchant = merchant?.isEmpty == false ? merchant : nil
        self.categories = self.merchant == nil ? parsed.categories : []
        self.minimumCents = Self.cents(filters.fromAmount)
        self.maximumCents = Self.cents(filters.toAmount)
        self.fromDate = filters.fromDate
        self.toDate = filters.toDate
    }

    private static func cents(_ dollars: Double?) -> Int? {
        guard let dollars, dollars > 0 else { return nil }
        return Int((dollars * 100).rounded())
    }

    /// True when nothing narrows the statement at all.
    var isEverything: Bool {
        merchant == nil && categories.isEmpty && minimumCents == nil
            && maximumCents == nil && fromDate == nil && toDate == nil
    }

    func matches(_ transaction: Transaction) -> Bool {
        if let merchant, !Self.merchant(transaction.merchant, matches: merchant) { return false }
        if !categories.isEmpty {
            guard let category = transaction.category, categories.contains(category) else { return false }
        }
        if let minimumCents, transaction.cents < minimumCents { return false }
        if let maximumCents, transaction.cents > maximumCents { return false }
        if let fromDate, transaction.date < fromDate { return false }
        if let toDate, transaction.date > toDate { return false }
        return true
    }

    /// Loose the way a merchant search box is: case, spacing and punctuation
    /// don't count, and either name may hold the other — "uber rides" finds
    /// Uber, "GoodLife" finds GoodLife Fitness, "Tim Horton's" finds Tim
    /// Hortons.
    static func merchant(_ name: String, matches query: String) -> Bool {
        let name = compact(name), query = compact(query)
        guard !name.isEmpty, !query.isEmpty else { return false }
        return name.contains(query) || query.contains(name)
    }

    private static func compact(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    /// The filters in words, for the model's prompt and the result card.
    var summary: String {
        var parts: [String] = []
        if let merchant { parts.append("merchant \u{201C}\(merchant)\u{201D}") }
        if !categories.isEmpty {
            parts.append("category " + categories.map(\.title).joined(separator: " or "))
        }
        switch (minimumCents, maximumCents) {
        case let (low?, high?): parts.append("amount \(Money.format(low)) to \(Money.format(high))")
        case let (low?, nil): parts.append("amount \(Money.format(low)) or more")
        case let (nil, high?): parts.append("amount \(Money.format(high)) or less")
        case (nil, nil): break
        }
        switch (fromDate, toDate) {
        case let (from?, to?) where from == to: parts.append("on \(Money.day(from))")
        case let (from?, to?): parts.append("from \(Money.day(from)) to \(Money.day(to))")
        case let (from?, nil): parts.append("from \(Money.day(from)) on")
        case let (nil, to?): parts.append("up to \(Money.day(to))")
        case (nil, nil): break
        }
        return parts.isEmpty ? "no filters — every transaction" : parts.joined(separator: "; ")
    }
}

// MARK: - Aggregates

/// The figures a set of transactions boils down to.
nonisolated struct SpendingSummary: Equatable, Sendable {
    var count: Int
    var totalCents: Int
    /// Rounded half away from zero to the cent.
    var averageCents: Int
    var largest: Transaction?
    var smallest: Transaction?
    var earliest: Transaction?
    var latest: Transaction?

    /// Ties on amount go to the most recent transaction, so a run of identical
    /// monthly bills reports the latest one.
    init(_ transactions: [Transaction]) {
        count = transactions.count
        totalCents = transactions.reduce(0) { $0 + $1.cents }
        averageCents = count == 0
            ? 0
            : Int((Double(totalCents) / Double(count)).rounded(.toNearestOrAwayFromZero))
        let byDate = transactions.sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        earliest = byDate.first
        latest = byDate.last
        largest = byDate.reversed().max { $0.cents < $1.cents }
        smallest = byDate.reversed().min { $0.cents < $1.cents }
    }
}

/// What a breakdown can split the matching transactions by.
nonisolated enum SpendingGrouping: String, CaseIterable, Sendable {
    case merchant, category, city, province, month

    func key(for transaction: Transaction) -> String {
        switch self {
        case .merchant: transaction.merchant
        case .category: transaction.category?.title ?? "Other"
        case .city: "\(transaction.city), \(transaction.province)"
        case .province: transaction.province
        case .month: Money.month(transaction.date)
        }
    }
}

/// One line of a breakdown.
nonisolated struct SpendingGroup: Equatable, Sendable {
    var name: String
    var totalCents: Int
    var count: Int
}

extension TransactionStore {
    /// Groups highest total first; equal totals fall back to the name so the
    /// order never depends on dictionary iteration.
    nonisolated static func breakdown(_ transactions: [Transaction], by grouping: SpendingGrouping) -> [SpendingGroup] {
        var groups: [String: SpendingGroup] = [:]
        for transaction in transactions {
            let key = grouping.key(for: transaction)
            groups[key, default: SpendingGroup(name: key, totalCents: 0, count: 0)].totalCents += transaction.cents
            groups[key]?.count += 1
        }
        return groups.values.sorted { ($1.totalCents, $0.name) < ($0.totalCents, $1.name) }
    }
}

// MARK: - Formatting

/// Fixed-locale formatting for the screen and the filter summary the tool
/// hands the model, so they read the same on every device.
nonisolated enum Money {
    /// Cents as a dollar figure for the model's data: 148620 → 1486.2.
    static func dollars(_ cents: Int) -> Double {
        Double(cents) / 100
    }

    /// `$1,234.56`.
    static func format(_ cents: Int) -> String {
        (Decimal(cents) / 100).formatted(
            .currency(code: "CAD").locale(Locale(identifier: "en_CA"))
        )
    }

    private static let iso: DateFormatter = formatter("yyyy-MM-dd")
    private static let long: DateFormatter = formatter("MMMM d, yyyy")
    private static let monthYear: DateFormatter = formatter("MMMM yyyy")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }

    /// `2026-10-04` → `October 4, 2026`.
    static func day(_ iso: String) -> String {
        guard let date = Self.iso.date(from: iso) else { return iso }
        return long.string(from: date)
    }

    /// `2026-10-04` → `October 2026`.
    static func month(_ iso: String) -> String {
        guard let date = Self.iso.date(from: iso) else { return iso }
        return monthYear.string(from: date)
    }
}
