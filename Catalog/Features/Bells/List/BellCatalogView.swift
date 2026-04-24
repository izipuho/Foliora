import SwiftUI
import SwiftData
import UIKit

private enum SummaryCountKind: String {
    case bells
    case materials
    case countries
    case cities
    case members

    var resource: LocalizedStringResource {
        "collection.count.\(self.rawValue)"
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

enum BellOrderMode: String, CaseIterable, Hashable {
        case title = "title"
        case newestFirst = "newest_first"
        case oldestFirst = "oldest_first"
        case geography = "geography"
        case acquisitionYear = "acquisition_year"
        case storage = "storage"

        var title: String {
            String(localized: "bell_catalog.sort.\(rawValue)")
        }
    }

enum BellSummaryFilter: Hashable {
    case all
    case withOrigin
    case missingOrigin
    case withYear
    case missingYear
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
        case .withYear:
            return String(localized: "bell_catalog.summary.with_year")
        case .missingYear:
            return String(localized: "bell_catalog.filter_summary.missing_year")
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
    @Environment(\.modelContext) private var modelContext
    @Binding var layoutMode: BellGridLayoutMode
    @Binding var orderMode: BellOrderMode
    @Binding var summaryFilter: BellSummaryFilter?
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
    @Namespace private var bellGridTransitionNamespace
    @Namespace private var bellDetailZoomNamespace

    init(
        collection: CollectionSummary,
        repository: any CatalogRepository,
        collaborators: [Collaborator],
        layoutMode: Binding<BellGridLayoutMode> = .constant(.mini),
        orderMode: Binding<BellOrderMode> = .constant(.newestFirst),
        summaryFilter: Binding<BellSummaryFilter?> = .constant(nil)
    ) {
        self.repository = repository
        self.collaborators = collaborators
        self.collection = collection
        self._layoutMode = layoutMode
        self._orderMode = orderMode
        self._summaryFilter = summaryFilter
        let collectionID = Optional(collection.id)
        _queriedBells = Query(
            filter: #Predicate<BellEntity> { bell in
                bell.collection?.id == collectionID
            },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        _queriedLocations = Query()
        _queriedHomes = Query()
    }

    private var themeColors: [Color] {
        collection.backgroundStyle.screenColors
    }

    private var usesGroupedSections: Bool {
        viewModel.usesGroupedSections
    }

    private var viewModel: BellCatalogViewModel {
        BellCatalogViewModel(
            bellRecords: queriedBells,
            orderMode: orderMode,
            summaryFilter: summaryFilter,
            searchText: ""
        )
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
        viewModel.filteredBells.first(where: { $0.id == bellID })
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
                bells: viewModel.filteredBells,
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
        .onChange(of: orderMode) { _, _ in
            accumulatedMagnificationDelta = 0
            lastGestureMagnification = nil
            activeLayoutThresholdDirection = nil
            visualScale = 1
            pinchOriginBellID = nil
        }
        .onChange(of: summaryFilter) { _, _ in
            accumulatedMagnificationDelta = 0
            lastGestureMagnification = nil
            activeLayoutThresholdDirection = nil
            visualScale = 1
            pinchOriginBellID = nil
        }
    }

    private func unifiedFeedContent(
        bells: [BellEntity],
        screenWidth: CGFloat,
        screenHeight: CGFloat
    ) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: usesGroupedSections ? [.sectionHeaders] : []) {
                    Color.clear
                        .frame(height: 0)
                        .id("bell-grid-top")

                    dashboardHeader(screenHeight: screenHeight)

                    if let summaryFilter, summaryFilter != .all {
                        activeSummaryFilterSection
                    }

                    if bells.isEmpty {
                        emptyBellsGridState(
                            title: LocalizedStringKey(String(localized: "bell_catalog.empty.title")),
                            description: LocalizedStringKey(String(localized: "bell_catalog.empty.description"))
                        )
                    } else if usesGroupedSections {
                        groupedBellSectionsContent(
                            sections: viewModel.groupedSections(from: bells),
                            screenWidth: screenWidth,
                            scrollProxy: scrollProxy
                        )
                        .scaleEffect(visualScale, anchor: .center)
                    } else {
                        LazyVGrid(columns: gridColumns(forScreenWidth: screenWidth), spacing: layoutMode.spacing) {
                            ForEach(bells) { bell in
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
            .onChange(of: summaryFilter) { _, _ in
                if case .some(.tag(_)) = summaryFilter {
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

            Text(String.localizedStringWithFormat(String(localized: "bell_catalog.items.filtered_by_tag"), summaryFilter?.title() ?? ""))
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button(String(localized: "common.clear")) {
                summaryFilter = nil
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(collection.backgroundStyle.accentColor)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.medium, style: .continuous))
    }

    private func dashboardHeader(screenHeight: CGFloat) -> some View {
        let headerHeight = min(max(screenHeight * 0.36, 220), 320)

        return VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    dashboardMetricChip(
                        title: String(localized: "bell_catalog.dashboard.total"),
                        value: "\(viewModel.bellRecords.count)",
                        systemImage: "bell.fill"
                    ) {
                        summaryFilter = nil
                    }

                    dashboardMetricChip(
                        title: String(localized: "bell_catalog.dashboard.countries"),
                        value: "\(viewModel.countryCount)",
                        systemImage: "globe.europe.africa.fill"
                    ) {
                        summaryFilter = .withOrigin
                    }

                    dashboardMetricChip(
                        title: String(localized: "bell_catalog.dashboard.cities"),
                        value: "\(viewModel.cityCount)",
                        systemImage: "building.2.fill"
                    ) {
                        summaryFilter = .withCity
                    }
                }
            }
            .scrollClipDisabled()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    DashboardTopGeographyCard(
                        countryName: topGeography?.name ?? String(localized: "common.unknown"),
                        flag: topGeography?.flag ?? "🌍",
                        countText: topGeographyCountText,
                        tint: collection.backgroundStyle.accentColor,
                        action: {
                            guard !topGeographyEntries.isEmpty else { return }
                            isPresentingTopGeographyPopover = true
                        }
                    )
                    .popover(isPresented: $isPresentingTopGeographyPopover) {
                        TopGeographyPopover(
                            entries: topGeographyEntries,
                            onSelect: { country in
                                isPresentingTopGeographyPopover = false
                                focusGeography(country: country)
                            }
                        )
                    }

                    DashboardDataHealthCard(
                        progress: dataHealthProgress,
                        tint: collection.backgroundStyle.accentColor
                    ) {
                        isPresentingDataHealthPopover = true
                    }
                    .popover(isPresented: $isPresentingDataHealthPopover) {
                        DataHealthPopover(
                            entries: dataHealthEntries,
                            onSelect: { filter in
                                isPresentingDataHealthPopover = false
                                summaryFilter = filter
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

    private var dataHealthProgress: Double {
        guard !viewModel.bellRecords.isEmpty else { return 0 }
        let completeFields = viewModel.bellsWithOriginCount + viewModel.bellsWithAcquiredYearCount + viewModel.bellsWithStorageCount + viewModel.bellsWithNotesCount + viewModel.bellsWithTagsCount
        let totalFields = viewModel.bellRecords.count * 5
        return min(max(Double(completeFields) / Double(totalFields), 0), 1)
    }

    private var dataHealthEntries: [DataHealthEntry] {
        [
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.with_origin"),
                countText: "\(viewModel.bellsWithOriginCount)/\(viewModel.bellRecords.count)",
                filter: .missingOrigin
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.with_year"),
                countText: "\(viewModel.bellsWithAcquiredYearCount)/\(viewModel.bellRecords.count)",
                filter: .missingYear
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.with_storage"),
                countText: "\(viewModel.bellsWithStorageCount)/\(viewModel.bellRecords.count)",
                filter: .missingStorage
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.with_notes"),
                countText: "\(viewModel.bellsWithNotesCount)/\(viewModel.bellRecords.count)",
                filter: .missingNotes
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.with_tags"),
                countText: "\(viewModel.bellsWithTagsCount)/\(viewModel.bellRecords.count)",
                filter: .missingTags
            )
        ]
    }

    private var topGeography: (name: String, flag: String, count: Int)? {
        guard let topCountry = viewModel.topCountries.first else { return nil }
        let countryCode = viewModel.bellRecords
            .first(where: { $0.countryName.localizedCaseInsensitiveCompare(topCountry.0) == .orderedSame })?
            .originPlace?
            .countryCode ?? ""

        return (
            name: topCountry.0,
            flag: flagEmoji(for: countryCode),
            count: topCountry.1
        )
    }

    private var topGeographyEntries: [TopGeographyEntry] {
        Array(viewModel.topCountries.prefix(5)).map { row in
            let countryCode = viewModel.bellRecords
                .first(where: { $0.countryName.localizedCaseInsensitiveCompare(row.0) == .orderedSame })?
                .originPlace?
                .countryCode ?? ""

            return TopGeographyEntry(
                country: row.0,
                flag: flagEmoji(for: countryCode),
                countText: localizedCount(row.1, kind: .bells)
            )
        }
    }

    private var topGeographyCountText: String {
        guard let topGeography else { return String(localized: "bell_catalog.summary.no_origin_data") }
        return localizedCount(topGeography.count, kind: .bells)
    }

    private func focusTopGeography() {
        guard let topCountry = topGeography?.name else { return }
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

    //private var homeName: String {
    //    viewModel.homeName
    //}

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

    private enum AnalysisFeedback: Equatable {
        case success
        case warning

        var sensoryFeedback: SensoryFeedback {
            switch self {
            case .success:
                return .impact(weight: .light)
            case .warning:
                return .warning
            }
        }
    }

    private struct AnalysisFeedbackEvent: Equatable {
        let kind: AnalysisFeedback
        let token: Int
    }

    let collection: CollectionSummary
    let repository: any CatalogRepository
    let startSection: StartSection?
    let initialAnalysisImage: UIImage?
    let onSave: (BellRecord) -> Void
    @Query private var queriedLocations: [LocationEntity]
    @Query private var queriedBells: [BellEntity]

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
    @State private var analysisFeedbackEvent: AnalysisFeedbackEvent?
    @State private var analysisFeedbackToken = 0
    @State private var photoAnalysis = BellPhotoAnalysisController()
    @State private var didStartInitialAnalysis = false
    private let existingBellID: UUID?
    private let existingCreatedAt: Date?
    private let editorItemID: UUID

    private let acquiredYearOptions = [String(localized: "editor.acquired_year.none")] + Array(1900...Calendar.current.component(.year, from: .now)).reversed().map(String.init)

    private var availableLocations: [Location] {
        queriedLocations.map { entity in
            Location(
                id: entity.id,
                homeID: entity.home?.id ?? collection.homeID,
                parentLocationID: entity.parent?.id,
                kind: entity.kind,
                name: entity.name,
                notes: entity.notes
            )
        }
    }

    private var availablePlaces: [Place] {
        let places = queriedBells
            .compactMap { bell -> Place? in
                guard let place = bell.originPlace else { return nil }
                return Place(
                    id: place.id,
                    displayName: place.displayName,
                    countryCode: place.countryCode,
                    countryName: place.countryName,
                    regionName: place.regionName,
                    cityName: place.cityName,
                    latitude: place.latitude,
                    longitude: place.longitude
                )
            }

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
        initialAnalysisImage: UIImage? = nil,
        startSection: StartSection? = nil,
        onSave: @escaping (BellRecord) -> Void
    ) {
        self.collection = collection
        self.repository = repository
        self.startSection = startSection
        self.initialAnalysisImage = initialAnalysisImage
        self.onSave = onSave
        self.existingBellID = bell?.id
        self.existingCreatedAt = bell?.createdAt
        self.editorItemID = bell?.id ?? UUID()
        let homeID = Optional(collection.homeID)
        let collectionID = Optional(collection.id)
        _queriedLocations = Query(
            filter: #Predicate<LocationEntity> { location in
                location.home?.id == homeID
            },
            sort: [SortDescriptor(\.name)]
        )
        _queriedBells = Query(
            filter: #Predicate<BellEntity> { bell in
                bell.collection?.id == collectionID
            },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
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
                            mediaAssets: $mediaAssets,
                            analysisHighlightedAssetID: photoAnalysis.isAnalyzing ? firstPhotoAssetID : nil
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
                                if !photoAnalysis.suggestions.recognizedText.isEmpty {
                                    PhotoRecognizedTextBlock(textFeatures: photoAnalysis.suggestions.recognizedText)
                                }

                                if let titleSuggestion = photoAnalysis.suggestions.title {
                                    PhotoSuggestionRow(
                                        title: String(localized: "editor.photo_analysis.title"),
                                        suggestedValue: titleSuggestion.value,
                                        confidence: titleSuggestion.confidence,
                                        onAccept: {
                                            title = titleSuggestion.value
                                            photoAnalysis.dismiss(.title)
                                        }
                                    )
                                }

                                if let notesSuggestion = photoAnalysis.suggestions.notes {
                                    PhotoSuggestionRow(
                                        title: String(localized: "editor.photo_analysis.notes"),
                                        suggestedValue: notesSuggestion.value,
                                        confidence: notesSuggestion.confidence,
                                        onAccept: {
                                            notes = notesSuggestion.value
                                            photoAnalysis.dismiss(.notes)
                                        }
                                    )
                                }

                                if let materialSuggestion = photoAnalysis.suggestions.material {
                                    PhotoSuggestionRow(
                                        title: String(localized: "editor.photo_analysis.material"),
                                        suggestedValue: materialSuggestionLabel(materialSuggestion),
                                        confidence: materialSuggestion.confidence,
                                        onAccept: {
                                            material = materialSuggestion.value
                                            if materialSuggestion.value == .other {
                                                customMaterialName = photoAnalysis.suggestions.customMaterialName?.value ?? ""
                                                photoAnalysis.dismiss(.customMaterialName)
                                            } else {
                                                customMaterialName = ""
                                            }
                                            photoAnalysis.dismiss(.material)
                                        }
                                    )
                                }

                                if let conditionSuggestion = photoAnalysis.suggestions.condition {
                                    PhotoSuggestionRow(
                                        title: String(localized: "editor.photo_analysis.condition"),
                                        suggestedValue: conditionSuggestion.value.displayName,
                                        confidence: conditionSuggestion.confidence,
                                        onAccept: {
                                            condition = conditionSuggestion.value
                                            photoAnalysis.dismiss(.condition)
                                        }
                                    )
                                }

                                if let yearSuggestion = photoAnalysis.suggestions.suggestedYear {
                                    PhotoSuggestionRow(
                                        title: String(localized: "editor.photo_analysis.year"),
                                        suggestedValue: String(yearSuggestion.value),
                                        confidence: yearSuggestion.confidence,
                                        onAccept: {
                                            selectedAcquiredYearOption = String(yearSuggestion.value)
                                            photoAnalysis.dismiss(.suggestedYear)
                                        }
                                    )
                                }

                                if let geoSuggestion = photoAnalysis.suggestions.suggestedGeo {
                                    PhotoSuggestionRow(
                                        title: String(localized: "editor.photo_analysis.geo"),
                                        suggestedValue: geoSuggestion.value.name,
                                        confidence: geoSuggestion.confidence,
                                        onAccept: {
                                            selectedOriginPlace = place(from: geoSuggestion.value)
                                            photoAnalysis.dismiss(.suggestedGeo)
                                        }
                                    )
                                }

                                if !photoAnalysis.suggestions.suggestedTags.isEmpty {
                                    PhotoSuggestedTagsRow(
                                        title: String(localized: "editor.photo_analysis.tags"),
                                        suggestions: photoAnalysis.suggestions.suggestedTags,
                                        onAccept: { newValues in
                                            for value in newValues where !tags.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
                                                tags.append(value)
                                            }
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
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(String(localized: "common.cancel"))
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button { saveBell() } label: { Image(systemName: "checkmark") }
                        .disabled(!canSave)
                        .accessibilityLabel(String(localized: "common.save"))
                    }
                }
                .task {
                    startInitialPhotoAnalysisIfNeeded()
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
                .sensoryFeedback(trigger: analysisFeedbackEvent) { _, newValue in
                    newValue?.kind.sensoryFeedback
                }
                .onChange(of: photoAnalysis.isAnalyzing) { wasAnalyzing, isAnalyzing in
                    guard wasAnalyzing, !isAnalyzing else { return }
                    handlePhotoAnalysisCompletion()
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

    private func emitAnalysisFeedback(_ kind: AnalysisFeedback) {
        analysisFeedbackToken += 1
        analysisFeedbackEvent = AnalysisFeedbackEvent(kind: kind, token: analysisFeedbackToken)
    }

    private func handlePhotoAnalysisCompletion() {
        if photoAnalysis.suggestions.hasSuggestions {
            emitAnalysisFeedback(.success)
        }

        // Keep failures / empty results silent by default.
        // If the analysis flow is re-enabled and warning feedback is needed later,
        // emit `.warning` here in a more selective way.
    }

    private func startInitialPhotoAnalysisIfNeeded() {
        guard !didStartInitialAnalysis, existingBellID == nil, let initialAnalysisImage else { return }
        didStartInitialAnalysis = true
        photoAnalysis.analyze(image: initialAnalysisImage)
    }

    private var firstPhotoAssetID: UUID? {
        mediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first?
            .id
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

    private func place(from geoPoint: GeoPoint) -> Place {
        Place(
            id: UUID(),
            displayName: geoPoint.name,
            countryCode: "",
            countryName: geoPoint.name,
            regionName: nil,
            cityName: nil,
            latitude: geoPoint.latitude,
            longitude: geoPoint.longitude
        )
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
           let customMaterial = photoAnalysis.suggestions.customMaterialName?.value,
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

            HStack {
                Spacer()

                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel(String(localized: "common.apply"))
            }
        }
        .padding(.vertical, CatalogSpacing.micro)
    }

    private var confidenceLabel: String {
        "\(Int((confidence * 100).rounded()))%"
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
    let onAccept: ([String]) -> Void

    @State private var selectedValues: Set<String>

    init(
        title: String,
        suggestions: [SuggestedFieldValue<String>],
        onAccept: @escaping ([String]) -> Void
    ) {
        self.title = title
        self.suggestions = suggestions
        self.onAccept = onAccept
        _selectedValues = State(initialValue: Set(suggestions.map(\.value)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            TagFlowLayout(spacing: 8) {
                ForEach(selectedSuggestions, id: \.value) { suggestion in
                    PhotoSuggestedTagChip(tag: suggestion.value) {
                        selectedValues.remove(suggestion.value)
                    }
                }
            }

            HStack {
                Spacer()

                Button {
                    onAccept(suggestions.map(\.value).filter(selectedValues.contains))
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .disabled(selectedValues.isEmpty)
                .accessibilityLabel(String(localized: "common.apply"))
            }
        }
        .padding(.vertical, CatalogSpacing.micro)
    }

    private var selectedSuggestions: [SuggestedFieldValue<String>] {
        suggestions.filter { selectedValues.contains($0.value) }
    }
}

private struct PhotoSuggestedTagChip: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: CatalogSpacing.compact) {
            Text("#\(tag)")
                .font(.subheadline.weight(.medium))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "common.delete"))
        }
        .catalogPillPadding(.regular)
        .background(.thinMaterial, in: Capsule())
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

private struct DashboardDataHealthCard: View {
    let progress: Double
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(CatalogSemanticColors.separator, lineWidth: 8)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.subheadline.weight(.bold))
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "bell_catalog.dashboard.health"))
                        .font(.headline)
                    Text(String(localized: "bell_catalog.dashboard.health.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .frame(width: 240, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.section, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardTopGeographyCard: View {
    let countryName: String
    let flag: String
    let countText: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(flag)
                    .font(.system(size: 34))

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "bell_catalog.dashboard.top_geography"))
                        .font(.headline)
                    Text(countryName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(countText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.turn.down.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .padding()
            .frame(width: 240, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.section, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct TopGeographyEntry: Identifiable {
    let country: String
    let flag: String
    let countText: String

    var id: String { country }
}

private struct TopGeographyPopover: View {
    let entries: [TopGeographyEntry]
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Button {
                    onSelect(entry.country)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.country)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(entry.countText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(String(localized: "bell_catalog.dashboard.top_geography"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

private struct DataHealthEntry: Identifiable {
    let title: String
    let countText: String
    let filter: BellSummaryFilter

    var id: String { title }
}

private struct DataHealthPopover: View {
    let entries: [DataHealthEntry]
    let onSelect: (BellSummaryFilter) -> Void

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Button {
                    onSelect(entry.filter)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(entry.countText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(String(localized: "bell_catalog.dashboard.health"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
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
