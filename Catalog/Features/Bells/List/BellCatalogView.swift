import SwiftUI
import SwiftData
import UIKit


private func localizedCount(_ count: Int, kind: SummaryCountKind) -> String {
    String.localizedStringWithFormat(
        String(localized: kind.resource),
        count
    )
}

private enum BellCatalogFeedback: Equatable {
    case success
    case warning
    case selection

    var sensoryFeedback: SensoryFeedback {
        switch self {
        case .success:
            return .success
        case .warning:
            return .warning
        case .selection:
            return .selection
        }
    }
}

private struct BellCatalogFeedbackEvent: Equatable {
    let kind: BellCatalogFeedback
    let token: Int
}

struct BellCatalogSelectionModePreferenceKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private extension BellPresenceFilter {
    var title: String {
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
        }
    }
}

private extension BellAttributeFilter {
    var title: String {
        switch self {
        case .country(let value), .material(let value), .tag(let value):
            return value
        case .condition(let condition):
            return condition.displayName
        case .acquisitionMethod(let method):
            return method.displayName
        }
    }
}

private extension BellFilters {
    var activeTagFilter: BellAttributeFilter? {
        attributes.first {
            if case .tag = $0 {
                return true
            }

            return false
        }
    }

    var title: String? {
        presence.first?.title ?? attributes.first?.title
    }
}



struct BellCatalogView: View {
    enum DisplayMode {
        case normal
        case search
    }

    private enum LayoutThresholdDirection {
        case zoomIn
        case zoomOut
    }

    let repository: any CatalogRepository
    let collaborators: [Collaborator]
    let collection: CollectionSummary?
    let displayMode: DisplayMode
    let startsSearchFocused: Bool
    @Environment(\.modelContext) private var modelContext
    @Binding var layoutMode: BellGridLayoutMode
    @Binding var orderMode: BellOrderMode
    @Binding var filters: BellFilters
    @Binding var searchState: BellCatalogSearchState
    @Query private var bells: [BellEntity]
    @Query private var queriedLocations: [LocationEntity]
    @Query private var queriedHomes: [HomeEntity]
    @Query(sort: \CollectionEntity.title) private var queriedCollections: [CollectionEntity]
    @State private var presentedBell: BellEntity?
    @State private var bellPendingMove: BellEntity?
    @State private var bellPendingDeletion: BellEntity?
    @State private var isPresentingDeleteConfirmation = false
    @State private var activeJumpPopoverSectionID: String?
    @State private var isPresentingDataHealthPopover = false
    @State private var isPresentingTopGeographyPopover = false
    @State private var pendingScrollTargetID: String?
    @State private var isSelectionModeEnabled = false
    @State private var selectedBellIDs: Set<UUID> = []
    @State private var visualScale: CGFloat = 1
    @State private var feedbackEvent: BellCatalogFeedbackEvent?
    @State private var feedbackToken = 0
    @State private var activeLayoutThresholdDirection: LayoutThresholdDirection?
    @State private var accumulatedMagnificationDelta: CGFloat = 0
    @State private var lastGestureMagnification: CGFloat?
    @State private var isPinching: Bool = false
    @State private var isPreparingForPinch = false
    @State private var didEndActivePinchGesture = false
    @State private var pinchOriginBellID: UUID?
    @State private var didAttemptCapture = false
    @State private var pinchNavigatedBell: BellEntity?
    @State private var suggestedTokens: [SearchToken] = []
    @FocusState private var isSearchFocused: Bool
    @StateObject private var viewModel: BellCatalogViewModel
    @Namespace private var bellGridTransitionNamespace
    @Namespace private var bellDetailZoomNamespace

