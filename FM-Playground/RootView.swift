import SwiftUI

/// The app's three pages, on the system tab bar.
///
/// Route decides which search system a question belongs to, Query is what the
/// transaction one turns it into, and Transactions runs those filters against
/// a statement and answers the question with tool calling.
struct RootView: View {
    var body: some View {
        TabView {
            Tab("Query", systemImage: "magnifyingglass") {
                QueryView()
            }
            Tab("Route", systemImage: "arrow.triangle.branch") {
                RouteView()
            }
            Tab("Transactions", systemImage: "creditcard") {
                TransactionsView()
            }
        }
    }
}

#Preview {
    RootView()
}
