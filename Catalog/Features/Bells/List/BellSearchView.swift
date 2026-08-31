import SwiftUI
import CoreData

/// Groups search token values and behavior.
enum BellSearchToken: Identifiable, Hashable {
    case collection(UUID)
    case country(String)
    case material(String)
    case tag(String)
    case condition(ItemCondition)
    case acquisitionMethod(AcquisitionMethod)
    case presence(BellPresenceFilter)

    enum Category: Hashable {
        case collection
        case country
        case material
        case tag
        case condition
        case acquisitionMethod
        case presence
    }

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
        case .presence(let filter):
            return "presence:\(filter.searchID)"
        }
    }

    var category: Category {
        switch self {
        case .collection:
            return .collection
        case .country:
            return .country
        case .material:
            return .material
        case .tag:
            return .tag
        case .condition:
            return .condition
        case .acquisitionMethod:
            return .acquisitionMethod
        case .presence:
            return .presence
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
                title: String(localized: "common.field.tags"),
                systemImage: "tag",
                tokens: uniqueValues(bells.flatMap(\.tagValues)).map(BellSearchToken.tag)
            ),
            SearchTokenGroup(
                title: String(localized: "common.field.condition"),
                systemImage: "checkmark.seal",
                tokens: uniqueConditions.map(BellSearchToken.condition)
            ),
            SearchTokenGroup(
                title: String(localized: "item.detail.acquisition"),
                systemImage: "tray.and.arrow.down",
                tokens: uniqueAcquisitionMethods.map(BellSearchToken.acquisitionMethod)
            ),
            SearchTokenGroup(
                title: String(localized: "catalog.dashboard.health"),
                systemImage: "checklist",
                tokens: BellPresenceFilter.allSearchFilters.map(BellSearchToken.presence)
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

    var body: some View {
        SearchShellView(
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
        onBellSelected?(bell.id)
    }

    private func searchTokenTitle(_ token: BellSearchToken) -> String {
        switch token {
        case .collection(let collectionID):
            return collectionTitlesByID[collectionID]
                ?? String(localized: "common.collection")
        case .country(let value), .material(let value), .tag(let value):
            return value
        case .condition(let condition):
            return condition.displayName
        case .acquisitionMethod(let method):
            return method.displayName
        case .presence(let filter):
            return filter.searchTitle
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
        case .presence:
            return "checklist"
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
            && matches(tokens: searchState.tokens, in: bell)
    }

    private func matches(tokens: [BellSearchToken], in bell: BellListItem) -> Bool {
        let groupedTokens = Dictionary(grouping: tokens, by: \.category)
        return groupedTokens.values.allSatisfy { group in
            group.contains { matches(token: $0, in: bell) }
        }
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
        case .presence(let filter):
            return filter.matches(bell)
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

private extension BellPresenceFilter {
    static let allSearchFilters: [BellPresenceFilter] = [
        .withOrigin,
        .missingOrigin,
        .withYear,
        .missingYear,
        .withCity,
        .withStorage,
        .missingStorage,
        .withNotes,
        .missingNotes,
        .withTags,
        .missingTags,
        .withMaterial,
        .missingMaterial
    ]

    var searchID: String {
        switch self {
        case .withOrigin: return "with-origin"
        case .missingOrigin: return "missing-origin"
        case .withYear: return "with-year"
        case .missingYear: return "missing-year"
        case .withCity: return "with-city"
        case .withStorage: return "with-storage"
        case .missingStorage: return "missing-storage"
        case .withNotes: return "with-notes"
        case .missingNotes: return "missing-notes"
        case .withTags: return "with-tags"
        case .missingTags: return "missing-tags"
        case .withMaterial: return "with-material"
        case .missingMaterial: return "missing-material"
        }
    }

    var searchTitle: String {
        switch self {
        case .withOrigin:
            return String(localized: "bell_catalog.summary.with_origin")
        case .missingOrigin:
            return String(localized: "bell_catalog.summary.missing_origin")
        case .withYear:
            return String(localized: "bell_catalog.summary.with_year")
        case .missingYear:
            return String(localized: "bell_catalog.summary.missing_year")
        case .withCity:
            return String(localized: "bell_catalog.summary.with_city")
        case .withStorage:
            return String(localized: "bell_catalog.summary.with_storage")
        case .missingStorage:
            return String(localized: "bell_catalog.summary.missing_storage")
        case .withNotes:
            return String(localized: "bell_catalog.summary.with_notes")
        case .missingNotes:
            return String(localized: "bell_catalog.summary.missing_notes")
        case .withTags:
            return String(localized: "bell_catalog.summary.with_tags")
        case .missingTags:
            return String(localized: "bell_catalog.summary.missing_tags")
        case .withMaterial:
            return String(localized: "bell_catalog.summary.with_material")
        case .missingMaterial:
            return String(localized: "bell_catalog.summary.missing_material")
        }
    }

    func matches(_ bell: BellListItem) -> Bool {
        switch self {
        case .withOrigin:
            return bell.hasOrigin
        case .missingOrigin:
            return !bell.hasOrigin
        case .withYear:
            return bell.acquiredYear != nil
        case .missingYear:
            return bell.acquiredYear == nil
        case .withCity:
            return !bell.cityName.isEmpty
        case .withStorage:
            return bell.hasStorage
        case .missingStorage:
            return !bell.hasStorage
        case .withNotes:
            return bell.hasNotes
        case .missingNotes:
            return !bell.hasNotes
        case .withTags:
            return !bell.tagValues.isEmpty
        case .missingTags:
            return bell.tagValues.isEmpty
        case .withMaterial:
            return bell.material != .unknown
        case .missingMaterial:
            return bell.material == .unknown
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
        BellSearchView(
            repository: repository,
            layoutMode: layoutMode,
            catalogSnapshot: catalogSnapshot,
            initialQuery: initialQuery,
            onBellSelected: onItemSelected
        )
    )
}

@MainActor
func makeCollectionDestinationContent(
    collection: CollectionSummary,
    catalogSnapshot: CatalogSnapshot?,
    repository: any CatalogRepository,
    coreDataContainer: NSPersistentCloudKitContainer,
    layoutMode: Binding<CatalogCardLayoutMode>,
    onItemSelected: ((UUID) -> Void)?,
    onBatchAddComplete: @escaping (Any) -> Void
) -> AnyView {
    AnyView(
        BellCollectionView(
            collection: collection,
            catalogSnapshot: catalogSnapshot,
            repository: repository,
            coreDataContainer: coreDataContainer,
            layoutMode: layoutMode,
            onBellSelected: onItemSelected,
            onBatchAddComplete: onBatchAddComplete
        )
    )
}

@MainActor
func makeItemDetailContent(
    itemID: UUID,
    repository: any CatalogRepository,
    catalogSnapshot: CatalogSnapshot?,
    onClose: (() -> Void)?
) -> AnyView {
    AnyView(
        BellItemDetailContainer(
            bellID: itemID,
            repository: repository,
            catalogSnapshot: catalogSnapshot,
            onClose: onClose
        )
    )
}