    init(
        collection: CollectionSummary?,
        repository: any CatalogRepository,
        collaborators: [Collaborator],
        displayMode: DisplayMode = .normal,
        layoutMode: Binding<BellGridLayoutMode> = .constant(.mini),
        orderMode: Binding<BellOrderMode> = .constant(.newestFirst),
        filters: Binding<BellFilters> = .constant(BellFilters()),
        searchState: Binding<BellCatalogSearchState> = .constant(BellCatalogSearchState()),
        startsSearchFocused: Bool = false
    ) {
        self.repository = repository
        self.collaborators = collaborators
        self.collection = collection
        self.displayMode = displayMode
        self.startsSearchFocused = startsSearchFocused
        self._layoutMode = layoutMode
        self._orderMode = orderMode
        self._filters = filters
        self._searchState = searchState
        if let collection {
            let collectionID = Optional(collection.id)
            _bells = Query(
                filter: #Predicate<BellEntity> { bell in
                    bell.collection?.id == collectionID
                },
                sort: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        } else {
            _bells = Query(sort: [SortDescriptor(\.createdAt, order: .reverse)])
        }
        _queriedLocations = Query()
        _queriedHomes = Query()
        _viewModel = StateObject(
            wrappedValue: BellCatalogViewModel(
                orderMode: orderMode.wrappedValue,
                filters: filters.wrappedValue,
                searchState: searchState.wrappedValue,
                forcesFlatLayout: Self.usesFlatSearchLayout(
                    displayMode: displayMode,
                    collection: collection,
                    searchState: searchState.wrappedValue,
                    startsSearchFocused: startsSearchFocused
                )
            )
        )
    }

    private var catalogStyle: CollectionBackgroundStyle {
        collection?.backgroundStyle ?? .slate
    }

    private var themeColors: [Color] {
        catalogStyle.screenColors
    }

    private var displayModel: BellCatalogDisplayModel {
        viewModel.displayModel
    }

    private func visibleBellsInDisplayOrder() -> [BellEntity] {
        switch displayModel.layout {
        case .empty:
            return []
        case .flat(let bells):
            return bells
        case .grouped(let sections):
            return sections.flatMap(\.bells)
        }
    }

    private var usesFlatSearchLayout: Bool {
        Self.usesFlatSearchLayout(
            displayMode: displayMode,
            collection: collection,
            searchState: searchState,
            startsSearchFocused: startsSearchFocused
        )
    }

    private static func usesFlatSearchLayout(
        displayMode: DisplayMode,
        collection: CollectionSummary?,
        searchState: BellCatalogSearchState,
        startsSearchFocused: Bool
    ) -> Bool {
        if displayMode == .search {
            return true
        }

        return collection == nil
        && (
            startsSearchFocused
            || !searchState.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !searchState.tokens.isEmpty
        )
    }

    private var hasActiveFilter: Bool {
        !filters.isEmpty
    }

    private func setFilter(_ filter: BellPresenceFilter) {
        filters = BellFilters(presence: [filter])
    }

    private func setFilter(_ filter: BellAttributeFilter) {
        filters = BellFilters(attributes: [filter])
    }

    private var locationsByID: [UUID: LocationEntity] {
        Dictionary(uniqueKeysWithValues: availableLocations.map { ($0.id, $0) })
    }

    private var scrollContentBottomInset: CGFloat { 120 }

