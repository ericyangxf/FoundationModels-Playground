import Foundation
import FoundationModels

/// Answers a question about the bundled statement in one model session.
///
/// The model reads the question, thinks out what it asks for — the merchant,
/// the kinds of spending, the amounts, and the dates, which it works out from
/// today itself — and calls the search tool with those filters. The tool does
/// the filtering and the arithmetic; the model writes the answer from what
/// comes back.
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

    /// The question in flight as far as it has got — thinking, the tool call
    /// and what it returned, then the answer as it streams.
    private(set) var liveEntries: [Transcript.Entry] = []

    let store: TransactionStore

    /// The day questions are asked on, when it isn't today.
    private let fixedReference: DateReference?

    /// The answer in flight, kept so clearing the search bar can drop it.
    private var activeRun: Task<Void, Never>?

    /// - Parameter reference: The day to answer as of. Nil, as on the tab,
    ///   means the real date; the accuracy tests pin the statement date.
    init(store: TransactionStore = .bundled, reference: DateReference? = nil) {
        self.store = store
        self.fixedReference = reference
    }

    var reference: DateReference { fixedReference ?? DateReference() }

    func prewarm() {
        OnDeviceModel.shared.prewarm()
    }

    func ask(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            reset()
            return
        }
        activeRun?.cancel()
        liveEntries = []
        phase = .answering
        activeRun = Task { await run(question) }
    }

    func reset() {
        activeRun?.cancel()
        activeRun = nil
        liveEntries = []
        phase = .idle
    }

    private func run(_ question: String) async {
        do {
            let answer = try await answer(question) { entries in
                guard !Task.isCancelled else { return }
                self.liveEntries = entries
            }
            guard !Task.isCancelled else { return }
            phase = .answered(answer)
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Runs one question end to end without touching `phase` — the path both
    /// the view and the accuracy tests take.
    func answer(
        _ question: String,
        onUpdate: ([Transcript.Entry]) -> Void = { _ in }
    ) async throws -> TransactionAnswer {
        let session = LanguageModelSession(profile: AnswerProfile(
            model: OnDeviceModel.languageModel,
            instructions: Self.instructions(for: reference),
            tool: SearchTransactionsTool(store: store)
        ))

        let clock = ContinuousClock()
        let start = clock.now
        let stream = session.streamResponse(to: question)
        for try await snapshot in stream {
            onUpdate(Array(snapshot.transcriptEntries))
        }
        let response = try await stream.collect()
        let latency = clock.now - start

        let toolCalls = ToolCallRecord.records(in: response.transcriptEntries)
        // The filters the answer stands on are those of the last search.
        let scope = toolCalls.compactMap(\.searchScope).last
        return TransactionAnswer(
            question: question,
            scope: scope,
            matches: scope.map(store.matching) ?? [],
            text: response.content.trimmingCharacters(in: .whitespacesAndNewlines),
            toolCalls: toolCalls,
            run: ModelRun(latency: latency, usage: response.usage, entries: response.transcriptEntries)
        )
    }

    private static func instructions(for reference: DateReference) -> String {
        """
        You answer a person's questions about their own credit card statement.

        Read the statement with searchTransactions: call it once, with the filters the question \
        asks for, then answer from what it returns.

        \(FilterRules.text)
        - Group by a merchant, category, city, province or month when the question asks which \
        one comes out on top, or how much was spent in a named city or province.
        - List in an order when the question asks to see or list transactions, or for its \
        latest, earliest, biggest or smallest few.

        \(reference.promptRules)

        How to answer:
        - Every figure comes from the tool's results. Don't add up, count or work out amounts \
        yourself.
        - Start with what the question asks for: totalSpent for how much, \
        matchingTransactionCount for how many, averagePerTransaction for an average, one \
        transaction's merchant, amount and date for the biggest, smallest, first or last, or \
        the first group in groupTotals and its total for which one or where.
        - To show or list transactions, give one line per listed transaction with its date, \
        merchant and amount.
        - When matchingTransactionCount is 0, say that no transactions matched.
        - Write amounts with a dollar sign and cents, and dates as the month name, day and year.
        """
    }
}

/// The answer session's setup: one tool, called exactly once.
///
/// Tool calling is `.required` until the transcript holds a tool output, so
/// the answer always stands on the statement, then `.disallowed`, so the
/// next step is the answer rather than another search.
struct AnswerProfile: LanguageModelSession.DynamicProfile {
    @SessionProperty(\.history) var history

    let model: GemmaLanguageModel
    let instructions: String
    let tool: SearchTransactionsTool

    var body: some DynamicProfile {
        let hasSearched = history.contains { entry in
            if case .toolOutput = entry { true } else { false }
        }
        LanguageModelSession.Profile {
            Instructions(instructions)
            tool
        }
        .model(model)
        // Greedy decoding keeps repeated runs of the same question comparable.
        .samplingMode(.greedy)
        .toolCallingMode(hasSearched ? .disallowed : .required)
    }
}

/// Everything one question produced, for the result screen and the tests.
struct TransactionAnswer {
    var question: String
    /// The filters the model searched with. Nil when it never searched.
    var scope: TransactionScope?
    /// The transactions those filters matched — the ones the answer is about.
    var matches: [Transaction]
    /// The model's answer, as shown on screen.
    var text: String
    var toolCalls: [ToolCallRecord]
    var run: ModelRun
}

/// One tool call as the transcript recorded it: what the model asked for and
/// what came back.
struct ToolCallRecord: Identifiable, Equatable {
    var id: String
    var toolName: String
    /// The arguments as JSON — `{}` for a tool that takes none.
    var arguments: String
    var output: String
    /// The filters, for a call to the search tool whose arguments parse.
    var searchScope: TransactionScope?

    static func records(in entries: some Collection<Transcript.Entry>) -> [ToolCallRecord] {
        var outputs: [String: String] = [:]
        for case .toolOutput(let output) in entries {
            outputs[output.id] = Transcript.text(of: output.segments)
        }
        var records: [ToolCallRecord] = []
        for case .toolCalls(let calls) in entries {
            for call in calls {
                let search = call.toolName == SearchTransactionsTool.toolName
                    ? try? SearchTransactionsTool.Arguments(call.arguments)
                    : nil
                records.append(ToolCallRecord(
                    id: call.id,
                    toolName: call.toolName,
                    arguments: call.arguments.jsonString,
                    output: outputs[call.id] ?? "",
                    searchScope: search.map(TransactionScope.init)
                ))
            }
        }
        return records
    }
}
