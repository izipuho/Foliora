import SwiftUI

/// Groups search token values and behavior.
enum BellSearchToken: Identifiable, Hashable {
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

/// Represents bell catalog search state data and behavior.
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
    var tokens: [BellSearchToken] = []
}

/// Displays bell search content inside the shared search tab shell.
struct BellSearchView: View {
    let repository: any CatalogRepository
    let catalogSnapshot: CatalogSnapshot?
    let onBellSelected: ((UUID) -> Void)?
    private let initialQuery: String?
    @Binding var layoutMode: CatalogCardLayoutMode
    @State private var selectedBellID: UUID?
    @State private var searchState = BellCatalogSearchState()

    init(
        repository: any CatalogRepository,
        layoutMode: Binding<CatalogCardLayoutMode>,
        catalogSnapshot: CatalogSnapshot?,
        initialQuery: String? = nil,
        onBellSelected: ((UUID) -> Void)? = nil
    ) {
        self.repository = repository
        self.catalogSnapshot = catalogSnapshot
        self._layoutMode = layoutMode
        self.initialQuery = initialQuery
        self.onBellSelected = onBellSelected
    }

    private var bells: [BellListItem] {
        catalogSnapshot?.bells ?? []
    }

    private var collections: [Collection] {
        (catalogSnapshot?.collections ?? [])
            .sorted {
                let titleComparison = $0.title.localizedCaseInsensitiveCompare($1.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }

                return $0.id.uuidString < $1.id.uuidString
            }
    }

    private var collectionTitlesByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0.title) })
    }

    private var suggestedTokenGroups: [SearchTokenGroup<BellSearchToken>] {
        let selectedTokens = Set(searchState.tokens)

        return [
            SearchTokenGroup(
                title: String(localized: "root_tab.collections"),
                systemImage: "rectangle.stack",
                tokens: collections.map { BellSearchToken.collection($0.id) }
            ),
            SearchTokenGroup(
                title: String(localized: "bell_catalog.summary.countries"),
                systemImage: "globe.europe.africa",
                tokens: uniqueValues(bells.map(\.countryName)).map(BellSearchToken.country)
            ),
            SearchTokenGroup(
                title: String(localized: "bell_catalog.summary.materials"),
                systemImage: "shippingbox",
                tokens: uniqueValues(bells.map(\.materialDisplayName)).map(BellSearchToken.material)
            ),
            SearchTokenGroup(
                title: String(localized: "bell_catalog.summary.tags"),
                systemImage: "tag",
                tokens: uniqueValues(bells.flatMap(\.tagValues)).map(BellSearchToken.tag)
            ),
            SearchTokenGroup(
                title: String(localized: "common.field.condition"),
                systemImage: "checkmark.seal",
                tokens: uniqueConditions.map(BellSearchToken.condition)
            ),
            SearchTokenGroup(
                title: String(localized: "bell.detail.aquisition"),
                systemImage: "tray.and.arrow.down",
                tokens: uniqueAcquisitionMethods.map(BellSearchToken.acquisitionMethod)
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

    private var filteredBells: [BellListItem] {
        bells
            .filter { matches(bell: $0, searchState: searchState) }
            .sorted {
                if $0.createdAt == $1.createdAt {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }

                return $0.createdAt > $1.createdAt
            }
    }

    private var isBellDetailPresented: Binding<Bool> {
        Binding(
            get: { selectedBellID != nil },
            set: { isPresented in
                if !isPresented {
                    selectedBellID = nil
                }
            }
        )
    }

    var body: some View {
        SearchTabView(
            layoutMode: $layoutMode,
            query: $searchState.query,
            tokens: $searchState.tokens,
            suggestedTokenGroups: suggestedTokenGroups,
            initialQuery: initialQuery,
            tokenTitle: searchTokenTitle,
            tokenSystemImage: searchTokenSystemImage
        ) { layoutMetrics in
            searchResults(layoutMetrics: layoutMetrics)
        }
        .sheet(isPresented: isBellDetailPresented) {
            if let selectedBellID {
                BellDetailContainer(
                    bellID: selectedBellID,
                    repository: repository,
                    catalogSnapshot: catalogSnapshot
                )
                    .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private func searchResults(layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics) -> some View {
        if filteredBells.isEmpty {
            CatalogEmptyStateView(
                systemImage: "magnifyingglass",
                title: "bell_catalog.search.empty.title",
                message: "bell_catalog.search.empty.description"
            )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else {
            BellGridView(
                bells: filteredBells,
                layoutMode: layoutMode,
                layoutMetrics: layoutMetrics,
                selectedBellIDs: [],
                isSelectionModeEnabled: false,
                onTap: openBell,
                onSelect: nil
            )
        }
    }

    private func openBell(_ bell: BellListItem) {
        if let onBellSelected {
            onBellSelected(bell.id)
        } else {
            selectedBellID = bell.id
        }
    }

    private func searchTokenTitle(_ token: BellSearchToken) -> String {
        switch token {
        case .collection(let collectionID):
            return collectionTitlesByID[collectionID]
                ?? String(localized: "search.scope.collection")
        case .country(let value), .material(let value), .tag(let value):
            return value
        case .condition(let condition):
            return condition.displayName
        case .acquisitionMethod(let method):
            return method.displayName
        }
    }

    private func searchTokenSystemImage(_ token: BellSearchToken) -> String {
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

    private func matches(bell: BellListItem, searchState: BellCatalogSearchState) -> Bool {
        matchesQuery(searchState.query, in: bell, scope: searchState.scope)
        && searchState.tokens.allSatisfy { matches(token: $0, in: bell) }
    }

    private func matchesQuery(
        _ query: String,
        in bell: BellListItem,
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
            return collectionTitle(for: bell).localizedCaseInsensitiveContains(trimmedQuery)
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

    private func matchesScope(_ scope: BellCatalogSearchState.Scope, in bell: BellListItem) -> Bool {
        switch scope {
        case .all, .title, .collection, .origin, .tags, .notes:
            return true
        case .incomplete:
            return !bell.hasOrigin
            || bell.acquiredYear == nil
            || !bell.hasStorage
            || !bell.hasNotes
            || bell.tagValues.isEmpty
        }
    }

    private func matches(token: BellSearchToken, in bell: BellListItem) -> Bool {
        switch token {
        case .collection(let collectionID):
            return bell.collectionID == collectionID
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

    private func searchableValues(for bell: BellListItem) -> [String] {
        [
            bell.title,
            bell.notes,
            bell.materialDisplayName,
            collectionTitle(for: bell)
        ] + originValues(for: bell) + storageValues(for: bell) + bell.tagValues
    }

    private func originValues(for bell: BellListItem) -> [String] {
        return [
            bell.countryName,
            bell.cityName,
            bell.placeDisplayName,
            bell.regionName
        ]
    }

    private func storageValues(for bell: BellListItem) -> [String] {
        guard let storagePath = bell.storagePath, !storagePath.isEmpty else {
            return [bell.storageLocationName]
        }

        return [storagePath.displayPath] + storagePath.components.map(\.name)
    }

    private func collectionTitle(for bell: BellListItem) -> String {
        bell.collectionID.flatMap { collectionTitlesByID[$0] } ?? ""
    }
}
