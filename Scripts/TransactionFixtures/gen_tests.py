"""Writes FM-PlaygroundTests/TransactionAnswerTests.swift from cases.py and the
oracle's figures.

Usage, from the repo root:
  python3 -I Scripts/TransactionFixtures/generate.py FM-Playground/transactions.json
  python3 -I Scripts/TransactionFixtures/gen_tests.py FM-Playground/transactions.json \
      FM-PlaygroundTests/TransactionAnswerTests.swift
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cases import CASES  # noqa: E402
import oracle  # noqa: E402

SECTIONS = {
    "uberPastSixMonths": "How much at a merchant",
    "timHortonsVisitsPastThreeMonths": "How many",
    "groceriesLastMonth": "How much on a kind of spending",
    "everyPurchaseOverFiveHundred": "Amount filters",
    "biggestPurchaseLastMonth": "Biggest and smallest",
    "averageUberRide": "Averages",
    "lastCostcoTrip": "When",
    "lastThreeUberRides": "Show me",
    "topCity": "Where and which",
    "walmartLastWeek": "Nothing there",
}


def dollars(cents):
    return f"{cents // 100}.{cents % 100:02d}"


def swift_string(text):
    return json.dumps(text, ensure_ascii=False)


def scope_literal(scope):
    parts = []
    if scope["merchant"]:
        parts.append(f"merchant: {swift_string(scope['merchant'])}")
    if scope["categories"] and not scope["merchant"]:
        parts.append("categories: [" + ", ".join("." + c for c in scope["categories"]) + "]")
    if scope["min"] is not None:
        parts.append(f"minimum: {scope['min']}")
    if scope["max"] is not None:
        parts.append(f"maximum: {scope['max']}")
    if scope["dates"]:
        parts.append(f"dates: (\"{scope['dates'][0]}\", \"{scope['dates'][1]}\")")
    return ".init(" + ", ".join(parts) + ")" if parts else ".everything"


def keyword(group, by):
    if by == "city":
        return group.split(",")[0]
    if by == "month":
        return group.split(" ")[0]
    if by == "category":
        word = group.split(" ")[0].rstrip(",")
        return {"Groceries": "Grocer", "Hotels": "Hotel", "Restaurants": "Restaurant",
                "Electronics": "Electronic"}.get(word, word)
    return group


def answer_literal(check, result):
    kind = check[0]
    if kind == "total":
        return f".amount({dollars(result['amount'])})"
    if kind == "average":
        return f".average({dollars(result['amount'])})"
    if kind == "count":
        return f".count({result['count']})"
    if kind in ("largest", "smallest"):
        return f".transaction({swift_string(result['merchant'])}, {dollars(result['amount'])})"
    if kind in ("latest", "earliest"):
        return f".date(\"{result['date']}\")"
    if kind == "latestAmount":
        return f".dateAndAmount(\"{result['date']}\", {dollars(result['amount'])})"
    if kind == "list":
        return ".amounts([" + ", ".join(dollars(a) for a in result["amounts"]) + "])"
    if kind == "listDates":
        return ".dates([" + ", ".join(f"\"{d}\"" for d in result["dates"]) + "])"
    if kind == "group":
        return f".group({swift_string(keyword(result['group'], check[1]))}, {dollars(result['amount'])})"
    if kind == "nothing":
        return ".nothing"
    raise ValueError(kind)


HEADER = '''import Foundation
import FoundationModels
import Testing

@testable import FM_Playground

/// Scores the Transactions tab end to end on one hundred questions, typed the
/// way a bank client types them — casual, sometimes ungrammatical, sometimes
/// slangy — about the bundled statement.
///
/// Each test runs the same path the tab does: the Query tab's parse turns the
/// question into filters (the date reasoning chain for the dates, the model
/// for the rest), then a tool-calling session answers from the transactions those
/// filters matched. Each one writes out what a correct run looks like:
///
/// - `expecting`: the filters the question really asks for, worked out by hand
///   rather than by any code under test.
/// - `matches`: how many of the 200 transactions those filters leave.
/// - `answer`: the figure the answer has to state, computed from the JSON by
///   an independent script when the data was generated
///   (Scripts/TransactionFixtures/oracle.py — this file is its output).
///
/// `ask` then scores the run in layers, so a red test says whose fault it is:
///
/// 1. The parse has to land on the same transactions. When only the dates
///    differ, the failure names the date chain's reading and its trace; any
///    other difference is the merchant, amount, or category parse.
/// 2. The answer session has to call a tool — an answer written without
///    reading the statement is a guess, however lucky.
/// 3. The answer text has to state the expected figure. Numbers are matched
///    by value, so "$1,486.20" and "1486.2 dollars" both count; dates in any
///    common spelling; counts as digits or words.
///
/// The statement date is fixed at 2026-10-06, so the expected answers hold no
/// matter what day the suite runs.
@MainActor
@Suite(.serialized, .enabled(if: foundationModelIsAvailable()))
struct TransactionAnswerTests {
'''


def main():
    data, results, problems = oracle.main()
    assert not problems, problems
    out = [HEADER]
    first = True
    for name, question, scope, check, hits, result in results:
        if name in SECTIONS:
            out.append(("" if first else "\n") + f"    // MARK: - {SECTIONS[name]}\n")
            first = False
        out.append(f'''
    @Test({swift_string(question)})
    func {name}() async throws {{
        try await ask(
            {swift_string(question)},
            expecting: {scope_literal(scope)},
            matches: {len(hits)},
            answer: {answer_literal(check, result)}
        )
    }}
''')
    out.append("}\n")
    with open(sys.argv[2], "w") as f:
        f.write("".join(out))
    print(f"wrote {len(results)} tests to {sys.argv[2]}")


if __name__ == "__main__":
    main()