    private var bottomSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets
            .bottom ?? 0
    }

    private var orderedLayoutModes: [BellGridLayoutMode] {
        [.covers, .mini, .compact, .wide, .showcase]
    }

    private func gridColumns(forScreenWidth screenWidth: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.fixed(layoutMode.cardWidth(forScreenWidth: screenWidth)), spacing: layoutMode.spacing, alignment: .top),
            count: layoutMode.columnCount
        )
    }

    private func bellIndex(
        at location: CGPoint,
        in bells: [BellEntity],
        screenWidth: CGFloat
    ) -> Int? {
        guard !bells.isEmpty, screenWidth > 0 else { return nil }

        let columnCount = max(layoutMode.columnCount, 1)
        let cardWidth = layoutMode.cardWidth(forScreenWidth: screenWidth)
        let cardHeight = layoutMode.cardHeight
        let horizontalStep = cardWidth + layoutMode.spacing
        let verticalStep = cardHeight + layoutMode.spacing
        guard horizontalStep > 0, verticalStep > 0 else { return nil }

        let totalGridWidth = (cardWidth * CGFloat(columnCount)) + (layoutMode.spacing * CGFloat(max(columnCount - 1, 0)))
        let gridLeadingInset = max((screenWidth - totalGridWidth) / 2, 0)
        let localX = location.x - gridLeadingInset

        let rawColumn = ((localX - (cardWidth / 2)) / horizontalStep).rounded()
        let rawRow = ((location.y - (cardHeight / 2)) / verticalStep).rounded()
        let column = min(max(Int(rawColumn), 0), columnCount - 1)
        let row = max(Int(rawRow), 0)
        let index = (row * columnCount) + column

        return min(index, bells.count - 1)
    }

    private func layoutMagnifyGesture(
        bells: [BellEntity],
        screenWidth: CGFloat
    ) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !isPinching {
                    isPreparingForPinch = true
                    isPinching = true
                }
                if !didAttemptCapture {
                    capturePinchOriginBellIfNeeded(
                        at: value.startLocation,
                        in: bells,
                        screenWidth: screenWidth
                    )
                }
                updateAccumulatedMagnification(with: value.magnification)
                visualScale = clampedVisualScale(for: value.magnification)
            }
            .onEnded { value in
                didEndActivePinchGesture = abs(value.velocity) > 0.5
                let effectiveThreshold = zoomThreshold(forVelocity: value.velocity)
                let finalAccumulatedDelta = accumulatedMagnificationDelta
                let shouldOpenDetailFromPinch = layoutMode == .showcase && !canZoomOut && finalAccumulatedDelta >= effectiveThreshold
                let pinchOriginBell = pinchOriginBellID.flatMap { displayedItemsBell(withID: $0) }

                withAnimation(.easeInOut(duration: 0.2)) {
                    activeLayoutThresholdDirection = nil
                    visualScale = 1
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) {
                    if shouldOpenDetailFromPinch, let pinchOriginBell {
                        pinchNavigatedBell = pinchOriginBell
                    } else if finalAccumulatedDelta >= effectiveThreshold {
                        zoomOutLayout()
                    } else if finalAccumulatedDelta <= -effectiveThreshold {
                        zoomInLayout()
                    }
                }

                accumulatedMagnificationDelta = 0
                lastGestureMagnification = nil
                pinchOriginBellID = nil
                didAttemptCapture = false

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isPinching = false
                    isPreparingForPinch = false
                    didEndActivePinchGesture = false
                }
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
            emitFeedback(.selection)
        }
    }

    private func emitFeedback(_ kind: BellCatalogFeedback) {
        feedbackToken += 1
        feedbackEvent = BellCatalogFeedbackEvent(kind: kind, token: feedbackToken)
    }

    private func capturePinchOriginBellIfNeeded(
        at location: CGPoint,
        in bells: [BellEntity],
        screenWidth: CGFloat
    ) {
        guard pinchOriginBellID == nil else { return }
        guard !didAttemptCapture else { return }

        didAttemptCapture = true
        guard let index = bellIndex(at: location, in: bells, screenWidth: screenWidth) else { return }
        pinchOriginBellID = bells[index].id
    }

    private func displayedItemsBell(withID bellID: UUID) -> BellEntity? {
        viewModel.bell(withID: bellID)
    }

    private var availableSearchCollections: [CollectionEntity] {
        guard let collection else { return queriedCollections }
        return queriedCollections.filter { $0.home?.id == collection.homeID }
    }

    private func updateSuggestedTokens() {
        guard !usesFlatSearchLayout else {
            suggestedTokens = []
            return
        }

        let selectedTokens = Set(searchState.tokens)
        suggestedTokens = availableSearchCollections
            .map { SearchToken.collection($0.id) }
            .filter { !selectedTokens.contains($0) }
    }

    private func searchTokenTitle(_ token: SearchToken) -> String {
        switch token {
        case .collection(let collectionID):
            return queriedCollections.first(where: { $0.id == collectionID })?.title
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

    var body: some View {
        GeometryReader { proxy in
            unifiedFeedContent(
                displayModel: displayModel,
                screenWidth: proxy.size.width,
                screenHeight: proxy.size.height
            )
        }
        .sheet(item: $presentedBell) { bell in
            BellGridDetailSheetContainer(bell: bell, repository: repository)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $bellPendingMove) { bell in
            BellQuickMoveSheet(
                bell: bell,
                locations: availableLocations,
                locationPathByID: locationPathByID
            ) { locationID in
                let bells = isSelectionModeEnabled ? selectedBells : [bell]
                moveBells(bells, to: locationID)
                if isSelectionModeEnabled {
                    cancelSelectionMode()
                }
            }
        }
        .navigationDestination(item: $pinchNavigatedBell) { bell in
            BellGridDetailNavigationContainer(bell: bell, repository: repository)
                .navigationTransition(.zoom(sourceID: bell.id, in: bellDetailZoomNamespace))
        }
        .confirmationDialog(
            String(localized: "bell.context.delete.title"),
            isPresented: $isPresentingDeleteConfirmation,
            titleVisibility: .visible,
            presenting: bellPendingDeletion
        ) { bell in
            Button(String(localized: "bell.context.delete.confirm"), role: .destructive) {
                let bells = isSelectionModeEnabled ? selectedBells : [bell]
                deleteBells(bells)
                if isSelectionModeEnabled {
                    cancelSelectionMode()
                }
                bellPendingDeletion = nil
            }

            Button(String(localized: "common.cancel"), role: .cancel) {
                bellPendingDeletion = nil
            }
        } message: { _ in
            Text(String(localized: "bell.context.delete.message"))
        }
        .sensoryFeedback(trigger: feedbackEvent) { _, newValue in
            newValue?.kind.sensoryFeedback
        }
        .searchable(
            text: $searchState.query,
            tokens: $searchState.tokens,
            suggestedTokens: $suggestedTokens
        ) { token in
            Label(searchTokenTitle(token), systemImage: searchTokenSystemImage(token))
        }
        .searchFocused($isSearchFocused)
        .toolbar(isSelectionModeEnabled ? .hidden : .visible, for: .tabBar)
        .preference(key: BellCatalogSelectionModePreferenceKey.self, value: isSelectionModeEnabled)
        .toolbar {
            if isSelectionModeEnabled {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        cancelSelectionMode()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "common.cancel"))
                }
            }
        }
        .onAppear {
            viewModel.updateContext(orderMode: orderMode)
            viewModel.updateContext(filters: filters)
            viewModel.updateContext(searchState: searchState, forcesFlatLayout: usesFlatSearchLayout)
            viewModel.updateSource(bells: bells)
            updateSuggestedTokens()
            if startsSearchFocused {
                isSearchFocused = true
            }
        }
        .onChange(of: bells) { _, newValue in
            viewModel.updateSource(bells: newValue)
        }
        .onChange(of: orderMode) { _, newValue in
            viewModel.updateContext(orderMode: newValue)
            viewModel.updateSource(bells: bells)
            accumulatedMagnificationDelta = 0
            lastGestureMagnification = nil
            activeLayoutThresholdDirection = nil
            visualScale = 1
            pinchOriginBellID = nil
        }
        .onChange(of: filters) { _, newValue in
            viewModel.updateContext(filters: newValue)
            viewModel.updateSource(bells: bells)
            accumulatedMagnificationDelta = 0
            lastGestureMagnification = nil
            activeLayoutThresholdDirection = nil
            visualScale = 1
            pinchOriginBellID = nil
        }
        .onChange(of: searchState) { _, newValue in
            viewModel.updateContext(searchState: newValue, forcesFlatLayout: usesFlatSearchLayout)
            viewModel.updateSource(bells: bells)
            updateSuggestedTokens()
        }
        .onChange(of: queriedCollections) { _, _ in
            updateSuggestedTokens()
        }
    }

    private func unifiedFeedContent(
        displayModel: BellCatalogDisplayModel,
        screenWidth: CGFloat,
        screenHeight: CGFloat
    ) -> some View {
        return ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: displayModel.layout.isGrouped ? [.sectionHeaders] : []) {
                    Color.clear
                        .frame(height: 0)
                        .id("bell-grid-top")

                    if !isSelectionModeEnabled && displayMode == .normal {
                        dashboardHeader(displayModel: displayModel, screenHeight: screenHeight)
                    }

                    if hasActiveFilter && displayMode == .normal {
                        activeSummaryFilterSection
                    }

                    switch displayModel.layout {
                    case .empty:
                        emptyBellsGridState(
                            title: LocalizedStringKey(String(localized: "bell_catalog.empty.title")),
                            description: LocalizedStringKey(String(localized: "bell_catalog.empty.description"))
                        )
                    case .grouped(let sections):
                        groupedBellSectionsContent(
                            sections: sections,
                            screenWidth: screenWidth,
                            scrollProxy: scrollProxy
                        )
                        .scaleEffect(visualScale)
                    case .flat(let bells):
                        LazyVGrid(columns: gridColumns(forScreenWidth: screenWidth), spacing: layoutMode.spacing) {
                            ForEach(bells) { bell in
                                bellCardButton(bell)
                            }
                        }
                        .scaleEffect(visualScale)
                        .simultaneousGesture(
                            layoutMagnifyGesture(
                                bells: bells,
                                screenWidth: screenWidth
                            )
                        )
                    }
                }
                .animation(.snappy(duration: 0.24), value: layoutMode)
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
            .onChange(of: orderMode) { _, _ in
                activeJumpPopoverSectionID = nil
                let targetID = pendingScrollTargetID ?? "bell-grid-top"
                DispatchQueue.main.async {
                    withAnimation(.snappy(duration: 0.24)) {
                        scrollProxy.scrollTo(targetID, anchor: .top)
                    }
                    pendingScrollTargetID = nil
                }
            }
            .onChange(of: pendingScrollTargetID) { _, targetID in
                guard let targetID else { return }
                withAnimation(.snappy(duration: 0.24)) {
                    scrollProxy.scrollTo(targetID, anchor: .top)
                }
            }
            .onChange(of: filters) { _, newFilters in
                if newFilters.activeTagFilter != nil {
                    withAnimation(.snappy(duration: 0.24)) {
                        scrollProxy.scrollTo("bell-grid-top", anchor: .top)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if isSelectionModeEnabled && !selectedBellIDs.isEmpty {
                    selectionBottomPanel
                        .frame(height: 112, alignment: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: isSelectionModeEnabled)
            .animation(.easeInOut(duration: 0.22), value: selectedBellIDs.isEmpty)
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

    private var activeSummaryFilterSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag.fill")
                .foregroundStyle(catalogStyle.accentColor)

            Text(String.localizedStringWithFormat(String(localized: "bell_catalog.items.filtered_by_tag"), filters.title ?? ""))
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button(String(localized: "common.clear")) {
                filters = BellFilters()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(catalogStyle.accentColor)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.medium, style: .continuous))
    }

    private func dashboardHeader(displayModel: BellCatalogDisplayModel, screenHeight: CGFloat) -> some View {
        let headerHeight = min(max(screenHeight * 0.36, 220), 320)

        return VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    dashboardMetricChip(
                        title: String(localized: "bell_catalog.dashboard.total"),
                        value: "\(displayModel.stats.totalCount)",
                        systemImage: "bell.fill"
                    ) {
                        filters = BellFilters()
                    }

                    dashboardMetricChip(
                        title: String(localized: "bell_catalog.dashboard.countries"),
                        value: "\(displayModel.stats.countryCount)",
                        systemImage: "globe.europe.africa.fill"
                    ) {
                        setFilter(.withOrigin)
                    }

                    dashboardMetricChip(
                        title: String(localized: "bell_catalog.dashboard.cities"),
                        value: "\(displayModel.stats.cityCount)",
                        systemImage: "building.2.fill"
                    ) {
                        setFilter(.withCity)
                    }
                }
            }
            .scrollClipDisabled()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    DashboardTopGeographyCard(
                        countryName: topGeography(in: displayModel)?.name ?? String(localized: "common.unknown"),
                        flag: topGeography(in: displayModel)?.flag ?? "🌍",
                        countText: topGeographyCountText(in: displayModel),
                        tint: catalogStyle.accentColor,
                        action: {
                            guard !topGeographyEntries(in: displayModel).isEmpty else { return }
                            isPresentingTopGeographyPopover = true
                        }
                    )
                    .popover(isPresented: $isPresentingTopGeographyPopover) {
                        TopGeographyPopover(
                            entries: topGeographyEntries(in: displayModel),
                            onSelect: { country in
                                isPresentingTopGeographyPopover = false
                                focusGeography(country: country)
                            }
                        )
                    }

                    DashboardDataHealthCard(
                        progress: dataHealthProgress(in: displayModel),
                        tint: catalogStyle.accentColor
                    ) {
                        isPresentingDataHealthPopover = true
                    }
                    .popover(isPresented: $isPresentingDataHealthPopover) {
                        DataHealthPopover(
                            entries: dataHealthEntries(in: displayModel),
                            onSelect: { filter in
                                isPresentingDataHealthPopover = false
                                setFilter(filter)
                            }
                        )
                    }
                }
            }
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: headerHeight, alignment: .top)
        .padding(.horizontal, CatalogLayoutInsets.screen)
        .padding(.top, CatalogSpacing.compact)
        .padding(.vertical, 4)
        .scrollTransition(axis: .vertical) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.94, anchor: .top)
                .opacity(phase.isIdentity ? 1 : 0.82)
        }
    }

    private func dashboardMetricChip(
        title: String,
        value: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(catalogStyle.accentColor)

                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func dataHealthProgress(in displayModel: BellCatalogDisplayModel) -> Double {
        guard displayModel.stats.totalCount > 0 else { return 0 }
        let completeFields = displayModel.stats.filledOriginCount
            + displayModel.stats.filledYearCount
            + displayModel.stats.filledStorageCount
            + displayModel.stats.filledNotesCount
            + displayModel.stats.filledTagsCount
        let totalFields = displayModel.stats.totalCount * 5
        return min(max(Double(completeFields) / Double(totalFields), 0), 1)
    }

    private func dataHealthEntries(in displayModel: BellCatalogDisplayModel) -> [DataHealthEntry] {
        let total = displayModel.stats.totalCount

        return [
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.with_origin"),
                countText: "\(displayModel.stats.filledOriginCount)/\(total)",
                filter: .missingOrigin
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.with_year"),
                countText: "\(displayModel.stats.filledYearCount)/\(total)",
                filter: .missingYear
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.with_storage"),
                countText: "\(displayModel.stats.filledStorageCount)/\(total)",
                filter: .missingStorage
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.with_notes"),
                countText: "\(displayModel.stats.filledNotesCount)/\(total)",
                filter: .missingNotes
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.with_tags"),
                countText: "\(displayModel.stats.filledTagsCount)/\(total)",
                filter: .missingTags
            )
        ]
    }

    private func topGeography(in displayModel: BellCatalogDisplayModel) -> (name: String, flag: String, count: Int)? {
        guard let topCountry = displayModel.stats.topCountries.first else { return nil }
        return (
            name: topCountry.country,
            flag: flagEmoji(for: topCountry.countryCode),
            count: topCountry.count
        )
    }

    private func topGeographyEntries(in displayModel: BellCatalogDisplayModel) -> [TopGeographyEntry] {
        Array(displayModel.stats.topCountries.prefix(5)).map { row in
            return TopGeographyEntry(
                country: row.country,
                flag: flagEmoji(for: row.countryCode),
                countText: localizedCount(row.count, kind: .bells)
            )
        }
    }

    private func topGeographyCountText(in displayModel: BellCatalogDisplayModel) -> String {
        guard let topGeography = topGeography(in: displayModel) else { return String(localized: "bell_catalog.summary.no_origin_data") }
        return localizedCount(topGeography.count, kind: .bells)
    }

    private func focusTopGeography() {
        guard let topCountry = topGeography(in: displayModel)?.name else { return }
        focusGeography(country: topCountry)
    }

    private func focusGeography(country: String) {
        pendingScrollTargetID = "geography-\(country)"
        if orderMode != .geography {
            orderMode = .geography
        }
    }

    private func flagEmoji(for countryCode: String) -> String {
        let normalizedCode = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCode.count == 2 else { return "🌍" }

        let base: UInt32 = 127397
        let scalars = normalizedCode.unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }
        return scalars.count == 2 ? String(String.UnicodeScalarView(scalars)) : "🌍"
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
                                        bellCardButton(bell)
                                    }
                                }
                                .simultaneousGesture(
                                    layoutMagnifyGesture(
                                        bells: cabinetGroup.bells,
                                        screenWidth: screenWidth
                                    )
                                )
                            }
                        }
                    }
                } else {
                    LazyVGrid(columns: gridColumns(forScreenWidth: screenWidth), spacing: layoutMode.spacing) {
                        ForEach(section.bells) { bell in
                            bellCardButton(bell)
                        }
                    }
                    .simultaneousGesture(
                        layoutMagnifyGesture(
                            bells: section.bells,
                            screenWidth: screenWidth
                        )
                    )
                }
            } header: {
                BellGroupedSectionHeader(
                    title: section.title,
                    tint: catalogStyle.accentColor,
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

    private var availableLocations: [LocationEntity] {
        guard let collection else { return queriedLocations }
        return queriedLocations.filter { $0.home?.id == collection.homeID }
    }

    private var locationPathByID: [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: availableLocations.map { location in
                (location.id, location.pathDisplayName)
            }
        )
    }

    private var selectedBells: [BellEntity] {
        bells.filter { selectedBellIDs.contains($0.id) }
    }

    private func enterSelectionMode(with bellID: UUID) {
        withAnimation(.snappy(duration: 0.2)) {
            isSelectionModeEnabled = true
            selectedBellIDs.insert(bellID)
        }
    }

    private func toggleBellSelection(_ bellID: UUID) {
        withAnimation(.snappy(duration: 0.2)) {
            if selectedBellIDs.contains(bellID) {
                selectedBellIDs.remove(bellID)
            } else {
                selectedBellIDs.insert(bellID)
            }
        }
    }

    private func cancelSelectionMode() {
        withAnimation(.snappy(duration: 0.2)) {
            isSelectionModeEnabled = false
            selectedBellIDs.removeAll()
        }
    }

    private var selectionBottomPanel: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.72), .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            LinearGradient(
                colors: [.clear, .black.opacity(0.34), .black.opacity(0.56)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .center, spacing: 18) {
                Button {
                    bellPendingMove = selectedBells.first
                } label: {
                    Image(systemName: "folder")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(catalogStyle.accentColor)
                        .frame(width: 48, height: 48)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Circle()
                                        .fill(catalogStyle.accentColor.opacity(0.12))
                                }
                        }
                }
                .buttonStyle(.plain)

                Text(selectedBellCountText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minWidth: 150)

                Button(role: .destructive) {
                    bellPendingDeletion = selectedBells.first
                    isPresentingDeleteConfirmation = bellPendingDeletion != nil
                } label: {
                    Image(systemName: "trash")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(width: 48, height: 48)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Circle()
                                        .fill(Color.red.opacity(0.10))
                                }
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, CatalogLayoutInsets.screen)
            .padding(.bottom, 12)
            .padding(.bottom, bottomSafeAreaInset)
        }
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .bottom)
    }

    private var selectedBellCountText: String {
        String.localizedStringWithFormat(
            String(localized: "bell_catalog.selection.selected_count"),
            selectedBellIDs.count
        )
    }

    private func bellCardButton(_ bell: BellEntity) -> some View {
        Button {
            guard !isPinching else { return }
            guard !didEndActivePinchGesture && abs(accumulatedMagnificationDelta) < 0.01 else { return }

            if isSelectionModeEnabled {
                toggleBellSelection(bell.id)
            } else {
                presentedBell = bell
            }
        } label: {
            let isSelected = selectedBellIDs.contains(bell.id)

            let card = Group {
                BellCardView(
                    bell: bell,
                    layoutMode: layoutMode
                )
                .compositingGroup()
                .overlay {
                    if isSelectionModeEnabled && isSelected {
                        RoundedRectangle(cornerRadius: CatalogCornerRadii.medium, style: .continuous)
                            .fill(.black.opacity(0.22))
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelectionModeEnabled && isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.blue, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(.white, lineWidth: 2)
                            }
                            .padding(8)
                    }
                }
            }
            .opacity(isPinching ? 0.99 : 1.0)

            Group {
                if isPinching {
                    card
                } else {
                    card
                        .matchedGeometryEffect(id: bell.id, in: bellGridTransitionNamespace)
                        .matchedTransitionSource(id: bell.id, in: bellDetailZoomNamespace)
                }
            }
        }
        .id(bell.id)
        .disabled(isPinching || didEndActivePinchGesture)
        .allowsHitTesting(!isPinching)
        .buttonStyle(.plain)
        .contextMenu {
            bellCardContextMenu(for: bell)
        } preview: {
            BellCardContextPreview(bell: bell, repository: repository)
        }
    }

    @ViewBuilder
    private func bellCardContextMenu(for bell: BellEntity) -> some View {
        Button {
            enterSelectionMode(with: bell.id)
        } label: {
            Label(String(localized: "bell.context.select"), systemImage: "checkmark.circle")
        }

        Button {
            bellPendingMove = bell
        } label: {
            Label(String(localized: "bell.context.move"), systemImage: "folder")
        }

        // TODO re-enable duplication when we have a better way to handle it in the UI, as it can be destructive if used unintentionally
        //Button {
        //    duplicateBell(bell)
        //} label: {
        //    Label(String(localized: "common.duplicate"), systemImage: "plus.square.on.square")
        //}

        // TODO add share link generation and handling
        //ShareLink(
        //    item: bellShareText(for: bell),
        //    preview: SharePreview(bell.title)
        //) {
        //    Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
        //}

        Button(role: .destructive) {
            bellPendingDeletion = bell
            isPresentingDeleteConfirmation = true
        } label: {
            Label(String(localized: "common.delete"), systemImage: "trash")
        }
    }

    private func duplicateBell(_ bell: BellEntity) {
        let duplicatedBell = BellEntity(
            id: UUID(),
            title: bell.title,
            notes: bell.notes,
            acquiredYear: bell.acquiredYear,
            createdAt: .now,
            conditionRaw: bell.conditionRaw,
            acquisitionMethodRaw: bell.acquisitionMethodRaw,
            materialRaw: bell.materialRaw,
            customMaterialName: bell.customMaterialName,
            createdBy: bell.createdBy
        )
        duplicatedBell.collection = bell.collection
        duplicatedBell.location = bell.location
        duplicatedBell.originPlace = bell.originPlace
        modelContext.insert(duplicatedBell)

        duplicatedBell.mediaAssets = bell.sortedMediaAssets.enumerated().map { offset, asset in
            let copy = MediaAssetEntity(
                id: UUID(),
                kindRaw: asset.kindRaw,
                localIdentifier: asset.localIdentifier,
                displayName: asset.displayName,
                sortOrder: offset
            )
            copy.bell = duplicatedBell
            modelContext.insert(copy)
            return copy
        }

        duplicatedBell.tags = bell.sortedTags.enumerated().map { offset, tag in
            let copy = BellTagEntity(value: tag.value, sortOrder: offset)
            copy.bell = duplicatedBell
            modelContext.insert(copy)
            return copy
        }

        try? modelContext.save()
        emitFeedback(.success)
    }

    private func moveBells(_ bells: [BellEntity], to locationID: UUID?) {
        let location = locationID.flatMap { locationsByID[$0] }
        for bell in bells {
            bell.location = location
        }

        try? modelContext.save()
        emitFeedback(.success)
    }

    private func deleteBells(_ bells: [BellEntity]) {
        for bell in bells {
            modelContext.delete(bell)
        }

        try? modelContext.save()
        emitFeedback(.warning)
    }

    private func bellShareText(for bell: BellEntity) -> String {
        var lines = [bell.title]

        if bell.originPlace != nil {
            lines.append(bell.placeDisplayName)
        }

        if !bell.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append(bell.notes)
        }

        return lines.joined(separator: "\n")
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
        .background(.ultraThinMaterial)
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
        .presentationBackground(.clear)
    }
}

