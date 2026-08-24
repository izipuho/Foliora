import SwiftUI

/// Displays a domain-neutral search tab shell.
struct SearchShellView<Token: Identifiable & Hashable, Content: View>: View {
    @Binding var layoutMode: CatalogCardLayoutMode
    @Binding var query: String
    @Binding var tokens: [Token]

    let suggestedTokenGroups: [SearchTokenGroup<Token>]
    let tokenTitle: (Token) -> String
    let tokenSystemImage: (Token) -> String
    let content: (CatalogCardGrid<AnyView>.LayoutMetrics) -> Content

    private let initialQuery: String?
    @State private var didApplyInitialQuery = false
    @FocusState private var isSearchFocused: Bool

    init(
        layoutMode: Binding<CatalogCardLayoutMode>,
        query: Binding<String>,
        tokens: Binding<[Token]>,
        suggestedTokenGroups: [SearchTokenGroup<Token>],
        initialQuery: String? = nil,
        tokenTitle: @escaping (Token) -> String,
        tokenSystemImage: @escaping (Token) -> String,
        @ViewBuilder content: @escaping (CatalogCardGrid<AnyView>.LayoutMetrics) -> Content
    ) {
        self._layoutMode = layoutMode
        self._query = query
        self._tokens = tokens
        self.suggestedTokenGroups = suggestedTokenGroups
        self.initialQuery = initialQuery
        self.tokenTitle = tokenTitle
        self.tokenSystemImage = tokenSystemImage
        self.content = content
    }

    var body: some View {
        CatalogCardGrid(layoutMode: layoutMode, usesGridLayout: false) { cardSize, gridMetrics, cardMetrics in
            LazyVStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xl) {
                searchHeader

                content((cardSize, gridMetrics, cardMetrics))
            }
            .padding(.top, CatalogMetrics.Spacing.xl)
        }
        .searchable(
            text: $query,
            tokens: $tokens
        ) { token in
            Label(tokenTitle(token), systemImage: tokenSystemImage(token))
        }
        .searchFocused($isSearchFocused)
        .onAppear {
            applyInitialQueryIfNeeded()
            isSearchFocused = true
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            Text("common.ui.search")
                .font(CatalogTypography.screenTitle)
                .foregroundStyle(.primary)
                .padding(.horizontal, CatalogMetrics.Insets.screen)

            SearchTokenBar(
                tokens: tokens,
                suggestedTokenGroups: suggestedTokenGroups,
                title: tokenTitle,
                select: selectToken,
                remove: removeToken
            )
            .ignoresSafeArea(.container, edges: .horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applyInitialQueryIfNeeded() {
        guard !didApplyInitialQuery else { return }
        didApplyInitialQuery = true

        guard let initialQuery else { return }
        query = initialQuery
    }

    private func selectToken(_ token: Token) {
        guard !tokens.contains(token) else { return }
        tokens.append(token)
    }

    private func removeToken(_ token: Token) {
        tokens.removeAll { $0 == token }
    }
}

/// Displays the catalog search tab using the active domain search implementation.
struct SearchView: View {
    let repository: any CatalogRepository
    let catalogSnapshot: CatalogSnapshot?
    let onItemSelected: ((UUID) -> Void)?
    private let initialQuery: String?
    @Binding var layoutMode: CatalogCardLayoutMode

    init(
        repository: any CatalogRepository,
        layoutMode: Binding<CatalogCardLayoutMode>,
        catalogSnapshot: CatalogSnapshot?,
        initialQuery: String? = nil,
        onItemSelected: ((UUID) -> Void)? = nil
    ) {
        self.repository = repository
        self.catalogSnapshot = catalogSnapshot
        self._layoutMode = layoutMode
        self.initialQuery = initialQuery
        self.onItemSelected = onItemSelected
    }

    var body: some View {
        makeSearchTabContent(
            repository: repository,
            layoutMode: $layoutMode,
            catalogSnapshot: catalogSnapshot,
            initialQuery: initialQuery,
            onItemSelected: onItemSelected
        )
    }
}

struct SearchTokenGroup<Token: Identifiable>: Identifiable {
    let title: String
    let systemImage: String
    let tokens: [Token]

    var id: String { title }
}

private struct SearchTokenBar<Token: Identifiable>: View {
    let tokens: [Token]
    let suggestedTokenGroups: [SearchTokenGroup<Token>]
    let title: (Token) -> String
    let select: (Token) -> Void
    let remove: (Token) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CatalogMetrics.Spacing.sm) {
                ForEach(tokens) { token in
                    Button {
                        remove(token)
                    } label: {
                        HStack(spacing: CatalogMetrics.Spacing.xs) {
                            Text(title(token))

                            Image(systemName: "xmark")
                                .foregroundStyle(.secondary)
                        }
                        .font(CatalogTypography.cardSubtitle)
                        .catalogSurfaceCapsule()
                    }
                    .buttonStyle(.plain)
                }

                ForEach(suggestedTokenGroups) { group in
                    Menu {
                        ForEach(group.tokens) { token in
                            Button(title(token)) {
                                select(token)
                            }
                        }
                    } label: {
                        Label(group.title, systemImage: group.systemImage)
                            .font(CatalogTypography.cardSubtitle)
                            .catalogSurfaceCapsule()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, CatalogMetrics.Insets.screen)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
