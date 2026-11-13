import SwiftUI
import CoreData

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

/// Displays the bell catalog view interface.
struct BellCatalogView: View {
    let repository: any AppRepository
    let collection: CollectionSummary
    let catalogSnapshot: CatalogSnapshot?
    let sharingState: CollectionSharingState
    let sharingService: (any CollectionSharingService)?
    let onSharingChanged: () -> Void
    let onBellSelected: ((UUID) -> Void)?
    let canEditCollection: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Binding var layoutMode: CatalogCardLayoutMode
    @Binding var orderMode: BellOrderMode
    @Binding var filters: BellFilters
    @Binding var cardManagement: CatalogCardManagementState<BellCatalogItem>
    @State private var activeJumpPopoverSectionID: String?
    @State private var pendingScrollTargetID: String?
    @State private var moveFeedbackToken = 0
    @State private var deleteFeedbackToken = 0
    @State private var scrollRequestToken = 0
    @State private var isFavoritesCollapsed = false
    @StateObject private var viewModel: BellCatalogViewModel

    init(
        collection: CollectionSummary,
        repository: any AppRepository,
        catalogSnapshot: CatalogSnapshot?,
        layoutMode: Binding<CatalogCardLayoutMode>,
        orderMode: Binding<BellOrderMode>,
        filters: Binding<BellFilters>,
        cardManagement: Binding<CatalogCardManagementState<BellCatalogItem>>,
        sharingState: CollectionSharingState,
        sharingService: (any CollectionSharingService)? = nil,
        onSharingChanged: @escaping () -> Void = {},
        canEditCollection: Bool,
        onBellSelected: ((UUID) -> Void)? = nil
    ) {
        self.repository = repository
        self.collection = collection
        self.catalogSnapshot = catalogSnapshot
        self.sharingState = sharingState
        self.sharingService = sharingService
        self.onSharingChanged = onSharingChanged
        self.onBellSelected = onBellSelected
        self.canEditCollection = canEditCollection
        self._layoutMode = layoutMode
        self._orderMode = orderMode
        self._filters = filters
        self._cardManagement = cardManagement
        _viewModel = StateObject(
            wrappedValue: BellCatalogViewModel(
                orderMode: orderMode.wrappedValue,
                filters: filters.wrappedValue
            )
        )
    }

    private var catalogStyle: CollectionBackgroundStyle {
        collection.backgroundStyle
    }

    private var displayModel: BellCatalogDisplayModel {
        viewModel.displayModel
    }

    private var hasActiveFilter: Bool {
        !filters.isEmpty
    }

    private var favoriteBells: [BellCatalogItem] {
        sourceBells.filter(\.isFavorite)
    }

    private var sourceBells: [BellCatalogItem] {
        catalogSnapshot?.bells.filter { $0.collectionID == collection.id } ?? []
    }

    private var storageContext: CatalogStorageContext {
        CatalogStorageContext(snapshot: catalogSnapshot, collection: collection)
    }

    private func setFilter(_ filter: BellPresenceFilter) {
        filters = BellFilters(presence: [filter])
    }

    private func setFilter(_ filter: BellAttributeFilter) {
        filters = BellFilters(attributes: [filter])
    }

    private func requestScroll(to targetID: String) {
        pendingScrollTargetID = targetID
        scrollRequestToken += 1
    }

