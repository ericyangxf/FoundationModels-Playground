/// The two ways this app turns a question into filters.
///
/// SwiftyChronoX leads because it does the calendar arithmetic itself and hands
/// the model only the part it is reliably good at. The model on its own can
/// match a date phrase against ranges we resolve for it up front — ask it for
/// "the past 40 days" and it picks the closest thing on that list — so it comes
/// second.
enum QueryEngine: String, CaseIterable, Identifiable, Sendable {
    case swiftyChronoX
    case foundationModels

    var id: String { rawValue }

    /// The label on the tab bar.
    var title: String {
        switch self {
        case .swiftyChronoX: "SwiftyChronoX"
        case .foundationModels: "Foundation Models"
        }
    }

    /// The heading over the run's numbers.
    var runDescription: String {
        switch self {
        case .swiftyChronoX: "SwiftyChronoX run"
        case .foundationModels: "Foundation Models run"
        }
    }
}
