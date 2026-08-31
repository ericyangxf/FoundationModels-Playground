/// The two ways this app turns a question into filters.
///
/// The on-device model is the interesting one, but it can only match a date
/// phrase against ranges we resolve for it up front — ask it for "the past 40
/// days" and it picks the closest thing on that list. SwiftyChronoX does the
/// arithmetic itself, so the second engine hands it the dates and leaves the
/// model the part it is reliably good at.
enum QueryEngine: String, CaseIterable, Identifiable, Sendable {
    case foundationModels
    case swiftyChronoX

    var id: String { rawValue }

    /// The label on the tab bar.
    var title: String {
        switch self {
        case .foundationModels: "Foundation Models"
        case .swiftyChronoX: "SwiftyChronoX"
        }
    }

    /// The heading over the run's numbers.
    var runDescription: String {
        switch self {
        case .foundationModels: "Foundation Models run"
        case .swiftyChronoX: "SwiftyChronoX run"
        }
    }
}
