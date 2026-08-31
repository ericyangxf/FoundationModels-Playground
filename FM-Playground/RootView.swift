import SwiftUI

/// The app's two pages, on the system tab bar.
///
/// They read left to right as the pipeline runs: Route decides which search
/// system a question belongs to, Query is what the transaction one does with it.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Query", systemImage: "magnifyingglass") {
                QueryView()
            }
            Tab("Route", systemImage: "arrow.triangle.branch") {
                RouteView()
            }
        }
    }
}

#Preview {
    RootView()
}
