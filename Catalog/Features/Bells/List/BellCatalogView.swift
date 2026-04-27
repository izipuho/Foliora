import SwiftUI
import SwiftData
import UIKit


private func localizedCount(_ count: Int, kind: SummaryCountKind) -> String {
    String.localizedStringWithFormat(
        String(localized: kind.resource),
        count
    )
}

private enum BellCatalogCoordinateSpace {
    static let pinchGrid = "bellCatalogPinchGrid"
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
    private enum LayoutThresholdDirection {
        case zoomIn
        case zoomOut
    }

    let repository: any CatalogRepository
    let collaborators: [Collaborator]
    let collection: CollectionSummary
    @Environment(\.modelContext) private var modelContext
    @Binding var layoutMode: BellGridLayoutMode
    @Binding var orderMode: BellOrderMode
    @Binding var filters: BellFilters
    @Query private var queriedBells: [BellEntity]
    @Query private var queriedLocations: [LocationEntity]
    @Query private var queriedHomes: [HomeEntity]
    @State private var presentedBell: BellEntity?
    @State private var bellPendingMove: BellEntity?
    @State private var bellPendingDeletion: BellEntity?
    @State private var isPresentingDeleteConfirmation = false
    @State private var activeJumpPopoverSectionID: String?
    @State private var isPresentingDataHealthPopover = false
    @State private var isPresentingTopGeographyPopover = false
    @State private var pendingScrollTargetID: String?
    @State private var visualScale: CGFloat = 1
    @State private var feedbackEvent: BellCatalogFeedbackEvent?
    @State private var feedbackToken = 0
    @State private var activeLayoutThresholdDirection: LayoutThresholdDirection?
    @State private var accumulatedMagnificationDelta: CGFloat = 0
    @State private var lastGestureMagnification: CGFloat?
    @State private var pinchOriginBellID: UUID?
    @State private var pinchNavigatedBell: BellEntity?
    @State private var bellCardFrames: [UUID: CGRect] = [:]
    @State private var viewModel: BellCatalogViewModel
    @Namespace private var bellGridTransitionNamespace
    @Namespace private var bellDetailZoomNamespace

    init(
        collection: CollectionSummary,
        repository: any CatalogRepository,
        collaborators: [Collaborator],
        layoutMode: Binding<BellGridLayoutMode> = .constant(.mini),
        orderMode: Binding<BellOrderMode> = .constant(.newestFirst),
        filters: Binding<BellFilters> = .constant(BellFilters())
    ) {
        self.repository = repository
        self.collaborators = collaborators
        self.collection = collection
        self._layoutMode = layoutMode
        self._orderMode = orderMode
        self._filters = filters
        let collectionID = Optional(collection.id)
        _queriedBells = Query(
            filter: #Predicate<BellEntity> { bell in
                bell.collection?.id == collectionID
            },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        _queriedLocations = Query()
        _queriedHomes = Query()
        _viewModel = State(
            initialValue: BellCatalogViewModel(
                bellRecords: [],
                orderMode: orderMode.wrappedValue,
                filters: filters.wrappedValue,
                searchText: ""
            )
        )
    }

    private var themeColors: [Color] {
        collection.backgroundStyle.screenColors
    }

