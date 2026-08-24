import SwiftUI

private struct BookSearchToken: Identifiable, Hashable {
    let id: String
}

struct BookSearchView: View {
    @Binding var layoutMode: CatalogCardLayoutMode
    @State private var query = ""
    @State private var tokens: [BookSearchToken] = []

    private let initialQuery: String?

    init(
        layoutMode: Binding<CatalogCardLayoutMode>,
        initialQuery: String? = nil
    ) {
        self._layoutMode = layoutMode
        self.initialQuery = initialQuery
    }

    var body: some View {
        SearchShellView(
            layoutMode: $layoutMode,
            query: $query,
            tokens: $tokens,
            suggestedTokenGroups: [],
            initialQuery: initialQuery,
            tokenTitle: { _ in "" },
            tokenSystemImage: { _ in "magnifyingglass" }
        ) { _ in
            CatalogEmptyStateView(
                systemImage: "magnifyingglass",
                title: "Search",
                message: "Book search is not available yet."
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
}

@MainActor
func makeSearchTabContent(
    repository: any CatalogRepository,
    layoutMode: Binding<CatalogCardLayoutMode>,
    catalogSnapshot: CatalogSnapshot?,
    initialQuery: String?,
    onItemSelected: ((UUID) -> Void)?
) -> AnyView {
    AnyView(
        BookSearchView(
            layoutMode: layoutMode,
            initialQuery: initialQuery
        )
    )
}
