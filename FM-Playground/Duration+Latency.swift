import Foundation

extension Duration {
    /// A round trip's wall time, in whichever unit reads best at that scale.
    var latencyDescription: String {
        let parts = components
        let milliseconds = Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
        // Under a millisecond the whole number would read as "0 ms", which is
        // the one case where the fraction is the interesting part.
        if milliseconds < 1 { return String(format: "%.2f ms", milliseconds) }
        return milliseconds < 1000
            ? String(format: "%.0f ms", milliseconds)
            : String(format: "%.2f s", milliseconds / 1000)
    }
}
