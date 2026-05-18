import SwiftUI
import SwiftData

enum SearchToken: Identifiable, Hashable {
    case collection(UUID)
    case country(String)
    case material(String)
    case tag(String)
    case condition(ItemCondition)
    case acquisitionMethod(AcquisitionMethod)

    var id: String {
        switch self {
        case .collection(let collectionID):
            return "collection:\(collectionID.uuidString)"
        case .country(let country):
            return "country:\(country)"
        case .material(let material):
            return "material:\(material)"
        case .tag(let tag):
            return "tag:\(tag)"
        case .condition(let condition):
            return "condition:\(condition.rawValue)"
        case .acquisitionMethod(let method):
            return "acquisition:\(method.rawValue)"
        }
    }
}

struct BellCatalogSearchState: Equatable {
    enum Scope: String, CaseIterable, Identifiable {
        case all
        case title
        case collection
        case origin
        case tags
        case notes
        case incomplete

        var id: String { rawValue }
    }

    var query = ""
    var scope: Scope = .all
    var tokens: [SearchToken] = []
}

struct SearchTabView: View {
    let repository: any CatalogRepository
    let onBellSelected: ((BellEntity) -> Void)?
    @Binding var layoutMode: BellGridLayoutMode
    @Query(sort: \CollectionEntity.title) private var collections: [CollectionEntity]
    @Query(sort: \BellEntity.title) private var bells: [BellEntity]
    @State private var selectedBell: BellEntity?
    @State private var searchState = BellCatalogSearchState()
    @FocusState private var isSearchFocused: Bool

    init(
        repository: any CatalogRepository,
        layoutMode: Binding<BellGridLayoutMode>,
        onBellSelected: ((BellEntity) -> Void)? = nil
    ) {
        self.repository = repository
        self._layoutMode = layoutMode
        self.onBellSelected = onBellSelected
    }

    private var suggestedTokenGroups: [SearchTokenGroup] {
        let selectedTokens = Set(searchState.tokens)

        return [
            SearchTokenGroup(
                title: String(localized: "root_tab.collections"),
                systemImage: "rectangle.stack",
                tokens: collections.map { SearchToken.collection($0.id) }
            ),
            SearchTokenGroup(
                title: String(localized: "bell_catalog.summary.countries"),
                systemImage: "globe.europe.africa",
                tokens: uniqueValues(bells.map(\.countryName)).map(SearchToken.country)
            ),
            SearchTokenGroup(
                title: String(localized: "bell_catalog.summary.materials"),
                systemImage: "shippingbox",
                tokens: uniqueValues(bells.map(\.materialDisplayName)).map(SearchToken.material)
            ),
            SearchTokenGroup(
                title: String(localized: "bell_catalog.summary.tags"),
                systemImage: "tag",
                tokens: uniqueValues(bells.flatMap(\.tagValues)).map(SearchToken.tag)
            ),
            SearchTokenGroup(
                title: String(localized: "common.field.condition"),
                systemImage: "checkmark.seal",
                tokens: uniqueConditions.map(SearchToken.condition)
            ),
            SearchTokenGroup(
                title: String(localized: "editor.acquisition"),
                systemImage: "tray.and.arrow.down",
                tokens: uniqueAcquisitionMethods.map(SearchToken.acquisitionMethod)
            )
        ]
        .map { group in
            SearchTokenGroup(
                title: group.title,
                systemImage: group.systemImage,
                tokens: group.tokens.filter { !selectedTokens.contains($0) }
            )
        }
        .filter { !$0.tokens.isEmpty }
    }

    private var filteredBells: [BellEntity] {
        bells
            .filter { matches(bell: $0, searchState: searchState) }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }

                return $0.createdAt > $1.createdAt
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchTokenBar(
                tokens: searchState.tokens,
                suggestedTokenGroups: suggestedTokenGroups,
                title: searchTokenTitle,
                select: selectToken,
                remove: removeToken
            )
            .background(.thinMaterial)

