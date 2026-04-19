import SwiftUI
import UIKit

private enum SummaryCountKind {
    case bells
    case materials
    case countries
    case cities
    case members

    var resource: LocalizedStringResource {
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
        String(localized: kind.resource),
        count
    )
}

private enum BellCatalogCoordinateSpace {
    static let pinchGrid = "bellCatalogPinchGrid"
}

private struct BellCardFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private extension CGPoint {
    func distanceSquared(to point: CGPoint) -> CGFloat {
        let dx = x - point.x
        let dy = y - point.y
        return (dx * dx) + (dy * dy)
    }
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
            return String(localized: "bell_catalog.sort.title")
        case .newestFirst:
            return String(localized: "bell_catalog.sort.newest_first")
        case .oldestFirst:
            return String(localized: "bell_catalog.sort.oldest_first")
        case .geography:
            return String(localized: "bell_catalog.group.geography")
        case .acquisitionYear:
            return String(localized: "bell_catalog.group.acquisition_year")
        case .storage:
            return String(localized: "bell_catalog.group.storage")
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
            return String(localized: "bell_catalog.filter_summary.all")
        case .withOrigin:
            return String(localized: "bell_catalog.summary.with_origin")
        case .missingOrigin:
            return String(localized: "bell_catalog.filter_summary.missing_origin")
        case .withCity:
            return String(localized: "bell_catalog.filter_summary.with_city")
        case .withStorage:
            return String(localized: "bell_catalog.summary.with_storage")
        case .missingStorage:
            return String(localized: "bell_catalog.filter_summary.missing_storage")
        case .withNotes:
            return String(localized: "bell_catalog.summary.with_notes")
        case .missingNotes:
            return String(localized: "bell_catalog.filter_summary.missing_notes")
        case .withTags:
            return String(localized: "bell_catalog.summary.with_tags")
        case .missingTags:
            return String(localized: "bell_catalog.filter_summary.missing_tags")
        case .withMaterial:
            return String(localized: "bell_catalog.filter_summary.with_material")
        case .country(let value), .material(let value), .tag(let value):
            return value
        }
    }
}

struct BellCatalogView: View {
    private enum LayoutThresholdDirection {
        case zoomIn
        case zoomOut
    }

    let repository: any CatalogRepository
    let collaborators: [Collaborator]
    let collection: CollectionSummary
    let mode: BellCatalogMode
    let orderMode: BellOrderMode
    let summaryFilter: BellSummaryFilter?
    let onSelectSummaryFilter: ((BellSummaryFilter) -> Void)?
    let onClearSummaryFilter: (() -> Void)?
    let externalSearchText: String?

    @Binding var layoutMode: BellGridLayoutMode
    @State private var viewModel: BellCatalogViewModel
    @State private var selectedCondition: ItemCondition?
    @State private var presentedBell: BellRecord?
    @State private var activeJumpPopoverSectionID: String?
    @State private var visualScale: CGFloat = 1
    @State private var layoutFeedbackTrigger: Int = 0
    @State private var activeLayoutThresholdDirection: LayoutThresholdDirection?
    @State private var accumulatedMagnificationDelta: CGFloat = 0
    @State private var lastGestureMagnification: CGFloat?
    @State private var pinchOriginBellID: UUID?
    @State private var pinchNavigatedBell: BellRecord?
    @State private var bellCardFrames: [UUID: CGRect] = [:]
    @Namespace private var bellGridTransitionNamespace
    @Namespace private var bellDetailZoomNamespace

