import Foundation
import FoundationModels

/// Answers a question about the bundled statement in two steps.
///
/// First the Query tab's own parse — the model reading merchant, amounts,
/// dates and categories — turns the question into filters.
/// Then a second model session, holding a tool built around the transactions
/// those filters matched, works out what the question asks about them and
/// writes the answer from the tool's figures.
@MainActor
@Observable
final class TransactionAnswerer {
    enum Phase {
        case idle
        case answering
        case answered(TransactionAnswer)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    let store: TransactionStore

    /// The same parser the Query tab runs, so a question is read the same way
    /// on both tabs.
    private let parser = QueryParser()

    /// The same permissive guardrails as the parse: the input is the person's
    /// own question about their own spending.
    private let model = SystemLanguageModel(
        useCase: .general,
        guardrails: .permissiveContentTransformations
    )

    /// The answer in flight, kept so clearing the search bar can drop it.
    private var activeRun: Task<Void, Never>?

    init(store: TransactionStore = .bundled) {
        self.store = store
    }

    var availability: SystemLanguageModel.Availability { model.availability }

    var modelName: String { model.variant.displayName }

    /// Today, as far as this tab is concerned: the real date, as on the Query
    /// tab, so a question is read against the same day on both tabs.
    var reference: DateReference { DateReference() }

    /// Warms the parse sessions. The answer session can't be warmed ahead of
    /// time — its tool is built around the transactions a question matches.
    func prewarm() {
        parser.prewarm()
    }

    func ask(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            reset()
            return
        }
        activeRun?.cancel()
        phase = .answering
        activeRun = Task { await run(question) }
    }

    func reset() {
        activeRun?.cancel()
        activeRun = nil
        phase = .idle
        prewarm()
    }

