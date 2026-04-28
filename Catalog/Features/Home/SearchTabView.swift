import SwiftUI
import SwiftData

struct SearchTabView: View {
    private enum SearchScope: String, CaseIterable, Identifiable {
        case all
        case title
        case collection
        case origin
        case tags
        case notes
        case incomplete

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return String(localized: "search.scope.all")
            case .title:
                return String(localized: "search.scope.title")
            case .collection:
                return String(localized: "search.scope.collection")
            case .origin:
                return String(localized: "search.scope.origin")
            case .tags:
                return String(localized: "search.scope.tags")
            case .notes:
                return String(localized: "search.scope.notes")
            case .incomplete:
                return String(localized: "search.scope.incomplete")
            }
        }
    }

    private enum SearchToken: Identifiable, Hashable {
        case material(String)
        case countryCity(country: String, city: String?)
        case tag(String)

        var id: String {
            switch self {
            case .material(let value):
                return "material:\(value.lowercased())"
            case .countryCity(let country, let city):
                let normalizedCity = city?.lowercased() ?? ""
                return "country-city:\(country.lowercased()):\(normalizedCity)"
            case .tag(let value):
                return "tag:\(value.lowercased())"
            }
        }

        var title: String {
            switch self {
            case .material(let value):
                return value
            case .countryCity(let country, let city):
                if let city, !city.isEmpty {
                    return "\(country) · \(city)"
                }

                return country
            case .tag(let value):
                return "#\(value)"
            }
        }

        var systemImage: String {
            switch self {
            case .material:
                return "square.grid.3x3.topleft.filled"
            case .countryCity:
                return "mappin.and.ellipse"
            case .tag:
                return "tag"
            }
        }
    }

    let repository: any CatalogRepository
    @Query(sort: \BellEntity.createdAt, order: .reverse) private var allBells: [BellEntity]
    @AppStorage("search.tab.scope") private var selectedScopeRawValue = SearchScope.all.rawValue
    @State private var query = ""
    @State private var selectedTokens: [SearchToken] = []
    @State private var isSearchPresented = true
    @FocusState private var isSearchFocused: Bool

    private var selectedScope: SearchScope {
        get { SearchScope(rawValue: selectedScopeRawValue) ?? .all }
        nonmutating set { selectedScopeRawValue = newValue.rawValue }
    }

    private var suggestedTokens: [SearchToken] {
        let materialTokens = topTokens(
            from: allBells.map { SearchToken.material($0.materialDisplayName) },
            limit: 8
        )

        let countryCityTokens = topTokens(
            from: allBells.compactMap { bell -> SearchToken? in
                let country = bell.countryName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !country.isEmpty else { return nil }

                let city = bell.cityName.trimmingCharacters(in: .whitespacesAndNewlines)
                return .countryCity(country: country, city: city.isEmpty ? nil : city)
            },
            limit: 10
        )

        let tagTokens = topTokens(
            from: allBells.flatMap { bell in
                bell.tagValues.map { SearchToken.tag($0) }
            },
            limit: 12
        )

        return (materialTokens + countryCityTokens + tagTokens)
            .filter { !selectedTokens.contains($0) }
    }

    private func topTokens(from tokens: [SearchToken], limit: Int) -> [SearchToken] {
        Dictionary(tokens.map { ($0, 1) }, uniquingKeysWith: +)
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }

                return lhs.key.title.localizedCaseInsensitiveCompare(rhs.key.title) == .orderedAscending
            }
            .prefix(limit)
            .map(\.key)
    }

    private var searchResults: [BellEntity] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return allBells
            .filter { bell in
                matchesSearchScope(for: bell, query: trimmedQuery) && matchesSelectedTokens(for: bell)
            }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var showsEmptySearchState: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedTokens.isEmpty &&
        selectedScope != .incomplete
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !showsEmptySearchState {
                        Text(searchResultsCountText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)
                    }

                    if showsEmptySearchState {
                        ContentUnavailableView.search
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    } else if searchResults.isEmpty {
                        ContentUnavailableView(
                            String(localized: "bell_catalog.search.empty.title"),
                            systemImage: "magnifyingglass",
                            description: Text(String(localized: "bell_catalog.search.empty.description"))
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 16
                        ) {
                            ForEach(searchResults) { bell in
                                NavigationLink {
                                    SearchBellDetailContainer(
                                        repository: repository,
                                        bell: bell
                                    )
                                } label: {
                                    BellSearchResultCard(
                                        bell: bell,
                                        collectionName: collectionName(for: bell)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .padding(.top, CatalogLayoutInsets.overlay)
            .contentMargins(.horizontal, nil, for: .scrollContent)
            .contentMargins(.bottom, 120, for: .scrollContent)
            .background(
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
            )
            .searchable(
                text: $query,
                tokens: $selectedTokens,
                suggestedTokens: .constant(suggestedTokens),
                isPresented: $isSearchPresented,
                prompt: String(localized: "collections.search.prompt")
            ) { token in
                Label(token.title, systemImage: token.systemImage)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .searchFocused($isSearchFocused)
        .defaultFocus($isSearchFocused, true)
        .onAppear {
            isSearchPresented = true
            isSearchFocused = true
        }
    }

    private var searchResultsCountText: String {
        String.localizedStringWithFormat(
            String(localized: "search.results.count"),
            searchResults.count
        )
    }

    private func matchesSearchScope(for bell: BellEntity, query: String) -> Bool {
        if selectedScope == .incomplete {
            return matchesIncomplete(bell) && (query.isEmpty || searchableText(for: bell, scope: .all).localizedCaseInsensitiveContains(query))
        }

        guard !query.isEmpty else { return false }
        return searchableText(for: bell, scope: selectedScope).localizedCaseInsensitiveContains(query)
    }

    private func searchableText(for bell: BellEntity, scope: SearchScope) -> String {
        switch scope {
        case .all:
            return [
                bell.title,
                bell.notes,
                bell.placeDisplayName,
                bell.storageDisplayPath,
                bell.condition.displayName,
                bell.acquisitionMethod.displayName,
                bell.materialDisplayName,
                collectionName(for: bell),
                bell.tagValues.joined(separator: " ")
            ]
            .joined(separator: "\n")
        case .title:
            return bell.title
        case .collection:
            return collectionName(for: bell)
        case .origin:
            return [bell.placeDisplayName, bell.storageDisplayPath]
                .joined(separator: "\n")
        case .tags:
            return bell.tagValues.joined(separator: " ")
        case .notes:
            return bell.notes
        case .incomplete:
            return searchableText(for: bell, scope: .all)
        }
    }

    private func matchesIncomplete(_ bell: BellEntity) -> Bool {
        bell.originPlace == nil ||
        bell.location == nil ||
        bell.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        bell.tagValues.isEmpty
    }

    private func matchesSelectedTokens(for bell: BellEntity) -> Bool {
        let materialTokens = selectedTokens.compactMap { token -> String? in
            guard case .material(let material) = token else { return nil }
            return material
        }

        let countryCityTokens = selectedTokens.compactMap { token -> (country: String, city: String?)? in
            guard case .countryCity(let country, let city) = token else { return nil }
            return (country, city)
        }

        let tagTokens = selectedTokens.compactMap { token -> String? in
            guard case .tag(let tag) = token else { return nil }
            return tag
        }

        if !materialTokens.isEmpty {
            let matchesMaterial = materialTokens.contains { material in
                bell.materialDisplayName.localizedCaseInsensitiveCompare(material) == .orderedSame
            }
            guard matchesMaterial else { return false }
        }

        if !countryCityTokens.isEmpty {
            let matchesCountryCity = countryCityTokens.contains { token in
                let matchesCountry = bell.countryName.localizedCaseInsensitiveCompare(token.country) == .orderedSame
                guard matchesCountry else { return false }

                if let city = token.city, !city.isEmpty {
                    guard let bellCity = bell.originPlace?.cityName else { return false }
                    return bellCity.localizedCaseInsensitiveCompare(city) == .orderedSame
                }

                return true
            }
            guard matchesCountryCity else { return false }
        }

        if !tagTokens.isEmpty {
            let matchesTag = tagTokens.contains { tag in
                bell.tagValues.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
            }
            guard matchesTag else { return false }
        }

        return true
    }

    private func collectionName(for bell: BellEntity) -> String {
        bell.collection?.title ?? ""
    }
}

private struct SearchBellDetailContainer: View {
    let repository: any CatalogRepository
    @State var bell: BellRecord

    init(repository: any CatalogRepository, bell: BellEntity) {
        self.repository = repository
        _bell = State(initialValue: bell.recordSnapshot)
    }

    var body: some View {
        BellDetailView(bell: $bell, repository: repository)
    }
}

private struct BellSearchResultCard: View {
    let bell: BellEntity
    let collectionName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BellCardView(bell: bell, layoutMode: .compact)
                .allowsHitTesting(false)

            if !collectionName.isEmpty {
                Text(collectionName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, CatalogSpacing.micro)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}