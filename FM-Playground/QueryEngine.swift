/// The two ways this app turns a question into filters.
///
/// Foundation Models leads: a chain of model sessions reads the dates out of the
/// question and calls date tools that do the calendar arithmetic for it.
/// SwiftyChronoX comes second, doing the date reading and arithmetic itself.
/// Either way the merchant, category, and amount come from the model.
enum QueryEngine: String, CaseIterable, Identifiable, Sendable {
    case foundationModels
    case swiftyChronoX

    var id: String { rawValue }

    /// The label on the tab bar.
    var title: String {
        switch self {
        case .swiftyChronoX: "SwiftyChronoX"
        case .foundationModels: "Foundation Models"
        }
    }
}
