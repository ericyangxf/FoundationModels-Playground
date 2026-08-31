import FoundationModels
import SwiftUI

/// Shows which search system a question would be handed to.
struct RouteView: View {
    @State private var router = QueryRouter()
    @State private var text = ""

    /// Deliberately mixed, so the two routes are one tap apart.
    private static let examples = [
        "Check credit score",
        "How much I spent on Starbucks this month?",
        "What is the interest rate on a TFSA?",
        "Show Uber rides under $25 last week",
        "How do I dispute a charge?"
    ]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Route")
                .onChange(of: text) { _, query in
                    // Covers the clear "x", which empties the field on its way out.
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        router.reset()
                    }
                }
        }
        .task { router.prewarm() }
    }

    @ViewBuilder
    private var content: some View {
        switch router.availability {
        case .available:
            results
        case .unavailable(let reason):
            UnavailableView(reason: reason)
        }
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch router.phase {
                case .idle:
                    RouteLegend()
                    ExampleList(examples: Self.examples, onPick: route)
                case .routing:
                    ProgressView("Routing…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                case .routed(let decision, let metrics):
                    RouteCard(decision: decision)
                    MetricsCard(
                        title: "Routing run",
                        latency: metrics.latencyDescription,
                        inputTokens: metrics.inputTokens,
                        cachedInputTokens: metrics.cachedInputTokens,
                        outputTokens: metrics.outputTokens
                    )
                case .failed(let message):
                    MessageCard(
                        icon: "exclamationmark.triangle",
                        tint: .orange,
                        title: "Couldn't route that",
                        message: message
                    )
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            QuerySearchField(
                prompt: "Ask anything",
                text: $text,
                onSubmit: route
            )
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func route(_ query: String) {
        text = query
        router.route(query)
    }
}

// MARK: - Result

/// The chosen route, big enough to read at a glance, with the model's reason
/// underneath it.
private struct RouteCard: View {
    let decision: RouteDecision

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(decision.route.title)
                    .font(.title2.weight(.semibold))
            } icon: {
                Image(systemName: decision.route.symbolName)
                    .font(.title2)
            }
            .foregroundStyle(decision.route.tint)

            Text(decision.reason)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(decision.route.tint.opacity(0.12), in: .rect(cornerRadius: 16))
    }
}

/// What the two routes are, for a page that hasn't been asked anything yet.
private struct RouteLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Every question goes one of two ways")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(SearchRoute.allCases, id: \.self) { route in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: route.symbolName)
                        .foregroundStyle(route.tint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(route.title).font(.subheadline.weight(.medium))
                        Text(route.blurb).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: .rect(cornerRadius: 16))
    }
}

private extension SearchRoute {
    /// Colour is what tells the two apart before the label is read.
    var tint: Color {
        switch self {
        case .transactionSearch: .green
        case .coveoSearch: .indigo
        }
    }
}

#Preview {
    RouteView()
}