private struct BellGridDetailNavigationContainer: View {
    @State private var bell: BellRecord
    let repository: any CatalogRepository

    init(bell: BellEntity, repository: any CatalogRepository) {
        _bell = State(initialValue: bell.recordSnapshot)
        self.repository = repository
    }

    var body: some View {
        BellDetailView(bell: $bell, repository: repository)
    }
}

private struct BellCardContextPreview: View {
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

private struct BellQuickMoveSheet: View {
    let bell: BellEntity
    let locations: [LocationEntity]
    let locationPathByID: [UUID: String]
    let onSave: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedLocationID: UUID?

    init(
        bell: BellEntity,
        locations: [LocationEntity],
        locationPathByID: [UUID: String],
        onSave: @escaping (UUID?) -> Void
    ) {
        self.bell = bell
        self.locations = locations
        self.locationPathByID = locationPathByID
        self.onSave = onSave
        _selectedLocationID = State(initialValue: bell.location?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "editor.storage")) {
                    LocationPickerField(
                        title: String(localized: "editor.location"),
                        selectedLabel: selectedLocationLabel,
                        locations: domainLocations,
                        selectedLocationID: $selectedLocationID
                    )
                }
            }
            .navigationTitle(String(localized: "bell.context.move"))
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
                        onSave(selectedLocationID)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(String(localized: "common.save"))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var selectedLocationLabel: String {
        guard let selectedLocationID, let path = locationPathByID[selectedLocationID] else {
            return String(localized: "common.unassigned")
        }

        return path
    }

    private var domainLocations: [Location] {
        locations.map { entity in
            Location(
                id: entity.id,
                homeID: entity.home?.id ?? UUID(),
                parentLocationID: entity.parent?.id,
                kind: entity.kind,
                name: entity.name,
                notes: entity.notes
            )
        }
    }
}
