import SwiftUI
import CoreData

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
    let onBellSelected: ((UUID) -> Void)?
    private let initialQuery: String?
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Binding var layoutMode: CatalogCardLayoutMode
    @State private var searchSnapshot = SearchCatalogSnapshot()
    @State private var selectedBellID: UUID?
    @State private var searchState = BellCatalogSearchState()
    @State private var didApplyInitialQuery = false
    @FocusState private var isSearchFocused: Bool

    init(
        repository: any CatalogRepository,
        layoutMode: Binding<CatalogCardLayoutMode>,
        initialQuery: String? = nil,
        onBellSelected: ((UUID) -> Void)? = nil
    ) {
        self.repository = repository
        self._layoutMode = layoutMode
        self.initialQuery = initialQuery
        self.onBellSelected = onBellSelected
    }

    private var bells: [BellListItem] {
        searchSnapshot.bells
    }

    private var suggestedTokenGroups: [SearchTokenGroup] {
        let selectedTokens = Set(searchState.tokens)

        return [
            SearchTokenGroup(
                title: String(localized: "root_tab.collections"),
                systemImage: "rectangle.stack",
                tokens: searchSnapshot.collections.map { SearchToken.collection($0.id) }
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
                title: String(localized: "bell.detail.aquisition"),
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

    private var filteredBells: [BellListItem] {
        searchSnapshot.bells
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
        CatalogCardGrid(layoutMode: layoutMode, usesGridLayout: false) { cardSize, gridMetrics, cardMetrics in
            LazyVStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xl) {
                searchHeader

                searchResults(layoutMetrics: (cardSize, gridMetrics, cardMetrics))
            }
            .padding(.top, CatalogMetrics.Spacing.xl)
        }
        .searchable(
            text: $searchState.query,
            tokens: $searchState.tokens
        ) { token in
            Label(searchTokenTitle(token), systemImage: searchTokenSystemImage(token))
        }
        .searchFocused($isSearchFocused)
        .onAppear {
            reloadSearchSnapshot()
            applyInitialQueryIfNeeded()
            isSearchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: managedObjectContext
        )) { _ in
            reloadSearchSnapshot()
        }
        .sheet(isPresented: isBellDetailPresented) {
            if let selectedBellID {
                BellDetailContainer(
                    bellID: selectedBellID,
                    repository: repository
                )
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            Text("common.ui.search")
                .font(CatalogTypography.screenTitle)
                .foregroundStyle(.primary)
                .padding(.horizontal, CatalogMetrics.Insets.screen)

            SearchTokenBar(
                tokens: searchState.tokens,
                suggestedTokenGroups: suggestedTokenGroups,
                title: searchTokenTitle,
                select: selectToken,
                remove: removeToken
            )
            .ignoresSafeArea(.container, edges: .horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                recordFor: { searchSnapshot.recordsByID[$0.id] },
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

    private func reloadSearchSnapshot() {
        searchSnapshot = SearchCatalogSnapshot(context: managedObjectContext)
    }

    private func applyInitialQueryIfNeeded() {
        guard !didApplyInitialQuery else { return }
        didApplyInitialQuery = true

        guard let initialQuery else { return }
        searchState.query = initialQuery
    }

    private func searchTokenTitle(_ token: SearchToken) -> String {
        switch token {
        case .collection(let collectionID):
            return searchSnapshot.collectionTitlesByID[collectionID]
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
            searchSnapshot.bells.contains { $0.condition == condition }
        }
    }

    private var uniqueAcquisitionMethods: [AcquisitionMethod] {
        AcquisitionMethod.allCases.filter { method in
            searchSnapshot.bells.contains { $0.acquisitionMethod == method }
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

    private func matches(token: SearchToken, in bell: BellListItem) -> Bool {
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
        let record = searchSnapshot.recordsByID[bell.id]

        return [
            bell.countryName,
            bell.cityName,
            bell.placeDisplayName,
            record?.originPlace?.regionName ?? bell.regionName
        ]
    }

    private func storageValues(for bell: BellListItem) -> [String] {
        let record = searchSnapshot.recordsByID[bell.id]

        return [
            record?.storageDisplayPath ?? "",
            record?.storageLocationName ?? "",
            bell.storageFloor,
            bell.storageRoom,
            bell.storageCabinet,
            bell.storageShelf
        ]
    }

    private func collectionTitle(for bell: BellListItem) -> String {
        bell.collectionID.flatMap { searchSnapshot.collectionTitlesByID[$0] } ?? ""
    }
}

private struct SearchTokenGroup: Identifiable {
    let title: String
    let systemImage: String
    let tokens: [SearchToken]

    var id: String { title }
}

private struct SearchCollectionSnapshot: Identifiable {
    let id: UUID
    let title: String
}

private struct SearchCatalogSnapshot {
    var collections: [SearchCollectionSnapshot] = []
    var bells: [BellListItem] = []
    var recordsByID: [UUID: BellRecord] = [:]
    var collectionTitlesByID: [UUID: String] = [:]

    init() {}

    init(context: NSManagedObjectContext) {
        let catalogSnapshot = BellCatalogSnapshot(context: context, collectionID: nil)
        let collectionEntities = Self.fetchEntities(
            named: "CollectionEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "title", ascending: true)]
        )

        collections = collectionEntities.map {
            SearchCollectionSnapshot(
                id: Self.uuidValue($0, "id"),
                title: Self.stringValue($0, "title")
            )
        }
        bells = catalogSnapshot.bells
        recordsByID = catalogSnapshot.recordsByID
        collectionTitlesByID = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0.title) })
    }

    private static func fetchEntities(
        named entityName: String,
        in context: NSManagedObjectContext,
        sortDescriptors: [NSSortDescriptor]
    ) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.sortDescriptors = sortDescriptors
        return (try? context.fetch(request)) ?? []
    }

    private static func uuidValue(_ entity: NSManagedObject, _ key: String) -> UUID {
        entity.value(forKey: key) as? UUID ?? UUID()
    }

    private static func stringValue(_ entity: NSManagedObject, _ key: String) -> String {
        entity.value(forKey: key) as? String ?? ""
    }
}

private struct SearchTokenBar: View {
    let tokens: [SearchToken]
    let suggestedTokenGroups: [SearchTokenGroup]
    let title: (SearchToken) -> String
    let select: (SearchToken) -> Void
    let remove: (SearchToken) -> Void

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