    private var displayModel: BellCatalogDisplayModel {
        viewModel.displayModel
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
                capturePinchOriginBellIfNeeded(at: value.startLocation)
                updateAccumulatedMagnification(with: value.magnification)
                updateLayoutThresholdFeedback(for: value)
                visualScale = clampedVisualScale(for: value.magnification)
            }
            .onEnded { value in
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
            emitFeedback(.selection)
        }
    }

    private func emitFeedback(_ kind: BellCatalogFeedback) {
        feedbackToken += 1
        feedbackEvent = BellCatalogFeedbackEvent(kind: kind, token: feedbackToken)
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

    private func displayedItemsBell(withID bellID: UUID) -> BellEntity? {
        displayModel.filteredBells.first(where: { $0.id == bellID })
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
                moveBell(bell, to: locationID)
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
                deleteBell(bell.id)
                emitFeedback(.warning)
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
        .coordinateSpace(name: BellCatalogCoordinateSpace.pinchGrid)
        .onPreferenceChange(BellCardFramePreferenceKey.self) { frames in
            bellCardFrames = frames
        }
        .onAppear {
            viewModel.updateContext(
                bellRecords: queriedBells,
                orderMode: orderMode,
                filters: filters,
                searchText: ""
            )
        }
        .onChange(of: queriedBells) { _, newValue in
            viewModel.updateContext(
                bellRecords: newValue,
                orderMode: orderMode,
                filters: filters,
                searchText: ""
            )
        }
        .onChange(of: orderMode) { _, newValue in
            viewModel.updateContext(
                bellRecords: queriedBells,
                orderMode: newValue,
                filters: filters,
                searchText: ""
            )
            accumulatedMagnificationDelta = 0
            lastGestureMagnification = nil
            activeLayoutThresholdDirection = nil
            visualScale = 1
            pinchOriginBellID = nil
        }
        .onChange(of: filters) { _, newValue in
            viewModel.updateContext(
                bellRecords: queriedBells,
                orderMode: orderMode,
                filters: newValue,
                searchText: ""
            )
            accumulatedMagnificationDelta = 0
            lastGestureMagnification = nil
            activeLayoutThresholdDirection = nil
            visualScale = 1
            pinchOriginBellID = nil
        }
    }

    private func unifiedFeedContent(
        displayModel: BellCatalogDisplayModel,
        screenWidth: CGFloat,
        screenHeight: CGFloat
    ) -> some View {
        return ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: displayModel.groupedSections.isEmpty ? [] : [.sectionHeaders]) {
                    Color.clear
                        .frame(height: 0)
                        .id("bell-grid-top")

                    dashboardHeader(displayModel: displayModel, screenHeight: screenHeight)

                    if hasActiveFilter {
                        activeSummaryFilterSection
                    }

                    if displayModel.filteredBells.isEmpty {
                        emptyBellsGridState(
                            title: LocalizedStringKey(String(localized: "bell_catalog.empty.title")),
                            description: LocalizedStringKey(String(localized: "bell_catalog.empty.description"))
                        )
                    } else if !displayModel.groupedSections.isEmpty {
                        groupedBellSectionsContent(
                            sections: displayModel.groupedSections,
                            screenWidth: screenWidth,
                            scrollProxy: scrollProxy
                        )
                        .scaleEffect(visualScale, anchor: .center)
                    } else {
                        LazyVGrid(columns: gridColumns(forScreenWidth: screenWidth), spacing: layoutMode.spacing) {
                            ForEach(displayModel.filteredBells) { bell in
                                bellCardButton(bell)
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
                .foregroundStyle(collection.backgroundStyle.accentColor)

            Text(String.localizedStringWithFormat(String(localized: "bell_catalog.items.filtered_by_tag"), filters.title ?? ""))
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button(String(localized: "common.clear")) {
                filters = BellFilters()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(collection.backgroundStyle.accentColor)
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
                        value: "\(displayModel.bellRecords.count)",
                        systemImage: "bell.fill"
                    ) {
                        filters = BellFilters()
                    }

                    dashboardMetricChip(
                        title: String(localized: "bell_catalog.dashboard.countries"),
                        value: "\(displayModel.countryCount)",
                        systemImage: "globe.europe.africa.fill"
                    ) {
                        setFilter(.withOrigin)
                    }

                    dashboardMetricChip(
                        title: String(localized: "bell_catalog.dashboard.cities"),
                        value: "\(displayModel.cityCount)",
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
                        tint: collection.backgroundStyle.accentColor,
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
                        tint: collection.backgroundStyle.accentColor
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
                    .foregroundStyle(collection.backgroundStyle.accentColor)

                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8)
        }
        .buttonStyle(.plain)
    }

    private func dataHealthProgress(in displayModel: BellCatalogDisplayModel) -> Double {
        guard !displayModel.bellRecords.isEmpty else { return 0 }
        let completeFields = displayModel.bellsWithOriginCount
            + displayModel.bellsWithAcquiredYearCount
            + displayModel.bellsWithStorageCount
            + displayModel.bellsWithNotesCount
            + displayModel.bellsWithTagsCount
        let totalFields = displayModel.bellRecords.count * 5
        return min(max(Double(completeFields) / Double(totalFields), 0), 1)
    }

    private func dataHealthEntries(in displayModel: BellCatalogDisplayModel) -> [DataHealthEntry] {
        let total = displayModel.bellRecords.count

        return [
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.with_origin"),
                countText: "\(displayModel.bellsWithOriginCount)/\(total)",
                filter: .missingOrigin
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.with_year"),
                countText: "\(displayModel.bellsWithAcquiredYearCount)/\(total)",
                filter: .missingYear
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.with_storage"),
                countText: "\(displayModel.bellsWithStorageCount)/\(total)",
                filter: .missingStorage
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.with_notes"),
                countText: "\(displayModel.bellsWithNotesCount)/\(total)",
                filter: .missingNotes
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.with_tags"),
                countText: "\(displayModel.bellsWithTagsCount)/\(total)",
                filter: .missingTags
            )
        ]
    }

    private func topGeography(in displayModel: BellCatalogDisplayModel) -> (name: String, flag: String, count: Int)? {
        guard let topCountry = displayModel.topCountries.first else { return nil }
        return (
            name: topCountry.country,
            flag: flagEmoji(for: topCountry.countryCode),
            count: topCountry.count
        )
    }

    private func topGeographyEntries(in displayModel: BellCatalogDisplayModel) -> [TopGeographyEntry] {
        Array(displayModel.topCountries.prefix(5)).map { row in
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
                            }
                        }
                    }
                } else {
                    LazyVGrid(columns: gridColumns(forScreenWidth: screenWidth), spacing: layoutMode.spacing) {
                        ForEach(section.bells) { bell in
                            bellCardButton(bell)
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
        guard let bell = queriedBells.first(where: { $0.id == bellID }) else { return }
        modelContext.delete(bell)
        try? modelContext.save()
    }

    private var availableLocations: [LocationEntity] {
        queriedLocations.filter { $0.home?.id == collection.homeID }
    }

    private var locationPathByID: [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: availableLocations.map { location in
                (location.id, location.pathDisplayName)
            }
        )
    }

    private func bellCardButton(_ bell: BellEntity) -> some View {
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
        .contextMenu {
            bellCardContextMenu(for: bell)
        } preview: {
            BellCardContextPreview(bell: bell, repository: repository)
        }
    }

    @ViewBuilder
    private func bellCardContextMenu(for bell: BellEntity) -> some View {
        Button {
            bellPendingMove = bell
        } label: {
            Label(String(localized: "bell.context.move"), systemImage: "folder")
        }

        Button {
            duplicateBell(bell)
        } label: {
            Label(String(localized: "common.duplicate"), systemImage: "plus.square.on.square")
        }

        ShareLink(
            item: bellShareText(for: bell),
            preview: SharePreview(bell.title)
        ) {
            Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
        }

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

    private func moveBell(_ bell: BellEntity, to locationID: UUID?) {
        bell.location = locationID.flatMap { locationsByID[$0] }
        try? modelContext.save()
        emitFeedback(.success)
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