    init(
        collection: CollectionSummary,
        repository: any CatalogRepository,
        collaborators: [Collaborator],
        mode: BellCatalogMode,
        layoutMode: Binding<BellGridLayoutMode> = .constant(.compact),
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
        self._layoutMode = layoutMode
        self.orderMode = orderMode
        self.summaryFilter = summaryFilter
        self.onSelectSummaryFilter = onSelectSummaryFilter
        self.onClearSummaryFilter = onClearSummaryFilter
        self.externalSearchText = externalSearchText
        let initialBellRecords = repository.fetchBellRecords(for: collection.id)
        let initialLocationsByID = Dictionary(
            uniqueKeysWithValues: repository.fetchLocations(in: collection.homeID).map { ($0.id, $0) }
        )
        let initialHomeName = repository.fetchHomes().first(where: { $0.id == collection.homeID })?.name ?? String(localized: "common.unknown")
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

    private var scrollContentBottomInset: CGFloat { 120 }

    private var orderedLayoutModes: [BellGridLayoutMode] {
        [.covers, .mini, .compact, .wide, .showcase]
    }

    private func gridColumns(forScreenWidth screenWidth: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.fixed(layoutMode.cardWidth(forScreenWidth: screenWidth)), spacing: layoutMode.spacing, alignment: .top),
            count: layoutMode.columnCount
        )
    }

    private var layoutMagnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard mode == .items else { return }
                capturePinchOriginBellIfNeeded(at: value.startLocation)
                updateAccumulatedMagnification(with: value.magnification)
                updateLayoutThresholdFeedback(for: value)
                visualScale = clampedVisualScale(for: value.magnification)
            }
            .onEnded { value in
                guard mode == .items else { return }
                let effectiveThreshold = zoomThreshold(forVelocity: value.velocity)
                let finalAccumulatedDelta = accumulatedMagnificationDelta
                let shouldOpenDetailFromPinch = layoutMode == .showcase && !canZoomOut && finalAccumulatedDelta >= effectiveThreshold

                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.84, blendDuration: 0.12)) {
                    activeLayoutThresholdDirection = nil
                    visualScale = 1

                    if shouldOpenDetailFromPinch,
                       let pinchOriginBellID,
                       let bell = displayedItemsBell(withID: pinchOriginBellID) {
                        pinchNavigatedBell = bell
                    } else if finalAccumulatedDelta >= effectiveThreshold {
                        zoomOutLayout()
                    } else if finalAccumulatedDelta <= -effectiveThreshold {
                        zoomInLayout()
                    }
                }

                accumulatedMagnificationDelta = 0
                lastGestureMagnification = nil
                pinchOriginBellID = nil
            }
    }

    private func clampedVisualScale(for magnification: CGFloat) -> CGFloat {
        min(max(magnification, 0.88), 1.16)
    }

    private func updateAccumulatedMagnification(with magnification: CGFloat) {
        let previousMagnification = lastGestureMagnification ?? 1
        accumulatedMagnificationDelta += magnification - previousMagnification
        lastGestureMagnification = magnification
    }

    private func zoomThreshold(forVelocity velocity: CGFloat) -> CGFloat {
        let baseThreshold: CGFloat = 0.12
        let velocityReduction = min(abs(velocity) * 0.015, 0.05)
        return max(0.05, baseThreshold - velocityReduction)
    }

    private func updateLayoutThresholdFeedback(for value: MagnifyGesture.Value) {
        let threshold = zoomThreshold(forVelocity: value.velocity)
        let newDirection: LayoutThresholdDirection?

        if accumulatedMagnificationDelta >= threshold, canZoomOut {
            newDirection = .zoomOut
        } else if accumulatedMagnificationDelta <= -threshold, canZoomIn {
            newDirection = .zoomIn
        } else {
            newDirection = nil
        }

        guard newDirection != activeLayoutThresholdDirection else { return }

        activeLayoutThresholdDirection = newDirection

        if newDirection != nil {
            layoutFeedbackTrigger += 1
        }
    }

    private func capturePinchOriginBellIfNeeded(at location: CGPoint) {
        guard pinchOriginBellID == nil else { return }

        if let exactMatch = bellCardFrames.first(where: { $0.value.contains(location) }) {
            pinchOriginBellID = exactMatch.key
            return
        }

        pinchOriginBellID = bellCardFrames.min { lhs, rhs in
            lhs.value.center.distanceSquared(to: location) < rhs.value.center.distanceSquared(to: location)
        }?.key
    }

    private func displayedItemsBell(withID bellID: UUID) -> BellRecord? {
        viewModel.filteredItemsBells.first(where: { $0.id == bellID })
    }

    private var canZoomIn: Bool {
        guard let currentIndex = orderedLayoutModes.firstIndex(of: layoutMode) else { return false }
        return currentIndex > 0
    }

    private var canZoomOut: Bool {
        guard let currentIndex = orderedLayoutModes.firstIndex(of: layoutMode) else { return false }
        return currentIndex < orderedLayoutModes.count - 1
    }

    private func zoomInLayout() {
        guard let currentIndex = orderedLayoutModes.firstIndex(of: layoutMode), currentIndex > 0 else {
            return
        }

        withAnimation(.snappy(duration: 0.24)) {
            layoutMode = orderedLayoutModes[currentIndex - 1]
        }
    }

    private func zoomOutLayout() {
        guard let currentIndex = orderedLayoutModes.firstIndex(of: layoutMode), currentIndex < orderedLayoutModes.count - 1 else {
            return
        }

        withAnimation(.snappy(duration: 0.24)) {
            layoutMode = orderedLayoutModes[currentIndex + 1]
        }
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
                        emptyTitle: LocalizedStringKey(String(localized: "bell_catalog.empty.title")),
                        emptyDescription: LocalizedStringKey(String(localized: "bell_catalog.empty.description")),
                        screenWidth: proxy.size.width
                    )
                case .search:
                    bellGridContent(
                        bells: viewModel.filteredBells,
                        showsSearchControls: true,
                        emptyTitle: LocalizedStringKey(String(localized: "bell_catalog.search.empty.title")),
                        emptyDescription: LocalizedStringKey(String(localized: "bell_catalog.search.empty.description")),
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
        .navigationDestination(item: $pinchNavigatedBell) { bell in
            BellGridDetailNavigationContainer(bell: bell, repository: repository)
                .navigationTransition(.zoom(sourceID: bell.id, in: bellDetailZoomNamespace))
        }
        .sensoryFeedback(.impact(weight: .light), trigger: layoutFeedbackTrigger)
        .coordinateSpace(name: BellCatalogCoordinateSpace.pinchGrid)
        .onPreferenceChange(BellCardFramePreferenceKey.self) { frames in
            bellCardFrames = frames
        }
        .onAppear(perform: syncViewModelContext)
        .onChange(of: orderMode) { _, _ in
            accumulatedMagnificationDelta = 0
            lastGestureMagnification = nil
            activeLayoutThresholdDirection = nil
            visualScale = 1
            pinchOriginBellID = nil
            syncViewModelContext()
        }
        .onChange(of: summaryFilter) { _, _ in
            accumulatedMagnificationDelta = 0
            lastGestureMagnification = nil
            activeLayoutThresholdDirection = nil
            visualScale = 1
            pinchOriginBellID = nil
            syncViewModelContext()
        }
        .onChange(of: externalSearchText) { _, _ in
            accumulatedMagnificationDelta = 0
            lastGestureMagnification = nil
            activeLayoutThresholdDirection = nil
            visualScale = 1
            pinchOriginBellID = nil
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
                    title: String(localized: "bell_catalog.summary.top_countries"),
                    emptyTitle: String(localized: "bell_catalog.summary.no_origin_data"),
                    rows: Array(viewModel.topCountries.prefix(4))
                )
                summaryBreakdownCard(
                    title: String(localized: "bell_catalog.summary.top_materials"),
                    emptyTitle: String(localized: "bell_catalog.summary.no_material_data"),
                    rows: Array(viewModel.topMaterials.prefix(4))
                )
                summaryTagCloudCard
                summaryRecentBells(screenWidth: screenWidth)
            }
        }
        .contentMargins(.horizontal, nil, for: .scrollContent)
        .contentMargins(.top, nil, for: .scrollContent)
        .contentMargins(.bottom, scrollContentBottomInset, for: .scrollContent)
        .background(
            LinearGradient(
                colors: themeColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private func bellGridContent(
        bells: [BellRecord],
        showsSearchControls: Bool,
        emptyTitle: LocalizedStringKey,
        emptyDescription: LocalizedStringKey,
        screenWidth: CGFloat
    ) -> some View {
        if orderMode == .geography && usesGroupedSectionsInCurrentMode {
            groupedGeographyListContent(
                bells: bells,
                showsSearchControls: showsSearchControls,
                emptyTitle: emptyTitle,
                emptyDescription: emptyDescription,
                screenWidth: screenWidth
            )
        } else {
            standardBellGridContent(
                bells: bells,
                showsSearchControls: showsSearchControls,
                emptyTitle: emptyTitle,
                emptyDescription: emptyDescription,
                screenWidth: screenWidth
            )
        }
    }

    private func standardBellGridContent(
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
                        .scaleEffect(visualScale, anchor: .center)
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
                                    .matchedGeometryEffect(id: bell.id, in: bellGridTransitionNamespace)
                                    .matchedTransitionSource(id: bell.id, in: bellDetailZoomNamespace)
                                    .background {
                                        GeometryReader { proxy in
                                            Color.clear.preference(
                                                key: BellCardFramePreferenceKey.self,
                                                value: [bell.id: proxy.frame(in: .named(BellCatalogCoordinateSpace.pinchGrid))]
                                            )
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .scaleEffect(visualScale, anchor: .center)
                    }
                }
                .animation(.snappy(duration: 0.24), value: layoutMode)
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.12), value: visualScale)
                .animation(.snappy(duration: 0.24), value: orderMode)
            }
            .contentMargins(.horizontal, nil, for: .scrollContent)
            .contentMargins(.top, nil, for: .scrollContent)
            .contentMargins(.bottom, scrollContentBottomInset, for: .scrollContent)
            .background(
                LinearGradient(
                    colors: themeColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .simultaneousGesture(layoutMagnifyGesture)
            .overlay(alignment: .trailing) {
            }
            .onChange(of: orderMode) { _, _ in
                activeJumpPopoverSectionID = nil
                withAnimation(.snappy(duration: 0.24)) {
                    scrollProxy.scrollTo("bell-grid-top", anchor: .top)
                }
            }
        }
    }

    private func groupedGeographyListContent(
        bells: [BellRecord],
        showsSearchControls: Bool,
        emptyTitle: LocalizedStringKey,
        emptyDescription: LocalizedStringKey,
        screenWidth: CGFloat
    ) -> some View {
        let sections = viewModel.groupedSections(from: bells)

        return List {
            if !showsSearchControls, let summaryFilter, summaryFilter != .all {
                Section {
                    activeSummaryFilterSection
                        .listRowInsets(.top, 10)
                        .listRowInsets(.bottom, 6)
                        .listRowBackground(Color.clear)
                }
            }

            if bells.isEmpty {
                Section {
                    emptyBellsGridState(title: emptyTitle, description: emptyDescription)
                        .listRowInsets(.top, nil)
                        .listRowInsets(.bottom, 20)
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(sections) { section in
                    Section {
                        LazyVGrid(columns: gridColumns(forScreenWidth: screenWidth), spacing: layoutMode.spacing) {
                            ForEach(section.bells) { bell in
                                Button {
                                    presentedBell = bell
                                } label: {
                                    BellCardView(
                                        bell: bell,
                                        layoutMode: layoutMode
                                    )
                                    .matchedGeometryEffect(id: bell.id, in: bellGridTransitionNamespace)
                                    .matchedTransitionSource(id: bell.id, in: bellDetailZoomNamespace)
                                    .background {
                                        GeometryReader { proxy in
                                            Color.clear.preference(
                                                key: BellCardFramePreferenceKey.self,
                                                value: [bell.id: proxy.frame(in: .named(BellCatalogCoordinateSpace.pinchGrid))]
                                            )
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .scaleEffect(visualScale, anchor: .center)
                        .padding(.vertical, 8)
                    } header: {
                        BellGroupedSectionHeader(
                            title: section.title,
                            tint: collection.backgroundStyle.accentColor,
                            isJumpButton: false,
                            action: {}
                        )
                        .sectionIndexLabel(section.indexTitle)
                    }
                    .listRowInsets(.top, 0)
                    .listRowInsets(.bottom, 12)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .contentMargins(.horizontal, nil, for: .scrollContent)
        .contentMargins(.top, nil, for: .scrollContent)
        .contentMargins(.bottom, scrollContentBottomInset, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .listSectionIndexVisibility(.visible)
        .background(
            LinearGradient(
                colors: themeColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .simultaneousGesture(layoutMagnifyGesture)
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
            Text(String(localized: "bell_catalog.summary.coverage"))
                .font(.headline)

            SummaryCoverageRow(title: String(localized: "bell_catalog.summary.with_origin"), value: viewModel.bellsWithOriginCount, total: viewModel.bells.count, tint: collection.backgroundStyle.accentColor) {
                onSelectSummaryFilter?(.missingOrigin)
            }
            SummaryCoverageRow(title: String(localized: "bell_catalog.summary.with_storage"), value: viewModel.bellsWithStorageCount, total: viewModel.bells.count, tint: collection.backgroundStyle.accentColor) {
                onSelectSummaryFilter?(.missingStorage)
            }
            SummaryCoverageRow(title: String(localized: "bell_catalog.summary.with_notes"), value: viewModel.bellsWithNotesCount, total: viewModel.bells.count, tint: collection.backgroundStyle.accentColor) {
                onSelectSummaryFilter?(.missingNotes)
            }
            SummaryCoverageRow(title: String(localized: "bell_catalog.summary.with_tags"), value: viewModel.bellsWithTagsCount, total: viewModel.bells.count, tint: collection.backgroundStyle.accentColor) {
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
                            if title == String(localized: "bell_catalog.summary.top_countries") {
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
            Text(String(localized: "bell_catalog.summary.recent"))
                .font(.headline)

            if viewModel.bells.isEmpty {
                Text(String(localized: "bell_catalog.summary.none"))
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
            Text(String(localized: "bell_catalog.summary.tag_cloud"))
                .font(.headline)

            if viewModel.topTags.isEmpty {
                Text(String(localized: "bell_catalog.summary.no_tags"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                TagFlowLayout(spacing: 8) {
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

            Text(String.localizedStringWithFormat(String(localized: "bell_catalog.items.filtered_by_tag"), summaryFilter?.title() ?? ""))
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button(String(localized: "common.clear")) {
                onClearSummaryFilter?()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(collection.backgroundStyle.accentColor)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.medium, style: .continuous))
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
                FilterChip(title: String(localized: "bell_catalog.filter.all"), isSelected: selectedCondition == nil, tint: collection.backgroundStyle.accentColor) {
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
                                    .padding(.horizontal, CatalogSpacing.micro)

                                LazyVGrid(columns: gridColumns(forScreenWidth: screenWidth), spacing: layoutMode.spacing) {
                                    ForEach(cabinetGroup.bells) { bell in
                                        Button {
                                            presentedBell = bell
                                        } label: {
                                            BellCardView(
                                                bell: bell,
                                                layoutMode: layoutMode
                                            )
                                            .matchedGeometryEffect(id: bell.id, in: bellGridTransitionNamespace)
                                            .matchedTransitionSource(id: bell.id, in: bellDetailZoomNamespace)
                                            .background {
                                                GeometryReader { proxy in
                                                    Color.clear.preference(
                                                        key: BellCardFramePreferenceKey.self,
                                                        value: [bell.id: proxy.frame(in: .named(BellCatalogCoordinateSpace.pinchGrid))]
                                                    )
                                                }
                                            }
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
                                .matchedGeometryEffect(id: bell.id, in: bellGridTransitionNamespace)
                                .matchedTransitionSource(id: bell.id, in: bellDetailZoomNamespace)
                                .background {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: BellCardFramePreferenceKey.self,
                                            value: [bell.id: proxy.frame(in: .named(BellCatalogCoordinateSpace.pinchGrid))]
                                        )
                                    }
                                }
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

    private func deleteBell(_ bellID: UUID) {
        repository.deleteBellRecord(bellID: bellID)
        viewModel.bellRecords.removeAll { $0.id == bellID }
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
            homeName: repository.fetchHomes().first(where: { $0.id == collection.homeID })?.name ?? String(localized: "common.unknown")
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
                .fill(CatalogSemanticColors.separator)
                .frame(height: 0.5)
        }
    }
}

private struct BellGroupingJumpPopover: View {
    let titles: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CatalogSpacing.compact) {
                ForEach(titles, id: \.self) { title in
                    Button(title) {
                        onSelect(title)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, CatalogSpacing.regular)
                    .background(CatalogSemanticColors.groupedSurface, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.thumbnail, style: .continuous))
                }
            }
            .padding(CatalogSpacing.regular)
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
    @State private var selectedAcquiredYearOption = String(localized: "editor.acquired_year.none")
    @State private var highlightedSection: StartSection?
    @StateObject private var photoAnalysis = BellPhotoAnalysisController()
    private let existingBellID: UUID?
    private let existingCreatedAt: Date?
    private let editorItemID: UUID

    private let acquiredYearOptions = [String(localized: "editor.acquired_year.none")] + Array(1900...Calendar.current.component(.year, from: .now)).reversed().map(String.init)

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
        _selectedAcquiredYearOption = State(initialValue: bell?.acquiredYear.map(String.init) ?? String(localized: "editor.acquired_year.none"))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                Form {
                    Section(String(localized: "editor.media")) {
                        MediaSection(
                            itemID: editorItemID,
                            mediaAssets: $mediaAssets
                        )
                    }

                    if photoAnalysis.hasSuggestions {
                        Section(String(localized: "editor.photo_analysis.section")) {
                            if photoAnalysis.isAnalyzing {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text(String(localized: "editor.photo_analysis.analyzing"))
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
                                        title: String(localized: "editor.photo_analysis.title"),
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
                                        title: String(localized: "editor.photo_analysis.notes"),
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
                                        title: String(localized: "editor.photo_analysis.material"),
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
                                        title: String(localized: "editor.photo_analysis.condition"),
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
                                        title: String(localized: "editor.photo_analysis.tags"),
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

                    Section(String(localized: "editor.description")) {
                        TextField(String(localized: "editor.short_description"), text: $title)
                        TextField(String(localized: "editor.note_history"), text: $notes, axis: .vertical)
                            .lineLimit(4, reservesSpace: true)
                    }

                    Section(String(localized: "editor.acquisition_details")) {
                        YearPickerField(
                            title: String(localized: "editor.acquired_year"),
                            selection: $selectedAcquiredYearOption,
                            options: acquiredYearOptions
                        )

                        EnumSelectionRow(
                            title: String(localized: "editor.acquisition"),
                            selectedLabel: acquisitionMethod.displayName,
                            options: AcquisitionMethod.allCases,
                            selection: $acquisitionMethod,
                            optionTitle: \.displayName
                        )
                    }

                    Section(String(localized: "editor.attributes")) {
                        EnumSelectionRow(
                            title: String(localized: "editor.condition"),
                            selectedLabel: condition.displayName,
                            options: ItemCondition.allCases,
                            selection: $condition,
                            optionTitle: \.displayName
                        )

                        EnumSelectionRow(
                            title: String(localized: "editor.material"),
                            selectedLabel: material.displayName,
                            options: BellMaterial.allCases,
                            selection: $material,
                            optionTitle: \.displayName
                        )

                        if material == .other {
                            TextField(String(localized: "editor.material.custom"), text: $customMaterialName)
                        }
                    }

                    Section(String(localized: "editor.storage")) {
                        LocationPickerField(
                            title: String(localized: "editor.location"),
                            selectedLabel: selectedLocationLabel,
                            locations: availableLocations,
                            selectedLocationID: $selectedLocationID
                        )
                    }
                    .id(StartSection.storage)
                    .listRowBackground(sectionBackground(for: .storage))

                    Section(String(localized: "editor.additional_details")) {
                        PlacePickerField(
                            title: String(localized: "editor.origin"),
                            selectedLabel: selectedOriginLabel,
                            places: availablePlaces,
                            selectedPlace: $selectedOriginPlace
                        )
                    }

                    Section(String(localized: "editor.tags")) {
                        TagEditorSection(
                            tagInput: $tagInput,
                            tags: $tags
                        )
                    }
                }
                .navigationTitle(existingBellID == nil ? String(localized: "editor.bell.add") : String(localized: "editor.bell.edit"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(String(localized: "common.cancel"))
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            saveBell()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .disabled(!canSave)
                        .accessibilityLabel(String(localized: "common.save"))
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
            RoundedRectangle(cornerRadius: CatalogCornerRadii.highlight, style: .continuous)
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
                acquiredYear: selectedAcquiredYearOption == String(localized: "editor.acquired_year.none") ? nil : Int(selectedAcquiredYearOption),
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
            storagePath: location.map(locationPath(for:)) ?? String(localized: "common.unassigned"),
            mediaAssets: normalizedMediaAssets,
            createdBy: "You",
            tags: tags
        )

        onSave(newBell)
        dismiss()
    }

    private var selectedOriginLabel: String {
        selectedOriginPlace?.displayName ?? String(localized: "common.unassigned")
    }

    private var selectedLocationLabel: String {
        guard let selectedLocationID, let path = locationPathByID[selectedLocationID] else {
            return String(localized: "common.unassigned")
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
                    Label(String(localized: "editor.photo_analysis.accept"), systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(action: onReject) {
                    Label(String(localized: "editor.photo_analysis.reject"), systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, CatalogSpacing.micro)
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
                    .catalogPillPadding(.regular)
                    .background(.thinMaterial, in: Capsule())
            }
        }
    }
}

private struct PhotoRecognizedTextBlock: View {
    let textFeatures: [RecognizedTextFeature]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "editor.photo_analysis.detected_text"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TagFlowLayout(spacing: 8) {
                ForEach(textFeatures, id: \.self) { feature in
                    Text(feature.text)
                        .font(.caption.weight(.medium))
                        .catalogPillPadding(.regular)
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
                        .catalogPillPadding(.regular)
                        .background(.thinMaterial, in: Capsule())
                }
            }

            HStack(spacing: 10) {
                Button(action: onAcceptAll) {
                    Label(String(localized: "editor.photo_analysis.accept"), systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(action: onReject) {
                    Label(String(localized: "editor.photo_analysis.reject"), systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, CatalogSpacing.micro)
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
                .catalogPillPadding(.prominent)
                .background(
                    isSelected
                        ? tint
                        : CatalogMediaContrast.overlayChipMuted,
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
            .catalogPillPadding(.regular)
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
                            .fill(CatalogSemanticColors.separator)

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
                    .catalogPillPadding(.compact)
                    .background(tint.opacity(0.14), in: Capsule())
            }
        }
        .buttonStyle(.plain)
    }
}

private struct StatChip: View {
    let value: String
    let title: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogSpacing.micro) {
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, CatalogSpacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous))
    }
}

private struct SummaryGlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.section, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CatalogCornerRadii.section, style: .continuous)
                    .stroke(CatalogMediaContrast.glassStroke, lineWidth: 1)
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

private struct BellGridDetailNavigationContainer: View {
    @State var bell: BellRecord
    let repository: any CatalogRepository

    var body: some View {
        BellDetailView(bell: $bell, repository: repository)
    }
}
