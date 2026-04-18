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

    var localizationKey: String {
        switch self {
        case .bells:
            return "collection.count.bells"
        case .materials:
            return "collection.count.materials"
        case .countries:
            return "collection.count.countries"
        case .cities:
            return "collection.count.cities"
        case .members:
            return "collection.count.members"
        }
    }
}

private func localizedCount(_ count: Int, kind: SummaryCountKind) -> String {
    String.localizedStringWithFormat(
        NSLocalizedString(kind.localizationKey, comment: ""),
        count
    )
}

enum BellOrderMode: String, CaseIterable, Hashable {
    case title
    case newestFirst
    case oldestFirst
    case geography
    case acquisitionYear
    case storage

    var title: String {
        switch self {
        case .title:
            return BL("bell_catalog.sort.title")
        case .newestFirst:
            return BL("bell_catalog.sort.newest_first")
        case .oldestFirst:
            return BL("bell_catalog.sort.oldest_first")
        case .geography:
            return BL("bell_catalog.group.geography")
        case .acquisitionYear:
            return BL("bell_catalog.group.acquisition_year")
        case .storage:
            return BL("bell_catalog.group.storage")
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

struct BellCatalogView: View {
    let repository: any CatalogRepository
    let collaborators: [Collaborator]
    let collection: CollectionSummary
    let mode: BellCatalogMode
    let orderMode: BellOrderMode
    let summaryFilter: BellSummaryFilter?
    let onSelectSummaryFilter: ((BellSummaryFilter) -> Void)?
    let onClearSummaryFilter: (() -> Void)?
    let externalSearchText: String?

    @State private var viewModel: BellCatalogViewModel
    @State private var selectedCondition: ItemCondition?
    @State private var layoutMode: BellGridLayoutMode = .compact
    @State private var presentedBell: BellRecord?
    @State private var activeJumpPopoverSectionID: String?

    init(
        collection: CollectionSummary,
        repository: any CatalogRepository,
        collaborators: [Collaborator],
        mode: BellCatalogMode,
        orderMode: BellOrderMode = .title,
        summaryFilter: BellSummaryFilter? = nil,
        onSelectSummaryFilter: ((BellSummaryFilter) -> Void)? = nil,
        onClearSummaryFilter: (() -> Void)? = nil,
        externalSearchText: String? = nil
    ) {
        self.repository = repository
        self.collaborators = collaborators
        self.collection = collection
        self.mode = mode
        self.orderMode = orderMode
        self.summaryFilter = summaryFilter
        self.onSelectSummaryFilter = onSelectSummaryFilter
        self.onClearSummaryFilter = onClearSummaryFilter
        self.externalSearchText = externalSearchText
        let initialBellRecords = repository.fetchBellRecords(for: collection.id)
        let initialLocationsByID = Dictionary(
            uniqueKeysWithValues: repository.fetchLocations(in: collection.homeID).map { ($0.id, $0) }
        )
        let initialHomeName = repository.fetchHomes().first(where: { $0.id == collection.homeID })?.name ?? BL("common.unknown")
        _viewModel = State(
            initialValue: BellCatalogViewModel(
                bellRecords: initialBellRecords,
                orderMode: orderMode,
                summaryFilter: summaryFilter,
                searchText: externalSearchText ?? "",
                locationsByID: initialLocationsByID,
                homeName: initialHomeName
            )
        )
    }

    private var effectiveSearchText: String {
        externalSearchText ?? ""
    }

    private var themeColors: [Color] {
        collection.backgroundStyle.screenColors
    }

    private var usesGroupedSectionsInCurrentMode: Bool {
        mode == .items && viewModel.usesGroupedSections
    }

    private var locationsByID: [UUID: Location] {
        Dictionary(
            uniqueKeysWithValues: repository.fetchLocations(in: collection.homeID).map { ($0.id, $0) }
        )
    }


    private func gridColumns(forScreenWidth screenWidth: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.fixed(layoutMode.cardWidth(forScreenWidth: screenWidth)), spacing: layoutMode.spacing, alignment: .top),
            count: layoutMode.columnCount
        )
    }

    @ViewBuilder
    var body: some View {
        GeometryReader { proxy in
            Group {
                switch mode {
                case .summary:
                    summaryContent(screenWidth: proxy.size.width)
                case .items:
                    bellGridContent(
                        bells: viewModel.filteredItemsBells,
                        showsSearchControls: false,
                        emptyTitle: LocalizedStringKey(BL("bell_catalog.empty.title")),
                        emptyDescription: LocalizedStringKey(BL("bell_catalog.empty.description")),
                        screenWidth: proxy.size.width
                    )
                case .search:
                    bellGridContent(
                        bells: viewModel.filteredBells,
                        showsSearchControls: true,
                        emptyTitle: LocalizedStringKey(BL("bell_catalog.search.empty.title")),
                        emptyDescription: LocalizedStringKey(BL("bell_catalog.search.empty.description")),
                        screenWidth: proxy.size.width
                    )
                }
            }
        }
        .sheet(item: $presentedBell, onDismiss: {
            viewModel.refreshBellRecords(from: repository, collectionID: collection.id)
        }) { bell in
            BellGridDetailSheetContainer(bell: bell, repository: repository)
                .presentationDragIndicator(.visible)
        }
        .onAppear(perform: syncViewModelContext)
        .onChange(of: orderMode) { _, _ in
            syncViewModelContext()
        }
        .onChange(of: summaryFilter) { _, _ in
            syncViewModelContext()
        }
        .onChange(of: externalSearchText) { _, _ in
            syncViewModelContext()
        }
        .onChange(of: selectedCondition) { _, value in
            viewModel.selectedCondition = value
        }
    }

    private func summaryContent(screenWidth: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryOverviewCard
                summarySnapshotCard
                summaryCoverageCard
                summaryBreakdownCard(
                    title: BL("bell_catalog.summary.top_countries"),
                    emptyTitle: BL("bell_catalog.summary.no_origin_data"),
                    rows: Array(viewModel.topCountries.prefix(4))
                )
                summaryBreakdownCard(
                    title: BL("bell_catalog.summary.top_materials"),
                    emptyTitle: BL("bell_catalog.summary.no_material_data"),
                    rows: Array(viewModel.topMaterials.prefix(4))
                )
                summaryTagCloudCard
                summaryRecentBells(screenWidth: screenWidth)
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
        emptyDescription: LocalizedStringKey,
        screenWidth: CGFloat
    ) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: usesGroupedSectionsInCurrentMode ? [.sectionHeaders] : []) {
                    Color.clear
                        .frame(height: 0)
                        .id("bell-grid-top")

                    if !showsSearchControls, let summaryFilter, summaryFilter != .all {
                        activeSummaryFilterSection
                    }

                    if showsSearchControls {
                        searchFiltersSection
                    }

                    if bells.isEmpty {
                        emptyBellsGridState(title: emptyTitle, description: emptyDescription)
                    } else if usesGroupedSectionsInCurrentMode {
                        groupedBellSectionsContent(
                            sections: viewModel.groupedSections(from: bells),
                            screenWidth: screenWidth,
                            scrollProxy: scrollProxy
                        )
                    } else {
                        LazyVGrid(columns: gridColumns(forScreenWidth: screenWidth), spacing: layoutMode.spacing) {
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
                .animation(.snappy(duration: 0.24), value: orderMode)
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
            .overlay(alignment: .trailing) {
                if orderMode == .geography && usesGroupedSectionsInCurrentMode {
                    geographyJumpIndex { sectionID in
                        withAnimation(.snappy(duration: 0.24)) {
                            scrollProxy.scrollTo(sectionID, anchor: .top)
                        }
                    }
                    .padding(.trailing, 6)
                }
            }
            .onChange(of: orderMode) { _, _ in
                activeJumpPopoverSectionID = nil
                withAnimation(.snappy(duration: 0.24)) {
                    scrollProxy.scrollTo("bell-grid-top", anchor: .top)
                }
            }
        }
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
                        title: localizedCount(collection.collaboratorCount, kind: .members),
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
                summaryStatChip(value: "\(viewModel.bells.count)", title: localizedCount(viewModel.bells.count, kind: .bells), filter: .all)
                summaryStatChip(value: "\(viewModel.materialCount)", title: localizedCount(viewModel.materialCount, kind: .materials), filter: .withMaterial)
                summaryStatChip(value: "\(viewModel.countryCount)", title: localizedCount(viewModel.countryCount, kind: .countries), filter: .withOrigin)
                summaryStatChip(value: "\(viewModel.cityCount)", title: localizedCount(viewModel.cityCount, kind: .cities), filter: .withCity)
            }
        }
        .summaryGlassCard()
    }

    private var summaryCoverageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(BL("bell_catalog.summary.coverage"))
                .font(.headline)

            SummaryCoverageRow(title: BL("bell_catalog.summary.with_origin"), value: viewModel.bellsWithOriginCount, total: viewModel.bells.count, tint: collection.backgroundStyle.accentColor) {
                onSelectSummaryFilter?(.missingOrigin)
            }
            SummaryCoverageRow(title: BL("bell_catalog.summary.with_storage"), value: viewModel.bellsWithStorageCount, total: viewModel.bells.count, tint: collection.backgroundStyle.accentColor) {
                onSelectSummaryFilter?(.missingStorage)
            }
            SummaryCoverageRow(title: BL("bell_catalog.summary.with_notes"), value: viewModel.bellsWithNotesCount, total: viewModel.bells.count, tint: collection.backgroundStyle.accentColor) {
                onSelectSummaryFilter?(.missingNotes)
            }
            SummaryCoverageRow(title: BL("bell_catalog.summary.with_tags"), value: viewModel.bellsWithTagsCount, total: viewModel.bells.count, tint: collection.backgroundStyle.accentColor) {
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

    private func summaryRecentBells(screenWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(BL("bell_catalog.summary.recent"))
                .font(.headline)

            if viewModel.bells.isEmpty {
                Text(BL("bell_catalog.summary.none"))
                    .foregroundStyle(.secondary)
            } else {
                BellCardStripView(
                    bells: viewModel.recentBells,
                    layoutMode: .mini,
                    screenWidth: screenWidth
                ) { bell in
                    presentedBell = bell
                }
            }
        }
        .summaryGlassCard()
    }

    private var summaryTagCloudCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(BL("bell_catalog.summary.tag_cloud"))
                .font(.headline)

            if viewModel.topTags.isEmpty {
                Text(BL("bell_catalog.summary.no_tags"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(Array(viewModel.topTags.prefix(16).enumerated()), id: \.offset) { _, row in
                        SummaryTagCloudItem(
                            tag: row.0,
                            count: row.1,
                            maxCount: viewModel.topTags.first?.1 ?? row.1,
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

    private var searchFiltersSection: some View {
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

    private func binding(for bellID: UUID) -> Binding<BellRecord>? {
        guard let index = viewModel.bellRecords.firstIndex(where: { $0.id == bellID }) else { return nil }
        return $viewModel.bellRecords[index]
    }

    @ViewBuilder
    private func groupedBellSectionsContent(
        sections: [BellGroupedSection],
        screenWidth: CGFloat,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        ForEach(sections) { section in
            Section {
                if orderMode == .storage {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(section.cabinetGroups) { cabinetGroup in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(cabinetGroup.title)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)

                                LazyVGrid(columns: gridColumns(forScreenWidth: screenWidth), spacing: layoutMode.spacing) {
                                    ForEach(cabinetGroup.bells) { bell in
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
                    }
                } else {
                    LazyVGrid(columns: gridColumns(forScreenWidth: screenWidth), spacing: layoutMode.spacing) {
                        ForEach(section.bells) { bell in
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
            } header: {
                BellGroupedSectionHeader(
                    title: section.title,
                    tint: collection.backgroundStyle.accentColor,
                    isJumpButton: orderMode == .acquisitionYear || orderMode == .storage,
                    action: {
                        activeJumpPopoverSectionID = section.id
                    }
                )
                .id(section.id)
                .popover(
                    isPresented: Binding(
                        get: { activeJumpPopoverSectionID == section.id && (orderMode == .acquisitionYear || orderMode == .storage) },
                        set: { isPresented in
                            if !isPresented {
                                activeJumpPopoverSectionID = nil
                            }
                        }
                    )
                ) {
                    BellGroupingJumpPopover(
                        titles: sections.map(\.jumpTitle),
                        onSelect: { title in
                            guard let targetSection = sections.first(where: { $0.jumpTitle == title }) else { return }
                            activeJumpPopoverSectionID = nil
                            withAnimation(.snappy(duration: 0.24)) {
                                scrollProxy.scrollTo(targetSection.id, anchor: .top)
                            }
                        }
                    )
                }
            }
        }
    }

    private func geographyJumpIndex(onSelect: @escaping (String) -> Void) -> some View {
        return VStack(spacing: 4) {
            ForEach(viewModel.geographyIndexEntries) { entry in
                Button(entry.title) {
                    onSelect(entry.targetSectionID)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
    }

    private func deleteBell(_ bellID: UUID) {
        repository.deleteBellRecord(bellID: bellID)
        viewModel.bellRecords.removeAll { $0.id == bellID }
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

    private var homeName: String {
        viewModel.homeName
    }

    private func syncViewModelContext() {
        viewModel.updateContext(
            orderMode: orderMode,
            summaryFilter: summaryFilter,
            searchText: effectiveSearchText,
            locationsByID: locationsByID,
            homeName: repository.fetchHomes().first(where: { $0.id == collection.homeID })?.name ?? BL("common.unknown")
        )
    }
}

private struct BellGroupedSectionHeader: View {
    let title: String
    let tint: Color
    let isJumpButton: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isJumpButton {
                Button(action: action) {
                    headerContent
                }
                .buttonStyle(.plain)
            } else {
                headerContent
            }
        }
    }

    private var headerContent: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            if isJumpButton {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)
        }
    }
}

private struct BellGroupingJumpPopover: View {
    let titles: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(titles, id: \.self) { title in
                    Button(title) {
                        onSelect(title)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(12)
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320, minHeight: 160, idealHeight: 280, maxHeight: 360)
    }
}

struct BellEditorView: View {
    enum StartSection: Hashable {
        case storage
    }

    let collection: CollectionSummary
    let repository: any CatalogRepository
    let startSection: StartSection?
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
    @State private var highlightedSection: StartSection?
    @StateObject private var photoAnalysis = BellPhotoAnalysisController()
    private let existingBellID: UUID?
    private let existingCreatedAt: Date?
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
        startSection: StartSection? = nil,
        onSave: @escaping (BellRecord) -> Void
    ) {
        self.collection = collection
        self.repository = repository
        self.startSection = startSection
        self.onSave = onSave
        self.existingBellID = bell?.id
        self.existingCreatedAt = bell?.createdAt
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
            ScrollViewReader { scrollProxy in
                Form {
                    Section(BL("editor.media")) {
                        MediaSection(
                            itemID: editorItemID,
                            mediaAssets: $mediaAssets
                        )
                    }

                    if photoAnalysis.hasSuggestions {
                        Section(BL("editor.photo_analysis.section")) {
                            if photoAnalysis.isAnalyzing {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text(BL("editor.photo_analysis.analyzing"))
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                if !photoAnalysis.result.tags.isEmpty {
                                    PhotoAnalysisTagCloud(tags: photoAnalysis.result.tags)
                                }

                                if !photoAnalysis.result.recognizedText.isEmpty {
                                    PhotoRecognizedTextBlock(textFeatures: photoAnalysis.result.recognizedText)
                                }

                                if let titleSuggestion = photoAnalysis.result.title {
                                    PhotoSuggestionRow(
                                        title: BL("editor.photo_analysis.title"),
                                        suggestedValue: titleSuggestion.value,
                                        confidence: titleSuggestion.confidence,
                                        onAccept: {
                                            title = titleSuggestion.value
                                            photoAnalysis.dismiss(.title)
                                        },
                                        onReject: {
                                            photoAnalysis.dismiss(.title)
                                        }
                                    )
                                }

                                if let notesSuggestion = photoAnalysis.result.notes {
                                    PhotoSuggestionRow(
                                        title: BL("editor.photo_analysis.notes"),
                                        suggestedValue: notesSuggestion.value,
                                        confidence: notesSuggestion.confidence,
                                        onAccept: {
                                            notes = notesSuggestion.value
                                            photoAnalysis.dismiss(.notes)
                                        },
                                        onReject: {
                                            photoAnalysis.dismiss(.notes)
                                        }
                                    )
                                }

                                if let materialSuggestion = photoAnalysis.result.material {
                                    PhotoSuggestionRow(
                                        title: BL("editor.photo_analysis.material"),
                                        suggestedValue: materialSuggestionLabel(materialSuggestion),
                                        confidence: materialSuggestion.confidence,
                                        onAccept: {
                                            material = materialSuggestion.value
                                            if materialSuggestion.value == .other {
                                                customMaterialName = photoAnalysis.result.customMaterialName?.value ?? ""
                                                photoAnalysis.dismiss(.customMaterialName)
                                            } else {
                                                customMaterialName = ""
                                            }
                                            photoAnalysis.dismiss(.material)
                                        },
                                        onReject: {
                                            photoAnalysis.dismiss(.material)
                                            photoAnalysis.dismiss(.customMaterialName)
                                        }
                                    )
                                }

                                if let conditionSuggestion = photoAnalysis.result.condition {
                                    PhotoSuggestionRow(
                                        title: BL("editor.photo_analysis.condition"),
                                        suggestedValue: conditionSuggestion.value.displayName,
                                        confidence: conditionSuggestion.confidence,
                                        onAccept: {
                                            condition = conditionSuggestion.value
                                            photoAnalysis.dismiss(.condition)
                                        },
                                        onReject: {
                                            photoAnalysis.dismiss(.condition)
                                        }
                                    )
                                }

                                if !photoAnalysis.result.suggestedTags.isEmpty {
                                    PhotoSuggestedTagsRow(
                                        title: BL("editor.photo_analysis.tags"),
                                        suggestions: photoAnalysis.result.suggestedTags,
                                        onAcceptAll: {
                                            let newValues = photoAnalysis.result.suggestedTags.map(\.value)
                                            for value in newValues where !tags.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
                                                tags.append(value)
                                            }
                                            photoAnalysis.dismiss(.suggestedTags)
                                        },
                                        onReject: {
                                            photoAnalysis.dismiss(.suggestedTags)
                                        }
                                    )
                                }
                            }
                        }
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
                    .id(StartSection.storage)
                    .listRowBackground(sectionBackground(for: .storage))

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
                .task {
                    guard let startSection else { return }
                    highlightedSection = startSection
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation(.snappy(duration: 0.28)) {
                        scrollProxy.scrollTo(startSection, anchor: .top)
                    }
                    try? await Task.sleep(for: .seconds(1.2))
                    if highlightedSection == startSection {
                        withAnimation(.easeOut(duration: 0.35)) {
                            highlightedSection = nil
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionBackground(for section: StartSection) -> some View {
        if highlightedSection == section {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(collection.backgroundStyle.accentColor.opacity(0.10))
        } else {
            Color.clear
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
                createdAt: existingCreatedAt ?? .now,
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
            storagePath: location.map(locationPath(for:)) ?? BL("common.unassigned"),
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

    private func materialSuggestionLabel(_ suggestion: SuggestedFieldValue<BellMaterial>) -> String {
        if suggestion.value == .other,
           let customMaterial = photoAnalysis.result.customMaterialName?.value,
           !customMaterial.isEmpty {
            return customMaterial
        }

        return suggestion.value.displayName
    }
}

private struct PhotoSuggestionRow: View {
    let title: String
    let suggestedValue: String
    let confidence: Double
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(confidenceLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(suggestedValue)
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                Button(action: onAccept) {
                    Label(BL("editor.photo_analysis.accept"), systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(action: onReject) {
                    Label(BL("editor.photo_analysis.reject"), systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private var confidenceLabel: String {
        "\(Int((confidence * 100).rounded()))%"
    }
}

private struct PhotoAnalysisTagCloud: View {
    let tags: [NormalizedVisionTag]

    var body: some View {
        TagFlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag.tag.rawValue)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.thinMaterial, in: Capsule())
            }
        }
    }
}

private struct PhotoRecognizedTextBlock: View {
    let textFeatures: [RecognizedTextFeature]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(BL("editor.photo_analysis.detected_text"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TagFlowLayout(spacing: 8) {
                ForEach(textFeatures, id: \.self) { feature in
                    Text(feature.text)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.thinMaterial, in: Capsule())
                }
            }
        }
    }
}

private struct PhotoSuggestedTagsRow: View {
    let title: String
    let suggestions: [SuggestedFieldValue<String>]
    let onAcceptAll: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            TagFlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.value) { suggestion in
                    Text(suggestion.value)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.thinMaterial, in: Capsule())
                }
            }

            HStack(spacing: 10) {
                Button(action: onAcceptAll) {
                    Label(BL("editor.photo_analysis.accept"), systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(action: onReject) {
                    Label(BL("editor.photo_analysis.reject"), systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
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
