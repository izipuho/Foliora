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
    @Query(sort: \CollectionEntity.title) private var collections: [CollectionEntity]
    @Query(sort: \BellEntity.title) private var bells: [BellEntity]
    @AppStorage("bellCatalog.orderMode") private var orderModeRawValue = BellOrderMode.newestFirst.rawValue
    @AppStorage("bellCatalog.layoutMode") private var layoutModeRawValue = BellGridLayoutMode.mini.rawValue
    @State private var filters = BellFilters()
    @State private var searchState = BellCatalogSearchState()

    private var layoutMode: BellGridLayoutMode {
        get {
            BellGridLayoutMode(rawValue: layoutModeRawValue) ?? .mini
        }
        nonmutating set {
            layoutModeRawValue = newValue.rawValue
        }
    }

    private var orderMode: BellOrderMode {
        get {
            BellOrderMode(rawValue: orderModeRawValue) ?? .newestFirst
        }
        nonmutating set {
            orderModeRawValue = newValue.rawValue
        }
    }

    private var layoutModeBinding: Binding<BellGridLayoutMode> {
        Binding(
            get: { layoutMode },
            set: { layoutMode = $0 }
        )
    }

    private var orderModeBinding: Binding<BellOrderMode> {
        Binding(
            get: { orderMode },
            set: { orderMode = $0 }
        )
    }

    init(
        repository: any CatalogRepository,
        onBellSelected: ((BellEntity) -> Void)? = nil
    ) {
        self.repository = repository
        self.onBellSelected = onBellSelected
    }

    private var suggestedTokenGroups: [SearchTokenGroup] {
        let selectedTokens = Set(searchState.tokens)

        return [
            SearchTokenGroup(
                title: "Коллекции",
                systemImage: "rectangle.stack",
                tokens: collections.map { SearchToken.collection($0.id) }
            ),
            SearchTokenGroup(
                title: "Страны",
                systemImage: "globe.europe.africa",
                tokens: uniqueValues(bells.map(\.countryName)).map(SearchToken.country)
            ),
            SearchTokenGroup(
                title: "Материалы",
                systemImage: "shippingbox",
                tokens: uniqueValues(bells.map(\.materialDisplayName)).map(SearchToken.material)
            ),
            SearchTokenGroup(
                title: "Теги",
                systemImage: "tag",
                tokens: uniqueValues(bells.flatMap(\.tagValues)).map(SearchToken.tag)
            ),
            SearchTokenGroup(
                title: "Состояние",
                systemImage: "checkmark.seal",
                tokens: uniqueConditions.map(SearchToken.condition)
            ),
            SearchTokenGroup(
                title: "Получение",
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchTokenBar(
                    tokens: searchState.tokens,
                    suggestedTokenGroups: suggestedTokenGroups,
                    title: searchTokenTitle,
                    select: selectToken,
                    remove: removeToken
                )
                .padding(.vertical, 8)
                .background(.regularMaterial)

                BellCatalogView(
                    collection: nil,
                    repository: repository,
                    collaborators: [],
                    displayMode: .search,
                    layoutMode: layoutModeBinding,
                    orderMode: orderModeBinding,
                    filters: $filters,
                    searchState: $searchState,
                    startsSearchFocused: true,
                    onBellSelected: onBellSelected
                )
            }
            .toolbar(.hidden, for: .navigationBar)
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