    var body: some View {
        unifiedFeedContent(displayModel: displayModel)
            .modifier(
                CatalogCardManagementModifier(
                    state: $cardManagement,
                    visibleItems: visibleBells,
                    snapshot: catalogSnapshot,
                    collection: collection,
                    currentLocationID: { $0.locationID },
                    moveTitle: String(localized: "bell.context.move"),
                    deleteTitle: String(localized: "bell.context.delete.title"),
                    deleteMessage: String(localized: "bell.context.delete.message"),
                    selectedTitle: { count in
                        String.localizedStringWithFormat(
                            String(localized: "bell_catalog.selection.selected_count"),
                            count
                        )
                    },
                    canEdit: canEditCollection,
                    tint: catalogStyle.accentColor,
                    onSaveHome: { home, locations in
                        repository.saveHome(home)
                        repository.saveLocations(locations, in: home.id)
                    },
                    onMove: moveBells,
                    onDelete: deleteBells,
                    onBatchEdit: batchEditBells
                )
            )
            .sensoryFeedback(.success, trigger: moveFeedbackToken)
            .sensoryFeedback(.warning, trigger: deleteFeedbackToken)
            .onAppear {
                viewModel.updateContext(orderMode: orderMode)
                viewModel.updateContext(filters: filters)
                updateSourceBells(sourceBells)
            }
            .onChange(of: sourceBells) { _, newValue in
                updateSourceBells(newValue)
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
                }
            }
            .onChange(of: filters) { _, newValue in
                viewModel.updateContext(filters: newValue)
                cardManagement.pruneSelection(to: visibleBells)
                if newValue.activeTagFilter != nil {
                    requestScroll(to: "bell-grid-top")
                }
            }
    }

    private func unifiedFeedContent(displayModel: BellCatalogDisplayModel) -> some View {
        return ScrollViewReader { scrollProxy in
            CatalogCardGrid(layoutMode: layoutMode, usesGridLayout: false) { cardSize, gridMetrics, cardMetrics in
                LazyVStack(alignment: .leading, spacing: CatalogMetrics.Spacing.lg, pinnedViews: displayModel.layout.isGrouped ? [.sectionHeaders] : []) {
                    Color.clear
                        .frame(height: 0)
                        .id("bell-grid-top")

                    if !cardManagement.isSelectionModeEnabled {
                        dashboardHeader(displayModel: displayModel)
                    }

                    if !cardManagement.isSelectionModeEnabled && !favoriteBells.isEmpty {
                        favoritesSection(
                            bells: favoriteBells,
                            screenWidth: stripScreenWidth(cardSize: cardSize, gridMetrics: gridMetrics)
                        )

                        catalogSectionHeader
                    }

                    if hasActiveFilter {
                        activeSummaryFilterSection
                    }

                    switch displayModel.layout {
                    case .empty:
                        CatalogEmptyStateView(
                            systemImage: "bell.slash",
                            title: "bell_catalog.empty.title",
                            message: "bell_catalog.empty.description"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    case .grouped(let sections):
                        groupedBellSectionsContent(
                            sections: sections,
                            layoutMetrics: (cardSize, gridMetrics, cardMetrics),
                            scrollProxy: scrollProxy
                        )
                    case .flat(let bells):
                        bellGridView(bells: bells, layoutMetrics: (cardSize, gridMetrics, cardMetrics))
                    }
                }
            }
            .background {
                CatalogBackgrounds.collection(
                    catalogStyle.accentColor,
                    scheme: colorScheme
                )
                .ignoresSafeArea()
            }
            //.background(
            //    LinearGradient(
            //        colors: themeColors,
            //        startPoint: .topLeading,
            //        endPoint: .bottomTrailing
            //    )
            //    .ignoresSafeArea()
            //)
            .onChange(of: scrollRequestToken) { _, _ in
                guard let targetID = pendingScrollTargetID else { return }

                withAnimation(.snappy(duration: 0.24)) {
                    scrollProxy.scrollTo(targetID, anchor: .top)
                }

                pendingScrollTargetID = nil
            }
        }
    }

    private var activeSummaryFilterSection: some View {
        HStack(spacing: CatalogMetrics.Spacing.sm) {
            Image(systemName: "tag.fill")
                .foregroundStyle(catalogStyle.accentColor)

            Text(String.localizedStringWithFormat(String(localized: "bell_catalog.items.filtered_by_tag"), filters.title ?? ""))
                .font(CatalogTypography.cardSubtitle)

            Spacer()

            Button(String(localized: "common.clear")) {
                filters = BellFilters()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(catalogStyle.accentColor)
        }
        .padding(CatalogMetrics.Spacing.md)
        .background(.ultraThinMaterial, in: CatalogShapes.medium)
    }

    private func dashboardHeader(displayModel: BellCatalogDisplayModel) -> some View {
        BellCatalogDashboardView(
            stats: displayModel.stats,
            accentColor: catalogStyle.accentColor,
            collection: collection,
            catalogSnapshot: catalogSnapshot,
            sharingState: sharingState,
            sharingService: sharingService,
            onSharingChanged: onSharingChanged,
            onBellSelected: onBellSelected,
            onFilterApply: setFilter,
            onResetFilters: {
                filters = BellFilters()
            }
        )
    }

    private func favoritesSection(bells: [BellCatalogItem], screenWidth: CGFloat) -> some View {
        CatalogCollapsibleCardSection(
            title: String(localized: "bell.catalog.favorites"),
            layoutMode: layoutMode,
            screenWidth: screenWidth,
            isCollapsed: $isFavoritesCollapsed
        ) { cardSize, cardMetrics in
            ForEach(bells, id: \.id) { bell in
                Button {
                    onBellSelected?(bell.id)
                } label: {
                    BellCardView(
                        bell: bell,
                        style: CatalogCardContentStyle.style(for: layoutMode),
                        cardSize: cardSize,
                        cardMetrics: cardMetrics
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var catalogSectionHeader: some View {
        CatalogSectionHeader(title: String(localized: "bell.catalog.title"))
    }

    private func stripScreenWidth(
        cardSize: CGSize,
        gridMetrics: CatalogCardLayoutMode.GridMetrics
    ) -> CGFloat {
        let totalSpacing = gridMetrics.spacing * CGFloat(max(gridMetrics.columnCount - 1, 0))
        return cardSize.width * CGFloat(gridMetrics.columnCount) + totalSpacing + CatalogCardLayoutMode.screenHorizontalPadding * 2
    }

    @ViewBuilder
    private func groupedBellSectionsContent(
        sections: [BellGroupedSection],
        layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        ForEach(sections) { section in
            let usesJumpPopover = section.indexTitle == nil

            Section {
                if !section.bells.isEmpty {
                    bellGridView(bells: section.bells, layoutMetrics: layoutMetrics)
                }

                VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
                    ForEach(section.storageGroups) { storageGroup in
                        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
                            Text(storageGroup.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, CatalogMetrics.Spacing.xs)

                            bellGridView(bells: storageGroup.bells, layoutMetrics: layoutMetrics)
                        }
                    }
                }
            } header: {
                CatalogSectionHeader(
                    title: section.title,
                    showsJumpIndicator: usesJumpPopover,
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

    private func updateSourceBells(_ bells: [BellCatalogItem]) {
        viewModel.updateSource(bells: bells)
        cardManagement.pruneSelection(to: visibleBells)
    }

    private var visibleBells: [BellCatalogItem] {
        switch displayModel.layout {
        case .empty:
            return []
        case .flat(let bells):
            return bells
        case .grouped(let sections):
            return sections.flatMap(\.allBells)
        }
    }

    private func bellGridView(
        bells: [BellCatalogItem],
        layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics
    ) -> some View {
        BellGridView(
            bells: bells,
            layoutMode: layoutMode,
            layoutMetrics: layoutMetrics,
            cardManagement: $cardManagement,
            canManage: canEditCollection,
            onOpen: { bell in
                onBellSelected?(bell.id)
            },
            visibleItems: visibleBells,
            deleteTitle: String(localized: "bell.context.delete.title"),
            deleteMessage: String(localized: "bell.context.delete.message"),
            onDelete: deleteBells
        )
    }

    private func moveBells(_ bells: [BellCatalogItem], to locationID: UUID?) {
        guard canEditCollection else { return }

        let location = storageContext.location(for: locationID)
        for bell in bells {
            guard let record = catalogSnapshot?.recordsByID[bell.id] else { continue }
            repository.saveBellRecord(
                record.moving(
                    to: location,
                    storagePath: location.map(storageContext.storagePath(for:))
                )
            )
        }

        moveFeedbackToken += 1
    }

    private func deleteBells(_ bells: [BellCatalogItem]) {
        guard canEditCollection else { return }

        for bell in bells {
            repository.deleteBellRecord(bellID: bell.id)
        }

        deleteFeedbackToken += 1
    }
}

private struct BellGroupingJumpPopover: View {
    let titles: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                ForEach(titles, id: \.self) { title in
                    Button(title) {
                        onSelect(title)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, CatalogMetrics.Spacing.sm)
                    .padding(.horizontal, CatalogMetrics.Spacing.md)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: CatalogShapes.thumbnail)
                }
            }
            .padding(CatalogMetrics.Spacing.md)
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320, minHeight: 160, idealHeight: 280, maxHeight: 360)
    }
}

#if DEBUG
#Preview {
    let container = PreviewContainer.makeBellsMinimal()
    let repository = CoreDataCatalogRepository(
        context: container.viewContext,
        persistentContainer: nil
    )
    let snapshot = CatalogSnapshot.load(from: container.viewContext)
    let collection = snapshot.collections.first { $0.kind == .bells }!
    let itemCount = snapshot.bellRecords.filter { $0.item.collectionID == collection.id }.count
    let summary = CollectionSummary(
        id: collection.id,
        homeID: collection.homeID,
        kind: collection.kind,
        name: collection.title,
        subtitle: collection.notes,
        backgroundStyle: collection.backgroundStyle,
        itemCount: itemCount,
        status: .active,
        sharingSummary: "Invitation-only. Members join with Apple ID and receive a role inside the collection."
    )

    NavigationStack {
        BellCatalogView(
            collection: summary,
            repository: repository,
            catalogSnapshot: snapshot,
            layoutMode: .constant(.mini),
            orderMode: .constant(.newestFirst),
            filters: .constant(BellFilters()),
            cardManagement: .constant(CatalogCardManagementState()),
            sharingState: CollectionSharingState(
                currentUserRole: .owner,
                participants: []
            ),
            canEditCollection: true
        )
        .previewEnvironment(container)
    }
}
#endif