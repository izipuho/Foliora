import DesignSystem
import SwiftUI
import SwiftData

private enum BellCatalogFeedback: Equatable {
    case success
    case warning

    var sensoryFeedback: SensoryFeedback {
        switch self {
        case .success:
            return .success
        case .warning:
            return .warning
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
        case .missingMaterial:
            return String(localized: "bell_catalog.summary.missing_material")
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
    let repository: any CatalogRepository
    let collaborators: [Collaborator]
    let collection: CollectionSummary?
    let onBellSelected: ((BellEntity) -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Binding var layoutMode: BellGridLayoutMode
    @Binding var orderMode: BellOrderMode
    @Binding var filters: BellFilters
    @Query private var bells: [BellEntity]
    @Query private var queriedLocations: [LocationEntity]
    @Query private var queriedHomes: [HomeEntity]
    @State private var bellPendingMove: BellEntity?
    @State private var bellPendingDeletion: BellEntity?
    @State private var isPresentingDeleteConfirmation = false
    @State private var persistenceError: Error?
    @State private var activeJumpPopoverSectionID: String?
    @State private var pendingScrollTargetID: String?
    @State private var isSelectionModeEnabled = false
    @State private var selectedBellIDs: Set<UUID> = []
    @State private var feedbackEvent: BellCatalogFeedbackEvent?
    @State private var feedbackToken = 0
    @State private var scrollRequestToken = 0
    @State private var didEndActivePinchGesture = false
    @StateObject private var viewModel: BellCatalogViewModel
    @Namespace private var bellGridTransitionNamespace

    init(
        collection: CollectionSummary?,
        repository: any CatalogRepository,
        collaborators: [Collaborator],
        layoutMode: Binding<BellGridLayoutMode> = .constant(.mini),
        orderMode: Binding<BellOrderMode> = .constant(.newestFirst),
        filters: Binding<BellFilters> = .constant(BellFilters()),
        onBellSelected: ((BellEntity) -> Void)? = nil
    ) {
        self.repository = repository
        self.collaborators = collaborators
        self.collection = collection
        self.onBellSelected = onBellSelected
        self._layoutMode = layoutMode
        self._orderMode = orderMode
        self._filters = filters
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
                filters: filters.wrappedValue
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

    private func layoutMagnifyGesture() -> some Gesture {
        MagnifyGesture()
            .onEnded { value in
                let delta = value.magnification - 1
                let threshold = zoomThreshold(forVelocity: value.velocity)

                if delta >= threshold {
                    zoomOutLayout()
                } else if delta <= -threshold {
                    zoomInLayout()
                }

                didEndActivePinchGesture = true
            }
    }

    private func zoomThreshold(forVelocity velocity: CGFloat) -> CGFloat {
        let baseThreshold: CGFloat = 0.12
        let velocityReduction = min(abs(velocity) * 0.015, 0.05)
        return max(0.05, baseThreshold - velocityReduction)
    }

    private func emitFeedback(_ kind: BellCatalogFeedback) {
        feedbackToken += 1
        feedbackEvent = BellCatalogFeedbackEvent(kind: kind, token: feedbackToken)
    }

    private func resetPinchState() {
        didEndActivePinchGesture = false
    }

    private func requestScroll(to targetID: String) {
        pendingScrollTargetID = targetID
        scrollRequestToken += 1
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
                screenHeight: proxy.size.height,
                bottomSafeAreaInset: proxy.safeAreaInsets.bottom
            )
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
        .alert(
            "Error",
            isPresented: Binding(
                get: { persistenceError != nil },
                set: { isPresented in
                    if !isPresented {
                        persistenceError = nil
                    }
                }
            ),
            presenting: persistenceError
        ) { _ in
            Button("OK") {
                persistenceError = nil
            }
        } message: { error in
            Text(error.localizedDescription)
        }
        .sensoryFeedback(trigger: feedbackEvent) { _, newValue in
            newValue?.kind.sensoryFeedback
        }
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
            viewModel.updateSource(bells: bells)
            viewModel.updateContext(orderMode: orderMode)
            viewModel.updateContext(filters: filters)
        }
        .onChange(of: bells) { _, newValue in
            viewModel.updateSource(bells: newValue)
            pruneSelectionToVisibleBells()
        }
        .onChange(of: orderMode) { _, newValue in
            activeJumpPopoverSectionID = nil
            DispatchQueue.main.async {
                viewModel.updateContext(orderMode: newValue)
                if let pendingScrollTargetID {
                    requestScroll(to: pendingScrollTargetID)
                } else {
                    requestScroll(to: "bell-grid-top")
                }
                resetPinchState()
            }
        }
        .onChange(of: filters) { _, newValue in
            viewModel.updateContext(filters: newValue)
            pruneSelectionToVisibleBells()
            if newValue.activeTagFilter != nil {
                requestScroll(to: "bell-grid-top")
            }
            resetPinchState()
        }
    }

    private func unifiedFeedContent(
        displayModel: BellCatalogDisplayModel,
        screenHeight: CGFloat,
        bottomSafeAreaInset: CGFloat
    ) -> some View {
        return ScrollViewReader { scrollProxy in
            BellGridContainerView(layoutMode: layoutMode, bottomContentMargin: scrollContentBottomInset) { cardSize, gridMetrics, cardMetrics in
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: displayModel.layout.isGrouped ? [.sectionHeaders] : []) {
                    Color.clear
                        .frame(height: 0)
                        .id("bell-grid-top")

                    if !isSelectionModeEnabled {
                        dashboardHeader(displayModel: displayModel, screenHeight: screenHeight)
                    }

                    if hasActiveFilter {
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
                            cardSize: cardSize,
                            gridMetrics: gridMetrics,
                            cardMetrics: cardMetrics,
                            scrollProxy: scrollProxy
                        )
                    case .flat(let bells):
                        bellGridView(
                            bells: bells,
                            cardSize: cardSize,
                            gridMetrics: gridMetrics,
                            cardMetrics: cardMetrics
                        )
                    }
                }
                .simultaneousGesture(
                    layoutMagnifyGesture()
                )
                .animation(.snappy(duration: 0.24), value: layoutMode)
            }
            .background(
                LinearGradient(
                    colors: themeColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .onChange(of: scrollRequestToken) { _, _ in
                guard let targetID = pendingScrollTargetID else { return }

                withAnimation(.snappy(duration: 0.24)) {
                    scrollProxy.scrollTo(targetID, anchor: .top)
                }

                pendingScrollTargetID = nil
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelectionModeEnabled && !selectedVisibleBellIDs.isEmpty {
                    BellCatalogSelectionBottomPanel(
                        selectedCount: selectedVisibleBellIDs.count,
                        accentColor: catalogStyle.accentColor,
                        bottomSafeAreaInset: bottomSafeAreaInset,
                        onMove: {
                            bellPendingMove = selectedBells.first
                        },
                        onDelete: {
                            bellPendingDeletion = selectedBells.first
                            isPresentingDeleteConfirmation = bellPendingDeletion != nil
                        }
                    )
                        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: isSelectionModeEnabled)
            .animation(.easeInOut(duration: 0.22), value: selectedVisibleBellIDs.isEmpty)
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
        BellCatalogDashboardView(
            stats: displayModel.stats,
            accentColor: catalogStyle.accentColor,
            onFilterApply: setFilter,
            onGeographyFocus: focusGeography,
            onResetFilters: {
                filters = BellFilters()
            }
        )
        .frame(maxHeight: min(max(screenHeight * 0.36, 220), 320), alignment: .top)
    }

    private func focusGeography(country: String) {
        let targetID = "geography-\(country)"
        if orderMode != .geography {
            pendingScrollTargetID = targetID
            orderMode = .geography
        } else {
            requestScroll(to: targetID)
        }
    }

    @ViewBuilder
    private func groupedBellSectionsContent(
        sections: [BellGroupedSection],
        cardSize: CGSize,
        gridMetrics: BellGridLayoutMode.GridMetrics,
        cardMetrics: BellGridLayoutMode.CardMetrics,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        ForEach(sections) { section in
            let usesCabinetGroups = !section.cabinetGroups.isEmpty
            let usesJumpPopover = section.indexTitle == nil

            Section {
                if usesCabinetGroups {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(section.cabinetGroups) { cabinetGroup in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(cabinetGroup.title)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, CatalogSpacing.micro)

                                bellGridView(
                                    bells: cabinetGroup.bells,
                                    cardSize: cardSize,
                                    gridMetrics: gridMetrics,
                                    cardMetrics: cardMetrics
                                )
                            }
                        }
                    }
                } else {
                    bellGridView(
                        bells: section.bells,
                        cardSize: cardSize,
                        gridMetrics: gridMetrics,
                        cardMetrics: cardMetrics
                    )
                }
            } header: {
                BellGroupedSectionHeader(
                    title: section.title,
                    tint: catalogStyle.accentColor,
                    isJumpButton: usesJumpPopover,
                    action: {
                        activeJumpPopoverSectionID = section.id
                    }
                )
                .id(section.id)
                .popover(
                    isPresented: Binding(
                        get: { activeJumpPopoverSectionID == section.id && usesJumpPopover },
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

    private var visibleBells: [BellEntity] {
        switch displayModel.layout {
        case .empty:
            return []
        case .flat(let bells):
            return bells
        case .grouped(let sections):
            return sections.flatMap(\.allBells)
        }
    }

    private var visibleBellIDs: Set<UUID> {
        Set(visibleBells.map(\.id))
    }

    private var selectedVisibleBellIDs: Set<UUID> {
        selectedBellIDs.intersection(visibleBellIDs)
    }

    private var selectedBells: [BellEntity] {
        let selectedVisibleBellIDs = selectedVisibleBellIDs
        return visibleBells.filter { selectedVisibleBellIDs.contains($0.id) }
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

    private func pruneSelectionToVisibleBells() {
        selectedBellIDs.formIntersection(visibleBellIDs)

        if selectedBellIDs.isEmpty {
            isSelectionModeEnabled = false
        }
    }

    private func cancelSelectionMode() {
        withAnimation(.snappy(duration: 0.2)) {
            isSelectionModeEnabled = false
            selectedBellIDs.removeAll()
        }
    }

    private func bellGridView(
        bells: [BellEntity],
        cardSize: CGSize,
        gridMetrics: BellGridLayoutMode.GridMetrics,
        cardMetrics: BellGridLayoutMode.CardMetrics
    ) -> some View {
        BellGridView(
            bells: bells,
            layoutMode: layoutMode,
            cardSize: cardSize,
            gridMetrics: gridMetrics,
            cardMetrics: cardMetrics,
            selectedBellIDs: selectedBellIDs,
            isSelectionModeEnabled: isSelectionModeEnabled,
            onTap: handleBellCardTap,
            onSelect: { bell in
                enterSelectionMode(with: bell.id)
            },
            contextMenu: { bell in
                bellCardContextMenu(for: bell)
            },
            preview: { bell in
                BellCardContextPreview(bell: bell, repository: repository)
            }
        )
    }

    private func handleBellCardTap(_ bell: BellEntity) {
        if didEndActivePinchGesture {
            didEndActivePinchGesture = false
            return
        }

        if isSelectionModeEnabled {
            toggleBellSelection(bell.id)
        } else if let onBellSelected {
            onBellSelected(bell)
        }
    }

    @ViewBuilder
    private func bellCardContextMenu(for bell: BellEntity) -> some View {
        Button {
            bellPendingMove = bell
        } label: {
            Label(String(localized: "bell.context.move"), systemImage: "folder")
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

        if saveModelContext() {
            emitFeedback(.success)
        }
    }

    private func moveBells(_ bells: [BellEntity], to locationID: UUID?) {
        let location = locationID.flatMap { locationsByID[$0] }
        for bell in bells {
            bell.location = location
        }

        if saveModelContext() {
            emitFeedback(.success)
        }
    }

    private func deleteBells(_ bells: [BellEntity]) {
        for bell in bells {
            modelContext.delete(bell)
        }

        if saveModelContext() {
            emitFeedback(.warning)
        }
    }

    private func saveModelContext() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            persistenceError = error
            assertionFailure("modelContext.save failed: \(error)")
            return false
        }
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
            CatalogPill(
                padding: .prominent,
                backgroundStyle: AnyShapeStyle(isSelected ? tint : CatalogMediaContrast.overlayChipMuted),
                foregroundStyle: AnyShapeStyle(isSelected ? Color.white : Color.primary)
            ) {
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
        }
    }
}

private struct SummaryPill: View {
    let systemImage: String
    let title: String
    let tint: Color

    var body: some View {
        CatalogPill(
            padding: .regular,
            backgroundStyle: AnyShapeStyle(tint.opacity(0.12))
        ) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
        }
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
            .catalogGlassPanel(strokeColor: CatalogMediaContrast.glassStroke)
    }
}

private extension View {
    func summaryGlassCard() -> some View {
        modifier(SummaryGlassCardModifier())
    }
}

struct BellEntityDetailSheetContainer: View {
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
                Section(String(localized: "common.field.storage")) {
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