            BellGridContainerView(layoutMode: layoutMode) { cardSize, gridMetrics, cardMetrics in
                if filteredBells.isEmpty {
                    ContentUnavailableView.search
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    BellGridView(
                        bells: filteredBells,
                        layoutMode: layoutMode,
                        cardSize: cardSize,
                        gridMetrics: gridMetrics,
                        cardMetrics: cardMetrics,
                        selectedBellIDs: [],
                        isSelectionModeEnabled: false,
                        onTap: openBell,
                        onSelect: nil,
                        contextMenu: { _ in
                            EmptyView()
                        },
                        preview: { bell in
                            SearchBellCardPreview(bell: bell, repository: repository)
                        }
                    )
                }
            }
        }
        .searchable(
            text: $searchState.query,
            tokens: $searchState.tokens
        ) { token in
            Label(searchTokenTitle(token), systemImage: searchTokenSystemImage(token))
        }
        .searchFocused($isSearchFocused)
        .onAppear {
            isSearchFocused = true
        }
        .sheet(item: $selectedBell) { bell in
            BellEntityDetailSheetContainer(bell: bell, repository: repository)
                .presentationDragIndicator(.visible)
        }
    }

    private func openBell(_ bell: BellEntity) {
        if let onBellSelected {
            onBellSelected(bell)
        } else {
            selectedBell = bell
        }
    }

    private func searchTokenTitle(_ token: SearchToken) -> String {
        switch token {
        case .collection(let collectionID):
            return collections.first(where: { $0.id == collectionID })?.title
                ?? String(localized: "search.scope.collection")
        case .country(let value), .material(let value), .tag(let value):
            return value
        case .condition(let condition):
            return condition.displayName
        case .acquisitionMethod(let method):
            return method.displayName
        }
    }

    private func searchTokenSystemImage(_ token: SearchToken) -> String {
        switch token {
        case .collection:
            return "rectangle.stack"
        case .country:
            return "globe.europe.africa"
        case .material:
            return "shippingbox"
        case .tag:
            return "tag"
        case .condition:
            return "checkmark.seal"
        case .acquisitionMethod:
            return "tray.and.arrow.down"
        }
    }

    private func selectToken(_ token: SearchToken) {
        guard !searchState.tokens.contains(token) else { return }
        searchState.tokens.append(token)
    }

    private func removeToken(_ token: SearchToken) {
        searchState.tokens.removeAll { $0 == token }
    }

    private func uniqueValues(_ values: [String]) -> [String] {
        let trimmedValues = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen: Set<String> = []

        return trimmedValues
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var uniqueConditions: [ItemCondition] {
        ItemCondition.allCases.filter { condition in
            bells.contains { $0.condition == condition }
        }
    }

    private var uniqueAcquisitionMethods: [AcquisitionMethod] {
        AcquisitionMethod.allCases.filter { method in
            bells.contains { $0.acquisitionMethod == method }
        }
    }

    private func matches(bell: BellEntity, searchState: BellCatalogSearchState) -> Bool {
        matchesQuery(searchState.query, in: bell, scope: searchState.scope)
        && searchState.tokens.allSatisfy { matches(token: $0, in: bell) }
    }

    private func matchesQuery(
        _ query: String,
        in bell: BellEntity,
        scope: BellCatalogSearchState.Scope
    ) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return matchesScope(scope, in: bell) }

        switch scope {
        case .all:
            return searchableValues(for: bell).contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
        case .title:
            return bell.title.localizedCaseInsensitiveContains(trimmedQuery)
        case .collection:
            return bell.collection?.title.localizedCaseInsensitiveContains(trimmedQuery) == true
        case .origin:
            return originValues(for: bell).contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
        case .tags:
            return bell.tagValues.contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
        case .notes:
            return bell.notes.localizedCaseInsensitiveContains(trimmedQuery)
        case .incomplete:
            return matchesScope(.incomplete, in: bell)
            && searchableValues(for: bell).contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
        }
    }

    private func matchesScope(_ scope: BellCatalogSearchState.Scope, in bell: BellEntity) -> Bool {
        switch scope {
        case .all, .title, .collection, .origin, .tags, .notes:
            return true
        case .incomplete:
            return bell.originPlace == nil
            || bell.acquiredYear == nil
            || bell.location == nil
            || !bell.hasNotes
            || bell.tagValues.isEmpty
        }
    }

    private func matches(token: SearchToken, in bell: BellEntity) -> Bool {
        switch token {
        case .collection(let collectionID):
            return bell.collection?.id == collectionID
        case .country(let country):
            return bell.countryName.localizedCaseInsensitiveCompare(country) == .orderedSame
        case .material(let material):
            return bell.materialDisplayName.localizedCaseInsensitiveCompare(material) == .orderedSame
        case .tag(let tag):
            return bell.tagValues.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
        case .condition(let condition):
            return bell.condition == condition
        case .acquisitionMethod(let method):
            return bell.acquisitionMethod == method
        }
    }

    private func searchableValues(for bell: BellEntity) -> [String] {
        [
            bell.title,
            bell.notes,
            bell.materialDisplayName,
            bell.collection?.title ?? ""
        ] + originValues(for: bell) + storageValues(for: bell) + bell.tagValues
    }

    private func originValues(for bell: BellEntity) -> [String] {
        [
            bell.countryName,
            bell.cityName,
            bell.originPlace?.displayName ?? "",
            bell.originPlace?.regionName ?? ""
        ]
    }

    private func storageValues(for bell: BellEntity) -> [String] {
        [
            bell.storageDisplayPath,
            bell.location?.name ?? "",
            bell.location?.home?.name ?? ""
        ]
    }
}

private extension BellEntity {
    var hasNotes: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct SearchBellCardPreview: View {
    @State private var bell: BellRecord
    let repository: any CatalogRepository

    init(bell: BellEntity, repository: any CatalogRepository) {
        _bell = State(initialValue: bell.recordSnapshot)
        self.repository = repository
    }

    var body: some View {
        NavigationStack {
            BellDetailView(bell: $bell, repository: repository)
        }
        .allowsHitTesting(false)
    }
}

private struct SearchTokenGroup: Identifiable {
    let title: String
    let systemImage: String
    let tokens: [SearchToken]

    var id: String { title }
}

private struct SearchTokenBar: View {
    let tokens: [SearchToken]
    let suggestedTokenGroups: [SearchTokenGroup]
    let title: (SearchToken) -> String
    let select: (SearchToken) -> Void
    let remove: (SearchToken) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if tokens.isEmpty && suggestedTokenGroups.isEmpty {
                    Text("Нет поисковых токенов")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tokens) { token in
                        Button {
                            remove(token)
                        } label: {
                            Label(title(token), systemImage: "xmark")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }
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
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