    private func run(_ question: String) async {
        defer { prewarm() }
        do {
            let answer = try await answer(question)
            guard !Task.isCancelled else { return }
            phase = .answered(answer)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Runs one question end to end without touching `phase` — the path both
    /// the view and the accuracy tests take.
    func answer(_ question: String) async throws -> TransactionAnswer {
        let reference = reference
        let (parsed, parseMetrics) = try await parser.parsedQuery(
            for: question,
            reference: reference,
            resolve: { [store, model] question, about, candidates in
                try await Self.resolve(question, about: about, among: candidates, store: store, model: model)
            }
        )
        let scope = TransactionScope(parsed)
        let matches = store.matching(scope)
        let filters = scope.summary

        let session = LanguageModelSession(profile: AnswerProfile(
            model: model,
            instructions: Self.instructions,
            tool: LookUpTransactionsTool(transactions: matches, filters: filters, fixedGroupings: scope.fixedGroupings)
        ))

        let clock = ContinuousClock()
        let start = clock.now
        let response = try await session.respond(to: Self.prompt(question: question, filters: filters))
        let latency = clock.now - start
        let usage = response.usage

        // Comparing months under dates that cover one: the parse's dates and
        // the answer's grouping can't both be right. Dates every reading
        // agreed on win — the grouping was a stray, and the tool already
        // answered without it. Dates the readings split over don't, and
        // neither is shown.
        if Self.groupedByMonth(response.transcriptEntries), scope.fixedGroupings.contains(.month),
           parseMetrics.dateTrace?.confidence != .unanimous {
            let (from, to) = (scope.fromDate ?? "", scope.toDate ?? "")
            throw AnswerDeclined(
                reason: "the question compares months, but its dates were read as a single month",
                trace: "dates \(from) to \(to); lookUpTransactions grouped by month"
            )
        }

        return TransactionAnswer(
            question: question,
            parsed: parsed,
            parseMetrics: parseMetrics,
            scope: scope,
            matches: matches,
            text: response.content.trimmingCharacters(in: .whitespacesAndNewlines),
            toolCalls: ToolCallRecord.records(in: response.transcriptEntries),
            latency: latency,
            inputTokens: usage.input.totalTokenCount,
            cachedInputTokens: usage.input.cachedTokenCount,
            outputTokens: usage.output.totalTokenCount
        )
    }

    /// Reason over what each reading would search: the arbiter sees the
    /// question and, for each reading, how many transactions it leaves and
    /// which merchants they're at — and picks one, by label, asked in both
    /// orders. A pick that changes with the order declines.
    ///
    /// Shown only the question and the two names, the arbiter took the name
    /// — "Pharmacy" for "Pharmacy spending" — two times in five; shown what
    /// each reading would search, it settled all five.
    private nonisolated static func resolve(
        _ question: String,
        about: QueryParser.Disagreement,
        among candidates: [ParsedQuery],
        store: TransactionStore,
        model: SystemLanguageModel
    ) async throws -> Int? {
        let labels = candidates.map { candidate in
            switch about {
            case .merchant:
                candidate.filters.merchantName.map { "merchant: \($0)" } ?? "no merchant"
            case .categories:
                candidate.categories.isEmpty
                    ? "no category"
                    : "categories: " + candidate.categories.map(\.title).joined(separator: ", ")
            }
        }
        let lines = zip(labels, candidates).map { label, candidate in
            let scope = TransactionScope(candidate)
            let matches = store.matching(scope)
            let merchants = TransactionStore.breakdown(matches, by: .merchant)
                .prefix(5)
                .map { "\($0.name) \($0.count)" }
                .joined(separator: ", ")
            return "- \(label): \(scope.summary) → \(matches.count) transactions" + (merchants.isEmpty ? "" : " (\(merchants))")
        }
        let arbiter = LabelledChoice(model: model, instructions: arbiterInstructions(about))
        async let forward = arbiter.pick(among: labels, prompt: "Question: \(question)\nReadings:\n" + lines.joined(separator: "\n"))
        async let backward = arbiter.pick(
            among: labels.reversed(),
            prompt: "Question: \(question)\nReadings:\n" + lines.reversed().joined(separator: "\n")
        )
        let picks = try await [forward, backward]
        guard picks[0] == picks[1] else { return nil }
        return labels.firstIndex(of: picks[0])
    }

    private nonisolated static func arbiterInstructions(_ about: QueryParser.Disagreement) -> String {
        let subject = switch about {
        case .merchant: "whether it names a merchant"
        case .categories: "which kinds of spending it names"
        }
        return """
            Two readings of a question about the user's own card spending disagree on \(subject). \
            Each reading shows the transactions it would search and the merchants they are at. \
            Pick the reading whose transactions are the ones the question asks about.
            """
    }

    /// Whether any lookup in the turn asked for groups by month.
    private static func groupedByMonth(_ entries: some Collection<Transcript.Entry>) -> Bool {
        for case .toolCalls(let calls) in entries {
            for call in calls where (try? call.arguments.value(String?.self, forProperty: "groupBy")) == "month" {
                return true
            }
        }
        return false
    }

    private static func prompt(question: String, filters: String) -> String {
        """
        Question: \(question)
        Filters already applied: \(filters)
        """
    }

    private static let instructions = """
        You answer a person's questions about their own credit card transactions.

        The question's filters are already applied. Call lookUpTransactions to read the \
        matching transactions, then write the answer from the data it returns. Never add up, \
        filter, or work out anything yourself — every figure in your answer comes from that data.

        How to answer:
        - Start with the figure the question asks for: totalSpent for how much, \
        matchingTransactionCount for how many, averagePerTransaction for an average, or one \
        transaction's amount and date for the biggest, smallest, first, or last.
        - Which or where: name the first entry in groupTotals and its totalSpent — a group, \
        never a single transaction.
        - Show, list, or what was bought: add one line per transaction in listedTransactions, \
        each with its date, merchant, and amount.
        - When matchingTransactionCount is 0, say that no transactions matched.
        - When the data comes with a note, read it before answering; it may say to call again.

        Write amounts with a dollar sign and cents, and dates as the month name, day, and year.
        """
}

/// The answer session's setup: one tool, called once — or twice, when the
/// first answer came with a note.
///
/// The second call is required, not left to the model: offered the choice,
/// it answered "where do I spend the most on groceries" from the note-bearing
/// figures without regrouping. The note comes with the full figures, so a
/// stray grouping on a count question costs a call, not the answer.
///
/// Left to choose, the model sometimes skipped the tool and invented figures —
/// mostly on yes-or-no questions. A plain `.required` tool-calling mode fixes
/// that but holds for every step of the turn, so the model called the tool
/// again and again until the context window overflowed. This profile requires
/// the first call, and a second one when the first output carried a note,
/// then turns tool calling off so the next step is the answer.
struct AnswerProfile: LanguageModelSession.DynamicProfile {
    @SessionProperty(\.history) var history

    let model: SystemLanguageModel
    let instructions: String
    let tool: LookUpTransactionsTool

    /// Every lookup the tool has handed back so far.
    private var lookups: [TransactionLookup] {
        var lookups: [TransactionLookup] = []
        for case .toolOutput(let output) in history {
            for case .structure(let segment) in output.segments {
                if let lookup = try? TransactionLookup(segment.content) { lookups.append(lookup) }
            }
        }
        return lookups
    }

    private var mode: GenerationOptions.ToolCallingMode {
        let lookups = lookups
        if lookups.isEmpty { return .required }
        if lookups.count == 1, lookups[0].note != nil { return .required }
        return .disallowed
    }

    var body: some DynamicProfile {
        LanguageModelSession.Profile {
            Instructions(instructions)
            tool
        }
        .model(model)
        // Greedy sampling keeps repeated runs of the same question comparable.
        .samplingMode(.greedy)
        .toolCallingMode(mode)
    }
}

/// Everything one question produced, for the result screen and the tests.
struct TransactionAnswer {
    var question: String
    var parsed: ParsedQuery
    var parseMetrics: QueryParser.Metrics
    /// The filters the parse put on the statement.
    var scope: TransactionScope
    /// The transactions those filters matched — the only ones the tools saw.
    var matches: [Transaction]
    /// The model's answer, as shown on screen.
    var text: String
    var toolCalls: [ToolCallRecord]
    /// The answer session's own wall time, after the parse.
    var latency: Duration
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
}

/// One tool call as the transcript recorded it: what the model asked for and
/// what came back.
struct ToolCallRecord: Identifiable, Equatable {
    var id: String
    var toolName: String
    /// The arguments as JSON — `{}` for a tool that takes none.
    var arguments: String
    var output: String

    static func records(in entries: some Collection<Transcript.Entry>) -> [ToolCallRecord] {
        var outputs: [String: String] = [:]
        for case .toolOutput(let output) in entries {
            outputs[output.id] = output.segments.map { segment in
                switch segment {
                case .text(let text): text.content
                case .structure(let structure): structure.content.jsonString
                default: ""
                }
            }.joined(separator: "\n")
        }
        var records: [ToolCallRecord] = []
        for case .toolCalls(let calls) in entries {
            for call in calls {
                records.append(ToolCallRecord(
                    id: call.id,
                    toolName: call.toolName,
                    arguments: call.arguments.jsonString,
                    output: outputs[call.id] ?? ""
                ))
            }
        }
        return records
    }
}
