import SwiftUI
import UIKit

private func BL(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

private enum SummaryCountKind {
    case bells
    case materials
    case countries
    case cities
    case members

    func title(for count: Int) -> String {
        if Locale.preferredLanguages.first?.hasPrefix("ru") == true {
            switch self {
            case .bells:
                return russianPlural(count, one: "колокольчик", few: "колокольчика", many: "колокольчиков")
            case .materials:
                return russianPlural(count, one: "материал", few: "материала", many: "материалов")
            case .countries:
                return russianPlural(count, one: "страна", few: "страны", many: "стран")
            case .cities:
                return russianPlural(count, one: "город", few: "города", many: "городов")
            case .members:
                return russianPlural(count, one: "участник", few: "участника", many: "участников")
            }
        }

        switch self {
        case .bells:
            return count == 1 ? "bell" : "bells"
        case .materials:
            return count == 1 ? "material" : "materials"
        case .countries:
            return count == 1 ? "country" : "countries"
        case .cities:
            return count == 1 ? "city" : "cities"
        case .members:
            return count == 1 ? "member" : "members"
        }
    }
}

private func russianPlural(_ count: Int, one: String, few: String, many: String) -> String {
    let remainder100 = count % 100
    let remainder10 = count % 10

    if remainder100 >= 11 && remainder100 <= 14 {
        return many
    }

    switch remainder10 {
    case 1:
        return one
    case 2...4:
        return few
    default:
        return many
    }
}

enum BellSortOption: String, CaseIterable, Hashable {
    case title
    case origin
    case yearNewest
    case yearOldest

    var title: String {
        switch self {
        case .title:
            return BL("bell_catalog.sort.title")
        case .origin:
            return BL("bell_catalog.sort.origin")
        case .yearNewest:
            return BL("bell_catalog.sort.year_newest")
        case .yearOldest:
            return BL("bell_catalog.sort.year_oldest")
        }
    }
}

enum BellCatalogMode {
    case summary
    case items
    case search
}

enum BellSummaryFilter: Hashable {
    case all
    case withOrigin
    case missingOrigin
    case withCity
    case withStorage
    case missingStorage
    case withNotes
    case missingNotes
    case withTags
    case missingTags
    case withMaterial
    case country(String)
    case material(String)
    case tag(String)

    func title() -> String {
        switch self {
        case .all:
            return BL("bell_catalog.filter_summary.all")
        case .withOrigin:
            return BL("bell_catalog.summary.with_origin")
        case .missingOrigin:
            return BL("bell_catalog.filter_summary.missing_origin")
        case .withCity:
            return BL("bell_catalog.filter_summary.with_city")
        case .withStorage:
            return BL("bell_catalog.summary.with_storage")
        case .missingStorage:
            return BL("bell_catalog.filter_summary.missing_storage")
        case .withNotes:
            return BL("bell_catalog.summary.with_notes")
        case .missingNotes:
            return BL("bell_catalog.filter_summary.missing_notes")
        case .withTags:
            return BL("bell_catalog.summary.with_tags")
        case .missingTags:
            return BL("bell_catalog.filter_summary.missing_tags")
        case .withMaterial:
            return BL("bell_catalog.filter_summary.with_material")
        case .country(let value), .material(let value), .tag(let value):
            return value
        }
    }
}

enum BellGridLayoutMode: Int, CaseIterable {
    case covers
    case mini
    case compact
    case wide
    case showcase

    var columnCount: Int {
        switch self {
        case .covers:
            return 4
        case .mini:
            return 3
        case .compact:
            return 2
        case .wide, .showcase:
            return 1
        }
    }

    var cardHeight: CGFloat {
        switch self {
        case .covers:
            return 92
        case .mini:
            return 144
        case .compact:
            return 220
        case .wide:
            return 170
        case .showcase:
            return 460
        }
    }

    var cardPadding: CGFloat {
        switch self {
        case .covers:
            return 0
        case .mini:
            return 10
        case .compact:
            return 14
        case .wide:
            return 18
        case .showcase:
            return 22
        }
    }

    var spacing: CGFloat {
        switch self {
        case .covers:
            return 8
        case .mini:
            return 10
        case .compact:
            return 12
        case .wide:
            return 14
        case .showcase:
            return 18
        }
    }

    func preferredCardWidth(for availableWidth: CGFloat) -> CGFloat {
        let totalSpacing = spacing * CGFloat(max(columnCount - 1, 0))
        let usableWidth = max(availableWidth - totalSpacing, 0)
        return floor(usableWidth / CGFloat(columnCount))
    }

    var stripHeight: CGFloat {
        cardHeight + spacing
    }
}

struct BellCatalogView: View {
    let repository: any CatalogRepository
    let collaborators: [Collaborator]
    let collection: CollectionSummary
    let mode: BellCatalogMode
    let sortOption: BellSortOption
    let summaryFilter: BellSummaryFilter?
    let onSelectSummaryFilter: ((BellSummaryFilter) -> Void)?
    let onClearSummaryFilter: (() -> Void)?

    @State private var bellRecords: [BellRecord]
    @State private var searchText = ""
    @State private var selectedCondition: ItemCondition?
    @State private var layoutMode: BellGridLayoutMode = .compact
    @State private var presentedBell: BellRecord?

    init(
        collection: CollectionSummary,
        repository: any CatalogRepository,
        collaborators: [Collaborator],
        mode: BellCatalogMode,
        sortOption: BellSortOption = .title,
        summaryFilter: BellSummaryFilter? = nil,
        onSelectSummaryFilter: ((BellSummaryFilter) -> Void)? = nil,
        onClearSummaryFilter: (() -> Void)? = nil
    ) {
        self.repository = repository
        self.collaborators = collaborators
        self.collection = collection
        self.mode = mode
        self.sortOption = sortOption
        self.summaryFilter = summaryFilter
        self.onSelectSummaryFilter = onSelectSummaryFilter
        self.onClearSummaryFilter = onClearSummaryFilter
        _bellRecords = State(initialValue: repository.fetchBellRecords(for: collection.id))
    }

    private var bells: [BellRecord] {
        sorted(bellRecords)
    }

    private var filteredBells: [BellRecord] {
        sorted(
            bellRecords.filter { bell in
            let matchesSearch =
                searchText.isEmpty ||
                bell.title.localizedCaseInsensitiveContains(searchText) ||
                bell.countryName.localizedCaseInsensitiveContains(searchText) ||
                bell.cityName.localizedCaseInsensitiveContains(searchText) ||
                bell.tags.joined(separator: " ").localizedCaseInsensitiveContains(searchText)

            let matchesCondition = selectedCondition == nil || bell.condition == selectedCondition
            let matchesSummaryFilter = matches(bell: bell, summaryFilter: summaryFilter)
            return matchesSearch && matchesCondition && matchesSummaryFilter
        })
    }

    private var countryCount: Int {
        Set(bells.map(\.countryName).filter { !$0.isEmpty }).count
    }

    private var materialCount: Int {
        Set(bells.map(\.materialDisplayName)).count
    }

    private var cityCount: Int {
        Set(bells.map(\.cityName).filter { !$0.isEmpty }).count
    }

    private var themeColors: [Color] {
        collection.backgroundStyle.screenColors
    }

    private var homeName: String {
        repository.fetchHomes().first(where: { $0.id == collection.homeID })?.name ?? BL("common.unknown")
    }

    private var bellsWithOriginCount: Int {
        bells.filter { $0.originPlace != nil }.count
    }

    private var bellsWithStorageCount: Int {
        bells.filter { $0.item.locationID != nil }.count
    }

    private var bellsWithPhotosCount: Int {
        bells.filter { $0.photoCount > 0 }.count
    }

    private var filteredItemsBells: [BellRecord] {
        sorted(
            bellRecords.filter { bell in
                matches(bell: bell, summaryFilter: summaryFilter)
            }
        )
    }

    private var topCountries: [(String, Int)] {
        Dictionary(grouping: bells.map(\.countryName).filter { !$0.isEmpty }, by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
                }

                return lhs.1 > rhs.1
            }
    }

    private var topMaterials: [(String, Int)] {
        Dictionary(grouping: bells.map(\.materialDisplayName), by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
                }

                return lhs.1 > rhs.1
            }
    }

    private var topTags: [(String, Int)] {
        Dictionary(grouping: bells.flatMap(\.tags), by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
                }

                return lhs.1 > rhs.1
            }
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: layoutMode.spacing, alignment: .top),
            count: layoutMode.columnCount
        )
    }

    @ViewBuilder
    var body: some View {
        Group {
            switch mode {
            case .summary:
                summaryContent
            case .items:
                bellGridContent(
                    bells: filteredItemsBells,
                    showsSearchControls: false,
                    emptyTitle: LocalizedStringKey(BL("bell_catalog.empty.title")),
                    emptyDescription: LocalizedStringKey(BL("bell_catalog.empty.description"))
                )
            case .search:
                bellGridContent(
                    bells: filteredBells,
                    showsSearchControls: true,
                    emptyTitle: LocalizedStringKey(BL("bell_catalog.search.empty.title")),
                    emptyDescription: LocalizedStringKey(BL("bell_catalog.search.empty.description"))
                )
            }
        }
        .sheet(item: $presentedBell, onDismiss: {
            bellRecords = repository.fetchBellRecords(for: collection.id)
        }) { bell in
            BellGridDetailSheetContainer(bell: bell, repository: repository)
                .presentationDragIndicator(.visible)
        }
    }

    private var summaryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryOverviewCard
                summarySnapshotCard
                summaryCoverageCard
                summaryBreakdownCard(
                    title: BL("bell_catalog.summary.top_countries"),
                    emptyTitle: BL("bell_catalog.summary.no_origin_data"),
                    rows: Array(topCountries.prefix(4))
                )
                summaryBreakdownCard(
                    title: BL("bell_catalog.summary.top_materials"),
                    emptyTitle: BL("bell_catalog.summary.no_material_data"),
                    rows: Array(topMaterials.prefix(4))
                )
                summaryTagCloudCard
                summaryRecentBells
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .background(
            LinearGradient(
                colors: themeColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    private func bellGridContent(
        bells: [BellRecord],
        showsSearchControls: Bool,
        emptyTitle: LocalizedStringKey,
        emptyDescription: LocalizedStringKey
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !showsSearchControls, let summaryFilter, summaryFilter != .all {
                    activeSummaryFilterSection
                }

                if showsSearchControls {
                    searchSection
                }

                if bells.isEmpty {
                    emptyBellsGridState(title: emptyTitle, description: emptyDescription)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: layoutMode.spacing) {
                        ForEach(bells) { bell in
                            Button {
                                presentedBell = bell
                            } label: {
                                BellCardView(
                                    bell: bell,
                                    layoutMode: layoutMode
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
            .animation(.snappy(duration: 0.24), value: layoutMode)
        }
        .simultaneousGesture(zoomGesture)
        .background(
            LinearGradient(
                colors: themeColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    private func emptyBellsGridState(title: LocalizedStringKey, description: LocalizedStringKey) -> some View {
        ContentUnavailableView(
            title,
            systemImage: "bell.slash",
            description: Text(description)
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var summaryOverviewCard: some View {
        Button {
            onSelectSummaryFilter?(.all)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                if !collection.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(collection.subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    SummaryPill(systemImage: "house.fill", title: homeName, tint: collection.backgroundStyle.accentColor)
                    SummaryPill(
                        systemImage: "person.2.fill",
                        title: "\(collection.collaboratorCount) \(SummaryCountKind.members.title(for: collection.collaboratorCount))",
                        tint: collection.backgroundStyle.accentColor
                    )
                }
            }
            .summaryGlassCard()
        }
        .buttonStyle(.plain)
    }

    private var summarySnapshotCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                summaryStatChip(value: "\(bells.count)", title: SummaryCountKind.bells.title(for: bells.count), filter: .all)
                summaryStatChip(value: "\(materialCount)", title: SummaryCountKind.materials.title(for: materialCount), filter: .withMaterial)
                summaryStatChip(value: "\(countryCount)", title: SummaryCountKind.countries.title(for: countryCount), filter: .withOrigin)
                summaryStatChip(value: "\(cityCount)", title: SummaryCountKind.cities.title(for: cityCount), filter: .withCity)
            }
        }
        .summaryGlassCard()
    }

    private var summaryCoverageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(BL("bell_catalog.summary.coverage"))
                .font(.headline)

            SummaryCoverageRow(title: BL("bell_catalog.summary.with_origin"), value: bellsWithOriginCount, total: bells.count, tint: collection.backgroundStyle.accentColor) {
                onSelectSummaryFilter?(.missingOrigin)
            }
            SummaryCoverageRow(title: BL("bell_catalog.summary.with_storage"), value: bellsWithStorageCount, total: bells.count, tint: collection.backgroundStyle.accentColor) {
                onSelectSummaryFilter?(.missingStorage)
            }
            SummaryCoverageRow(title: BL("bell_catalog.summary.with_notes"), value: bells.filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count, total: bells.count, tint: collection.backgroundStyle.accentColor) {
                onSelectSummaryFilter?(.missingNotes)
            }
            SummaryCoverageRow(title: BL("bell_catalog.summary.with_tags"), value: bells.filter { !$0.tags.isEmpty }.count, total: bells.count, tint: collection.backgroundStyle.accentColor) {
                onSelectSummaryFilter?(.missingTags)
            }
        }
        .summaryGlassCard()
    }

    private func summaryBreakdownCard(
        title: String,
        emptyTitle: String,
        rows: [(String, Int)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if rows.isEmpty {
                Text(emptyTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        SummaryBreakdownRow(title: row.0, value: row.1, tint: collection.backgroundStyle.accentColor) {
                            if title == BL("bell_catalog.summary.top_countries") {
                                onSelectSummaryFilter?(.country(row.0))
                            } else {
                                onSelectSummaryFilter?(.material(row.0))
                            }
                        }
                    }
                }
            }
        }
        .summaryGlassCard()
    }

    private var summaryRecentBells: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(BL("bell_catalog.summary.recent"))
                .font(.headline)

            if bells.isEmpty {
                Text(BL("bell_catalog.summary.none"))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(bells.prefix(6))) { bell in
                            Button {
                                presentedBell = bell
                            } label: {
                                BellCardView(bell: bell, layoutMode: .mini)
                                    .frame(width: 148)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .summaryGlassCard()
    }

    private var summaryTagCloudCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(BL("bell_catalog.summary.tag_cloud"))
                .font(.headline)

            if topTags.isEmpty {
                Text(BL("bell_catalog.summary.no_tags"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(Array(topTags.prefix(16).enumerated()), id: \.offset) { _, row in
                        SummaryTagCloudItem(
                            tag: row.0,
                            count: row.1,
                            maxCount: topTags.first?.1 ?? row.1,
                            tint: collection.backgroundStyle.accentColor
                        ) {
                            onSelectSummaryFilter?(.tag(row.0))
                        }
                    }
                }
            }
        }
        .summaryGlassCard()
    }

    private var activeSummaryFilterSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag.fill")
                .foregroundStyle(collection.backgroundStyle.accentColor)

            Text(String.localizedStringWithFormat(BL("bell_catalog.items.filtered_by_tag"), summaryFilter?.title() ?? ""))
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button(BL("common.clear")) {
                onClearSummaryFilter?()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(collection.backgroundStyle.accentColor)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func summaryStatChip(value: String, title: String, filter: BellSummaryFilter) -> some View {
        Button {
            onSelectSummaryFilter?(filter)
        } label: {
            StatChip(value: value, title: title, tint: collection.backgroundStyle.accentColor)
        }
        .buttonStyle(.plain)
    }

    private func matches(bell: BellRecord, summaryFilter: BellSummaryFilter?) -> Bool {
        switch summaryFilter {
        case nil, .all:
            return true
        case .withOrigin:
            return bell.originPlace != nil
        case .missingOrigin:
            return bell.originPlace == nil
        case .withCity:
            return !bell.cityName.isEmpty
        case .withStorage:
            return bell.item.locationID != nil
        case .missingStorage:
            return bell.item.locationID == nil
        case .withNotes:
            return !bell.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .missingNotes:
            return bell.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .withTags:
            return !bell.tags.isEmpty
        case .missingTags:
            return bell.tags.isEmpty
        case .withMaterial:
            return !bell.materialDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .country(let country):
            return bell.countryName.localizedCaseInsensitiveCompare(country) == .orderedSame
        case .material(let material):
            return bell.materialDisplayName.localizedCaseInsensitiveCompare(material) == .orderedSame
        case .tag(let tag):
            return bell.tags.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame })
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(BL("bell_catalog.search.placeholder"), text: $searchText)
                .textInputAutocapitalization(.sentences)
                .padding(14)
                .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    FilterChip(title: BL("bell_catalog.filter.all"), isSelected: selectedCondition == nil, tint: collection.backgroundStyle.accentColor) {
                        selectedCondition = nil
                    }

                    ForEach(ItemCondition.allCases) { condition in
                        FilterChip(title: condition.displayName, isSelected: selectedCondition == condition, tint: collection.backgroundStyle.accentColor) {
                            selectedCondition = condition
                        }
                    }
                }
            }
        }
    }

    private func binding(for bellID: UUID) -> Binding<BellRecord>? {
        guard let index = bellRecords.firstIndex(where: { $0.id == bellID }) else { return nil }
        return $bellRecords[index]
    }

    private func deleteBell(_ bellID: UUID) {
        repository.deleteBellRecord(bellID: bellID)
        bellRecords.removeAll { $0.id == bellID }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onEnded { value in
                if value.magnification > 1.12 {
                    zoomIn()
                } else if value.magnification < 0.92 {
                    zoomOut()
                }
            }
    }

    private func zoomIn() {
        guard let nextMode = BellGridLayoutMode(rawValue: layoutMode.rawValue + 1) else { return }
        layoutMode = nextMode
    }

    private func zoomOut() {
        guard let previousMode = BellGridLayoutMode(rawValue: layoutMode.rawValue - 1) else { return }
        layoutMode = previousMode
    }

    private func sorted(_ bells: [BellRecord]) -> [BellRecord] {
        bells.sorted { lhs, rhs in
            switch sortOption {
            case .title:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .origin:
                let leftOrigin = lhs.placeDisplayName
                let rightOrigin = rhs.placeDisplayName

                if leftOrigin.localizedCaseInsensitiveCompare(rightOrigin) == .orderedSame {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }

                return leftOrigin.localizedCaseInsensitiveCompare(rightOrigin) == .orderedAscending
            case .yearNewest:
                switch (lhs.acquiredYear, rhs.acquiredYear) {
                case let (left?, right?) where left != right:
                    return left > right
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                default:
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            case .yearOldest:
                switch (lhs.acquiredYear, rhs.acquiredYear) {
                case let (left?, right?) where left != right:
                    return left < right
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                default:
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
        }
    }
}

struct BellEditorView: View {
    let collection: CollectionSummary
    let repository: any CatalogRepository
    let onSave: (BellRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var condition: ItemCondition = .good
    @State private var acquisitionMethod: AcquisitionMethod = .bought
    @State private var material: BellMaterial = .brass
    @State private var customMaterialName = ""
    @State private var selectedOriginPlace: Place?
    @State private var selectedLocationID: UUID?
    @State private var tagInput = ""
    @State private var tags: [String] = []
    @State private var mediaAssets: [MediaAsset] = []
    @State private var selectedAcquiredYearOption = BL("editor.acquired_year.none")
    private let existingBellID: UUID?
    private let editorItemID: UUID

    private let acquiredYearOptions = [BL("editor.acquired_year.none")] + Array(1900...Calendar.current.component(.year, from: .now)).reversed().map(String.init)

    private var availableLocations: [Location] {
        repository.fetchLocations(in: collection.homeID)
    }

    private var availablePlaces: [Place] {
        let places = repository
            .fetchBellRecords(for: collection.id)
            .compactMap(\.originPlace)

        return Array(Set(places)).sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private var locationPathByID: [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: availableLocations.map { location in
                (location.id, locationPath(for: location))
            }
        )
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        collection: CollectionSummary,
        repository: any CatalogRepository,
        bell: BellRecord? = nil,
        initialMediaAssets: [MediaAsset] = [],
        onSave: @escaping (BellRecord) -> Void
    ) {
        self.collection = collection
        self.repository = repository
        self.onSave = onSave
        self.existingBellID = bell?.id
        self.editorItemID = bell?.id ?? UUID()
        _title = State(initialValue: bell?.title ?? "")
        _notes = State(initialValue: bell?.notes ?? "")
        _condition = State(initialValue: bell?.condition ?? .good)
        _acquisitionMethod = State(initialValue: bell?.acquisitionMethod ?? .bought)
        _material = State(initialValue: bell?.details.material ?? .brass)
        _customMaterialName = State(initialValue: bell?.details.customMaterialName ?? "")
        _selectedOriginPlace = State(initialValue: bell?.originPlace)
        _selectedLocationID = State(initialValue: bell?.item.locationID)
        _tags = State(initialValue: bell?.tags ?? [])
        _mediaAssets = State(initialValue: bell?.mediaAssets ?? initialMediaAssets)
        _selectedAcquiredYearOption = State(initialValue: bell?.acquiredYear.map(String.init) ?? BL("editor.acquired_year.none"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(BL("editor.media")) {
                    MediaSection(
                        itemID: editorItemID,
                        mediaAssets: $mediaAssets
                    )
                }

                Section(BL("editor.description")) {
                    TextField(BL("editor.short_description"), text: $title)
                    TextField(BL("editor.note_history"), text: $notes, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                }

                Section(BL("editor.acquisition_details")) {
                    YearPickerField(
                        title: BL("editor.acquired_year"),
                        selection: $selectedAcquiredYearOption,
                        options: acquiredYearOptions
                    )

                    EnumSelectionRow(
                        title: BL("editor.acquisition"),
                        selectedLabel: acquisitionMethod.displayName,
                        options: AcquisitionMethod.allCases,
                        selection: $acquisitionMethod,
                        optionTitle: \.displayName
                    )
                }

                Section(BL("editor.attributes")) {
                    EnumSelectionRow(
                        title: BL("editor.condition"),
                        selectedLabel: condition.displayName,
                        options: ItemCondition.allCases,
                        selection: $condition,
                        optionTitle: \.displayName
                    )

                    EnumSelectionRow(
                        title: BL("editor.material"),
                        selectedLabel: material.displayName,
                        options: BellMaterial.allCases,
                        selection: $material,
                        optionTitle: \.displayName
                    )

                    if material == .other {
                        TextField(BL("editor.material.custom"), text: $customMaterialName)
                    }
                }

                Section(BL("editor.storage")) {
                    LocationPickerField(
                        title: BL("editor.location"),
                        selectedLabel: selectedLocationLabel,
                        locations: availableLocations,
                        selectedLocationID: $selectedLocationID
                    )
                }

                Section(BL("editor.additional_details")) {
                    PlacePickerField(
                        title: BL("editor.origin"),
                        selectedLabel: selectedOriginLabel,
                        places: availablePlaces,
                        selectedPlace: $selectedOriginPlace
                    )
                }

                Section(BL("editor.tags")) {
                    TagEditorSection(
                        tagInput: $tagInput,
                        tags: $tags
                    )
                }
            }
            .navigationTitle(existingBellID == nil ? BL("editor.bell.add") : BL("editor.bell.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(BL("common.cancel"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveBell()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave)
                    .accessibilityLabel(BL("common.save"))
                }
            }
        }
    }

    private func saveBell() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustomMaterial = customMaterialName.trimmingCharacters(in: .whitespacesAndNewlines)

        let itemID = editorItemID
        let location = availableLocations.first(where: { $0.id == selectedLocationID })
        let originPlace = selectedOriginPlace
        let normalizedMediaAssets = mediaAssets.enumerated().map { index, asset in
            MediaAsset(
                id: asset.id,
                itemID: itemID,
                kind: asset.kind,
                localIdentifier: asset.localIdentifier,
                displayName: asset.displayName,
                sortOrder: index
            )
        }

        let newBell = BellRecord(
            item: Item(
                id: itemID,
                collectionID: collection.id,
                locationID: selectedLocationID,
                title: trimmedTitle,
                notes: trimmedNotes,
                acquiredYear: selectedAcquiredYearOption == BL("editor.acquired_year.none") ? nil : Int(selectedAcquiredYearOption),
                condition: condition,
                acquisitionMethod: acquisitionMethod
            ),
            details: BellDetails(
                itemID: itemID,
                originPlaceID: selectedOriginPlace?.id,
                material: material,
                customMaterialName: material == .other ? trimmedCustomMaterial : nil
            ),
            originPlace: originPlace,
            storageLocation: location,
            storagePath: location.map(locationPath(for:)) ?? "Unassigned",
            mediaAssets: normalizedMediaAssets,
            createdBy: "You",
            tags: tags
        )

        onSave(newBell)
        dismiss()
    }

    private var selectedOriginLabel: String {
        selectedOriginPlace?.displayName ?? BL("common.unassigned")
    }

    private var selectedLocationLabel: String {
        guard let selectedLocationID, let path = locationPathByID[selectedLocationID] else {
            return BL("common.unassigned")
        }

        return path
    }

    private func locationPath(for location: Location) -> String {
        let locationsByID = Dictionary(uniqueKeysWithValues: availableLocations.map { ($0.id, $0) })
        var parts = [location.name]
        var currentParentID = location.parentLocationID

        while let parentID = currentParentID, let parent = locationsByID[parentID] {
            parts.insert(parent.name, at: 0)
            currentParentID = parent.parentLocationID
        }

        return parts.joined(separator: " / ")
    }
}

struct BellCardView: View {
    let bell: BellRecord
    let layoutMode: BellGridLayoutMode

    @ViewBuilder
    var body: some View {
        if layoutMode == .wide {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.clear)
                .overlay {
                    cardBackground
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(hasCoverPhoto ? 0.34 : 0),
                            Color.black.opacity(hasCoverPhoto ? 0.10 : 0),
                            Color.black.opacity(hasCoverPhoto ? 0.08 : 0)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bell.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(hasCoverPhoto ? .white : .primary)
                            .lineLimit(2)

                        Text(bell.placeDisplayName)
                            .font(.caption)
                            .foregroundStyle(hasCoverPhoto ? .white.opacity(0.86) : .secondary)
                            .lineLimit(2)
                    }
                    .padding(layoutMode.cardPadding)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 8) {
                        CompactMetaChip(
                            label: bell.materialDisplayName,
                            systemImage: "shippingbox.fill",
                            bright: hasCoverPhoto
                        )

                        if let acquiredYear = bell.acquiredYear {
                            CompactMetaChip(
                                label: String(acquiredYear),
                                systemImage: "calendar",
                                bright: hasCoverPhoto
                            )
                        }
                    }
                    .padding(layoutMode.cardPadding)
                }
                .frame(maxWidth: .infinity)
                .frame(height: layoutMode.cardHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
        } else {
            ZStack(alignment: .topLeading) {
                cardBackground

                LinearGradient(
                    colors: [
                        Color.black.opacity(hasCoverPhoto ? 0.34 : 0),
                        Color.black.opacity(hasCoverPhoto ? 0.10 : 0),
                        Color.black.opacity(hasCoverPhoto ? 0.08 : 0)
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                cardContent
                    .padding(layoutMode.cardPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: layoutMode.cardHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        switch layoutMode {
        case .covers:
            if !hasCoverPhoto {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bell.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(bell.placeDisplayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

        case .mini:
            VStack(alignment: .leading, spacing: 4) {
                Spacer()

                Text(bell.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(2)

                Text(bell.placeDisplayName)
                    .font(.caption2)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)

                if let acquiredYear = bell.acquiredYear {
                    Text(String(acquiredYear))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(hasCoverPhoto ? .white.opacity(0.9) : .secondary)
                }
            }

        case .compact:
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bell.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(2)

                    Text(bell.placeDisplayName)
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(2)
                }

                Spacer()

                if let acquiredYear = bell.acquiredYear {
                    CompactMetaChip(
                        label: String(acquiredYear),
                        systemImage: "calendar",
                        bright: hasCoverPhoto
                    )
                }
            }

        case .wide:
            EmptyView()

        case .showcase:
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bell.title)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(3)

                    Text(bell.placeDisplayName)
                        .font(.body)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(2)
                }

                Spacer()

                HStack(spacing: 8) {
                    CompactMetaChip(
                        label: bell.materialDisplayName,
                        systemImage: "shippingbox.fill",
                        bright: hasCoverPhoto
                    )

                    if let acquiredYear = bell.acquiredYear {
                        CompactMetaChip(
                            label: String(acquiredYear),
                            systemImage: "calendar",
                            bright: hasCoverPhoto
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if let coverPhotoAsset {
            BellCardCoverBackground(asset: coverPhotoAsset)
        } else {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.88),
                    Color.white.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var coverPhotoAsset: MediaAsset? {
        bell.mediaAssets
            .filter({ $0.kind == .photo })
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .first
    }

    private var hasCoverPhoto: Bool {
        coverPhotoAsset != nil
    }

    private var primaryTextColor: Color {
        hasCoverPhoto ? .white : .primary
    }

    private var secondaryTextColor: Color {
        hasCoverPhoto ? .white.opacity(0.86) : .secondary
    }
}

struct BellCardCoverBackground: View {
    let asset: MediaAsset
    private let mediaStore = LocalMediaFileStore.shared
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.88),
                        Color.white.opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .task(id: asset.localIdentifier) {
            loadImage()
        }
    }

    private func loadImage() {
        guard image == nil,
              let url = mediaStore.fileURL(for: asset.localIdentifier),
              let loadedImage = UIImage(contentsOfFile: url.path) else {
            return
        }

        image = loadedImage
    }
}

private struct CompactMetaChip: View {
    let label: String
    let systemImage: String
    let bright: Bool

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                bright
                    ? Color.white.opacity(0.16)
                    : Color.black.opacity(0.04),
                in: Capsule()
            )
            .foregroundStyle(bright ? .white : .secondary)
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var tint: Color = Color(red: 0.53, green: 0.31, blue: 0.14)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    isSelected
                        ? tint
                        : Color.white.opacity(0.72),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }
}

private struct SummaryPill: View {
    let systemImage: String
    let title: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(.primary)
    }
}

private struct SummaryTagCloudItem: View {
    let tag: String
    let count: Int
    let maxCount: Int
    let tint: Color
    let action: () -> Void

    private var emphasis: Double {
        guard maxCount > 1 else { return 1.0 }
        return 0.45 + (Double(count - 1) / Double(maxCount - 1)) * 0.55
    }

    private var font: Font {
        switch emphasis {
        case 0.9...:
            return .headline.weight(.bold)
        case 0.75...:
            return .subheadline.weight(.semibold)
        case 0.6...:
            return .footnote.weight(.semibold)
        default:
            return .caption.weight(.medium)
        }
    }

    var body: some View {
        Button(action: action) {
            Text(tag)
                .font(font)
                .foregroundStyle(tint.opacity(emphasis))
                .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

private struct SummaryCoverageRow: View {
    let title: String
    let value: Int
    let total: Int
    let tint: Color
    let action: () -> Void

    private var progress: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(value) / CGFloat(total)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text("\(value)/\(total)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.black.opacity(0.06))

                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 8)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SummaryBreakdownRow: View {
    let title: String
    let value: Int
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer()

                Text("\(value)")
                    .font(.subheadline.weight(.bold))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(tint.opacity(0.14), in: Capsule())
            }
        }
        .buttonStyle(.plain)
    }
}

private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX > 0, currentX + size.width > maxWidth {
                currentX = 0
                currentY += rowHeight + verticalSpacing
                rowHeight = 0
            }

            rowHeight = max(rowHeight, size.height)
            currentX += size.width + horizontalSpacing
        }

        return CGSize(width: maxWidth.isFinite ? maxWidth : currentX, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + verticalSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            currentX += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct StatChip: View {
    let value: String
    let title: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SummaryGlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.32), lineWidth: 1)
            )
    }
}

private extension View {
    func summaryGlassCard() -> some View {
        modifier(SummaryGlassCardModifier())
    }
}

struct BellCatalogView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            let repository = InMemoryCatalogRepository()
            let collection = repository.fetchCollections().first { $0.kind == .bells }!
            BellCatalogView(
                collection: collection,
                repository: repository,
                collaborators: repository.fetchCollaborators(for: collection.id),
                mode: .summary
            )
        }
    }
}

private struct BellGridDetailSheetContainer: View {
    @State var bell: BellRecord
    let repository: any CatalogRepository

    var body: some View {
        NavigationStack {
            BellDetailView(bell: $bell, repository: repository)
        }
        .presentationBackground(.clear)
    }
}
