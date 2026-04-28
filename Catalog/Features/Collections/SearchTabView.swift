import SwiftUI

struct SearchTabView: View {
    let repository: any CatalogRepository
    @State private var layoutMode: BellGridLayoutMode = .mini
    @State private var orderMode: BellOrderMode = .newestFirst
    @State private var filters = BellFilters()

    var body: some View {
        NavigationStack {
            BellCatalogView(
                collection: nil,
                repository: repository,
                collaborators: [],
                layoutMode: $layoutMode,
                orderMode: $orderMode,
                filters: $filters
            )
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
