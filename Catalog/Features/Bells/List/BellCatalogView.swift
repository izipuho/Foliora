import SwiftUI
import CoreData

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
    let collection: CollectionSummary?
    let sharingState: CollectionSharingState
    let onBellSelected: ((UUID) -> Void)?
    let canEditCollection: Bool
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Binding var layoutMode: BellGridLayoutMode
    @Binding var orderMode: BellOrderMode
    @Binding var filters: BellFilters
    @State private var catalogSnapshot = BellCatalogSnapshot()
    @State private var bellPendingMove: BellListItem?
    @State private var bellPendingDeletion: BellListItem?
    @State private var isPresentingDeleteConfirmation = false
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
        layoutMode: Binding<BellGridLayoutMode> = .constant(.mini),
        orderMode: Binding<BellOrderMode> = .constant(.newestFirst),
        filters: Binding<BellFilters> = .constant(BellFilters()),
        sharingState: CollectionSharingState,
        canEditCollection: Bool,
        onBellSelected: ((UUID) -> Void)? = nil
    ) {
        self.repository = repository
        self.collection = collection
        self.sharingState = sharingState
        self.onBellSelected = onBellSelected
        self.canEditCollection = canEditCollection
        self._layoutMode = layoutMode
        self._orderMode = orderMode
        self._filters = filters
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

    private var locationsByID: [UUID: Location] {
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
            reloadCatalogSnapshot()
            viewModel.updateContext(orderMode: orderMode)
            viewModel.updateContext(filters: filters)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: managedObjectContext
        )) { _ in
            reloadCatalogSnapshot()
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
                if canEditCollection && isSelectionModeEnabled && !selectedVisibleBellIDs.isEmpty {
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
            sharingState: sharingState,
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

    private var availableLocations: [Location] {
        guard let collection else { return catalogSnapshot.locations }
        return catalogSnapshot.locations.filter { $0.homeID == collection.homeID }
    }

    private var locationPathByID: [UUID: String] {
        catalogSnapshot.locationPathByID.filter { id, _ in
            availableLocations.contains { $0.id == id }
        }
    }

    private func reloadCatalogSnapshot() {
        catalogSnapshot = BellCatalogSnapshot(context: managedObjectContext, collectionID: collection?.id)
        viewModel.updateSource(bells: catalogSnapshot.bells)
        pruneSelectionToVisibleBells()
    }

    private var visibleBells: [BellListItem] {
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

    private var selectedBells: [BellListItem] {
        let selectedVisibleBellIDs = selectedVisibleBellIDs
        return visibleBells
            .filter { selectedVisibleBellIDs.contains($0.id) }
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
        bells: [BellListItem],
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
            onSelect: canEditCollection ? { bell in
                enterSelectionMode(with: bell.id)
            } : nil,
            contextMenu: canEditCollection ? { bell in
                AnyView(bellCardContextMenu(for: bell))
            } : nil
        )
    }

    private func handleBellCardTap(_ bell: BellListItem) {
        if didEndActivePinchGesture {
            didEndActivePinchGesture = false
            return
        }

        if isSelectionModeEnabled {
            toggleBellSelection(bell.id)
        } else if let onBellSelected {
            onBellSelected(bell.id)
        }
    }

    @ViewBuilder
    private func bellCardContextMenu(for bell: BellListItem) -> some View {
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

    private func moveBells(_ bells: [BellListItem], to locationID: UUID?) {
        guard canEditCollection else { return }

        let location = locationID.flatMap { locationsByID[$0] }
        for bell in bells {
            guard let record = catalogSnapshot.recordsByID[bell.id] else { continue }
            repository.saveBellRecord(record.moving(to: location, path: locationID.flatMap { locationPathByID[$0] } ?? ""))
        }

        reloadCatalogSnapshot()
        emitFeedback(.success)
    }

    private func deleteBells(_ bells: [BellListItem]) {
        guard canEditCollection else { return }

        for bell in bells {
            repository.deleteBellRecord(bellID: bell.id)
        }

        reloadCatalogSnapshot()
        emitFeedback(.warning)
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

struct BellCatalogDetailSheetContainer: View {
    let bellID: UUID
    let repository: any CatalogRepository
    let canEditCollection: Bool
    @Environment(\.managedObjectContext) private var managedObjectContext
    @State private var bell: BellRecord?

    init(bellID: UUID, repository: any CatalogRepository, canEditCollection: Bool) {
        self.bellID = bellID
        self.repository = repository
        self.canEditCollection = canEditCollection
    }

    var body: some View {
        NavigationStack {
            if let bellBinding {
                BellDetailView(
                    bell: bellBinding,
                    repository: repository,
                    canEditCollection: canEditCollection
                )
            } else {
                ContentUnavailableView("bel.not_found", systemImage: "bell.slash")
            }
        }
        .presentationBackground(.clear)
        .task(id: bellID) {
            reloadBell()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: managedObjectContext
        )) { _ in
            reloadBell()
        }
    }

    private var bellBinding: Binding<BellRecord>? {
        guard let currentBell = bell else { return nil }

        return Binding(
            get: {
                bell ?? currentBell
            },
            set: {
                bell = $0
            }
        )
    }

    private func reloadBell() {
        let snapshot = CoreDataBellLookupSnapshotLoader(context: managedObjectContext).loadSnapshot()
        bell = snapshot.bells.first { $0.id == bellID }
    }
}

private struct BellQuickMoveSheet: View {
    let bell: BellListItem
    let locations: [Location]
    let locationPathByID: [UUID: String]
    let onSave: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedLocationID: UUID?

    init(
        bell: BellListItem,
        locations: [Location],
        locationPathByID: [UUID: String],
        onSave: @escaping (UUID?) -> Void
    ) {
        self.bell = bell
        self.locations = locations
        self.locationPathByID = locationPathByID
        self.onSave = onSave
        _selectedLocationID = State(initialValue: bell.locationID)
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
        locations
    }
}
