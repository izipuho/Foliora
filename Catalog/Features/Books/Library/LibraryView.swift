import SwiftUI
import PhotosUI
import CoreData
import UIKit

private extension BookPresenceFilter {
    var title: String {
        switch self {
        case .missingCover:
            return String(localized: "library.health.missing_cover")
        case .missingAuthor:
            return String(localized: "library.health.missing_author")
        case .missingPublicationYear:
            return String(localized: "library.health.missing_publication_year")
        case .incompleteSeries:
            return String(localized: "library.health.incomplete_series")
        case .unknownSeriesSize:
            return String(localized: "library.health.series_size_unknown")
        }
    }
}

private extension BookFilters {
    var title: String? {
        presence.first?.title
    }
}

/// Displays and manages a single book library.
struct LibraryView: View {
    let collection: CollectionSummary
    let catalogSnapshot: CatalogSnapshot?
    let repository: any CatalogRepository
    let coreDataContainer: NSPersistentCloudKitContainer
    let layoutMode: Binding<CatalogCardLayoutMode>
    let onBookSelected: ((UUID) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("bookLibrary.orderMode") private var selectedOrderRawValue = LibraryOrderMode.title.rawValue
    @State private var filters = BookFilters()
    @State private var isPresentingEditLibrary = false
    @State private var isPresentingAddBookOptions = false
    @State private var isPresentingPhotoPicker = false
    @State private var isPresentingCamera = false
    @State private var shouldPresentEditorAfterCamera = false
    @State private var isPresentingAddBook = false
    @State private var isPresentingBatchAdd = false
    @State private var isPresentingPhotoCreationChoice = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var draftMediaAssets: [MediaAsset] = []
    @State private var collectionSharingState: CollectionSharingState?
    @State private var collectionSharingLoadError: Error?
    @State private var isFavoritesCollapsed = false
    @State private var collapsedGroupIDs: Set<String> = []
    @State private var favoriteChangeRevision = 0
    @State private var selection = CatalogCardSelectionState()
    @State private var bookPendingMove: BookRecord?
    @State private var bookPendingDeletion: BookRecord?
    @State private var isPresentingDeleteConfirmation = false
    @State private var isPresentingHomeEditor = false
    @State private var draftHome = Home(id: UUID(), name: "", iconName: "house.fill", notes: "")
    @State private var draftHomeLocations: [Location] = []
    @State private var bookPendingMoveAfterHomeEditor: BookRecord?
    @StateObject private var viewModel: LibraryViewModel

    private let imageMediaBuilder = ImageMediaBuilder(store: .shared)

    init(
        collection: CollectionSummary,
        catalogSnapshot: CatalogSnapshot?,
        repository: any CatalogRepository,
        coreDataContainer: NSPersistentCloudKitContainer,
        layoutMode: Binding<CatalogCardLayoutMode>,
        onBookSelected: ((UUID) -> Void)? = nil
    ) {
        self.collection = collection
        self.catalogSnapshot = catalogSnapshot
        self.repository = repository
        self.coreDataContainer = coreDataContainer
        self.layoutMode = layoutMode
        self.onBookSelected = onBookSelected
        _viewModel = StateObject(
            wrappedValue: LibraryViewModel(orderMode: .title)
        )
    }

    private var sourceBooks: [BookRecord] {
        catalogSnapshot?.bookRecords.filter { $0.collectionID == collection.id } ?? []
    }

    private var series: [BookSeries] {
        catalogSnapshot?.bookSeries.filter { $0.collectionID == collection.id } ?? []
    }

    private var displayModel: LibraryDisplayModel {
        viewModel.displayModel
    }

    private var favoriteBooks: [BookRecord] {
        displayModel.favoriteBooks
    }

    private var hasActiveFilter: Bool {
        !filters.isEmpty
    }

    private var selectedOrder: LibraryOrderMode {
        get {
            LibraryOrderMode(rawValue: selectedOrderRawValue) ?? .title
        }
        nonmutating set {
            selectedOrderRawValue = newValue.rawValue
        }
    }

    private var selectedOrderBinding: Binding<LibraryOrderMode> {
        Binding(
            get: { selectedOrder },
            set: { selectedOrder = $0 }
        )
    }

    private var homes: [Home] {
        catalogSnapshot?.homes ?? []
    }

    private var availableLocations: [Location] {
        guard let snapshot = catalogSnapshot else { return [] }

        let collectionLocations = snapshot.collectionLocationsByCollectionID[collection.id] ?? []
        if !collectionLocations.isEmpty {
            return collectionLocations
        }

        return snapshot.locationsByHomeID[collection.homeID] ?? []
    }

    private var locationsByID: [UUID: Location] {
        Dictionary(uniqueKeysWithValues: availableLocations.map { ($0.id, $0) })
    }

    private var locationPathByID: [UUID: String] {
        guard let snapshot = catalogSnapshot else { return [:] }

        if let collectionLocationPathByID = snapshot.collectionLocationPathByCollectionID[collection.id],
           !(snapshot.collectionLocationsByCollectionID[collection.id] ?? []).isEmpty {
            return collectionLocationPathByID
        }

        let availableLocationIDs = Set(availableLocations.map(\.id))
        return snapshot.locationPathByID.filter { id, _ in
            availableLocationIDs.contains(id)
        }
    }

    private var hasPlacedItems: Bool {
        catalogSnapshot?.bookRecords.contains {
            $0.collectionID == collection.id && $0.item.locationID != nil
        } ?? false
    }

    private var canEditLibrary: Bool {
        guard collectionSharingLoadError == nil else { return false }

        switch collectionSharingState?.currentUserRole {
        case .owner, .contributor:
            return true
        case .viewer, nil:
            return false
        }
    }

    private var canManageLibrarySharing: Bool {
        guard collectionSharingLoadError == nil else { return false }
        return collectionSharingState?.currentUserRole == .owner
    }

    private var sharingDestination: AnyView? {
        guard canManageLibrarySharing else { return nil }

        return AnyView(
            LibrarySharingStateLoaderView(
                collection: collection,
                sharingService: CloudKitCollectionSharingService(persistentContainer: coreDataContainer)
            )
        )
    }

    var body: some View {
        let _ = favoriteChangeRevision

        content
            .navigationTitle(collection.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                libraryToolbar
            }
            .onAppear {
                viewModel.updateContext(orderMode: selectedOrder)
                viewModel.updateContext(filters: filters)
                updateLibrarySource()
            }
            .onChange(of: sourceBooks) { _, _ in
                updateLibrarySource()
            }
            .onChange(of: series) { _, _ in
                updateLibrarySource()
            }
            .onChange(of: selectedOrderRawValue) { _, _ in
                viewModel.updateContext(orderMode: selectedOrder)
                pruneSelectionToVisibleBooks()
            }
            .onChange(of: filters) { _, newValue in
                viewModel.updateContext(filters: newValue)
                pruneSelectionToVisibleBooks()
            }
            .onReceive(NotificationCenter.default.publisher(for: .catalogItemFavoriteDidChange)) { notification in
                guard
                    let change = notification.object as? CatalogItemFavoriteChange,
                    change.collectionID == collection.id
                else {
                    return
                }

                favoriteChangeRevision &+= 1
                updateLibrarySource()
            }
            .photosPicker(
                isPresented: $isPresentingPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: nil,
                matching: .images,
                photoLibrary: .shared()
            )
            .catalogMultiPhotoCreationDialog(
                isPresented: $isPresentingPhotoCreationChoice,
                photoCount: draftMediaAssets.count,
                onSelect: handlePhotoCreationMode,
                onCancel: clearDraftBook
            )
            .fullScreenCover(isPresented: $isPresentingCamera) {
                CameraPicker { image in
                    Task {
                        await addCapturedPhotoAndPresentEditor(image)
                    }
                }
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                Task {
                    await addDraftPhotosAndPresentEditor(from: newItems)
                }
            }
            .onChange(of: isPresentingCamera) { _, isPresented in
                if !isPresented, shouldPresentEditorAfterCamera, !draftMediaAssets.isEmpty {
                    shouldPresentEditorAfterCamera = false
                    isPresentingAddBook = true
                }
            }
            .sheet(isPresented: $isPresentingAddBook, onDismiss: clearDraftBook) {
                BookEditorView(
                    collection: collection,
                    initialMediaAssets: draftMediaAssets
                ) { book in
                    (repository as! any BookCatalogRepository).saveBookRecord(book)
                }
            }
            .sheet(isPresented: $isPresentingBatchAdd, onDismiss: clearDraftBook) {
                BookBatchAddView(
                    collection: collection,
                    initialMediaAssets: draftMediaAssets,
                    repository: repository,
                    onComplete: {
                        isPresentingBatchAdd = false
                    }
                )
            }
            .sheet(isPresented: $isPresentingEditLibrary) {
                editLibrarySheet
            }
            .sheet(item: $bookPendingMove) { book in
                CatalogQuickMoveSheet(
                    currentLocationID: book.item.locationID,
                    title: String(localized: "bell.context.move"),
                    locations: availableLocations,
                    locationPathByID: locationPathByID,
                    onManageLocations: {
                        presentHomeEditor(for: collection.homeID, thenMove: book)
                    }
                ) { locationID in
                    let books = selection.isEnabled ? selectedBooks : [book]
                    moveBooks(books, to: locationID)
                    if selection.isEnabled {
                        cancelSelectionMode()
                    }
                }
            }
            .sheet(isPresented: $isPresentingHomeEditor) {
                HomeEditorView(
                    home: $draftHome,
                    locations: $draftHomeLocations,
                    onSave: {
                        repository.saveHome(draftHome)
                        repository.saveLocations(draftHomeLocations, in: draftHome.id)
                        continueQuickMoveIfNeeded()
                    },
                    onDelete: nil
                )
            }
            .confirmationDialog(
                String(localized: "book.delete.title"),
                isPresented: $isPresentingDeleteConfirmation,
                titleVisibility: .visible,
                presenting: bookPendingDeletion
            ) { book in
                Button(String(localized: "common.delete"), role: .destructive) {
                    let books = selection.isEnabled ? selectedBooks : [book]
                    deleteBooks(books)
                    if selection.isEnabled {
                        cancelSelectionMode()
                    }
                    bookPendingDeletion = nil
                }

                Button(String(localized: "common.cancel"), role: .cancel) {
                    bookPendingDeletion = nil
                }
            } message: { _ in
                Text(String(localized: "book.delete.message"))
            }
            .toolbar(selection.isEnabled ? .hidden : .visible, for: .tabBar)
            .preference(key: CatalogSelectionModePreferenceKey.self, value: selection.isEnabled)
            .task(id: collection.id) {
                await loadCollectionSharingState()
            }
    }

    @ViewBuilder
    private var content: some View {
        if canEditLibrary && collection.itemCount == 0 {
            CatalogEmptyStateView(
                systemImage: "books.vertical",
                title: "library.empty.books.title",
                message: "library.empty.books.message",
                primaryActionTitle: "book.action.add",
                primaryActionSystemImage: "plus.circle.fill",
                primaryTint: collection.backgroundStyle.accentColor,
                primaryAction: { isPresentingAddBookOptions = true }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(libraryBackground)
        } else {
            libraryContent
        }
    }

    private var libraryContent: some View {
        ScrollViewReader { scrollProxy in
            CatalogCardGrid(
                layoutMode: layoutMode.wrappedValue,
                usesGridLayout: false
            ) { cardSize, gridMetrics, cardMetrics in
                LazyVStack(
                    alignment: .leading,
                    spacing: CatalogMetrics.Spacing.lg,
                    pinnedViews: displayModel.layout.isGrouped ? [.sectionHeaders] : []
                ) {
                    if !selection.isEnabled {
                        LibraryDashboardView(
                            stats: displayModel.stats,
                            accentColor: collection.backgroundStyle.accentColor,
                            collection: collection,
                            catalogSnapshot: catalogSnapshot,
                            repository: repository,
                            canEditCollection: canEditLibrary,
                            onBookSelected: onBookSelected,
                            sharingState: collectionSharingState,
                            sharingService: CloudKitCollectionSharingService(persistentContainer: coreDataContainer),
                            onSharingChanged: {
                                Task {
                                    await loadCollectionSharingState()
                                }
                            },
                            onFilterApply: { filter in
                                filters = BookFilters(presence: [filter])
                            }
                        )
                    }

                    if hasActiveFilter {
                        activeFilterSection
                    }

                    if !selection.isEnabled && !favoriteBooks.isEmpty {
                        CatalogCollapsibleCardSection(
                            title: String(localized: "bell.catalog.favorites"),
                            layoutMode: layoutMode.wrappedValue,
                            screenWidth: stripScreenWidth(cardSize: cardSize, gridMetrics: gridMetrics),
                            isCollapsed: $isFavoritesCollapsed
                        ) { favoriteCardSize, favoriteCardMetrics in
                            ForEach(favoriteBooks) { book in
                                bookCard(
                                    book,
                                    cardSize: favoriteCardSize,
                                    cardMetrics: favoriteCardMetrics,
                                    allowsManagementActions: false
                                )
                            }
                        }

                        if !displayModel.layout.isGrouped {
                            CatalogSectionHeader(title: String(localized: "library.title"))
                        }
                    }

                    switch displayModel.layout {
                    case .empty:
                        EmptyView()
                    case .flat(let books):
                        CatalogCardGrid(
                            layoutMode: layoutMode.wrappedValue,
                            layoutMetrics: (cardSize, gridMetrics, cardMetrics)
                        ) { cardSize, _, cardMetrics in
                            ForEach(books) { book in
                                bookCard(
                                    book,
                                    cardSize: cardSize,
                                    cardMetrics: cardMetrics
                                )
                            }
                        }
                    case .grouped(let sections):
                        groupedLibrarySections(
                            sections,
                            layoutMetrics: (cardSize, gridMetrics, cardMetrics)
                        )
                    }
                }
            }
            .background(libraryBackground)
            .overlay(alignment: .trailing) {
                if !selection.isEnabled,
                   (selectedOrder == .author || selectedOrder == .title),
                   case .grouped(let sections) = displayModel.layout {
                    LibraryAlphabetIndex(sections: sections) { sectionID in
                        withAnimation(.snappy(duration: 0.2)) {
                            scrollProxy.scrollTo(sectionID, anchor: .top)
                        }
                    }
                    .padding(.trailing, CatalogMetrics.Spacing.xs)
                }
            }
        }
    }

    private var activeFilterSection: some View {
        HStack(spacing: CatalogMetrics.Spacing.sm) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(collection.backgroundStyle.accentColor)

            Text(filters.title ?? "")
                .font(CatalogTypography.cardSubtitle)

            Spacer()

            Button(String(localized: "common.clear")) {
                filters = BookFilters()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(collection.backgroundStyle.accentColor)
        }
        .padding(CatalogMetrics.Spacing.md)
        .background(.ultraThinMaterial, in: CatalogShapes.medium)
    }

    @ViewBuilder
    private func groupedLibrarySections(
        _ sections: [LibraryGroupedSection],
        layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics
    ) -> some View {
        ForEach(sections) { section in
            let isSectionCollapsible = selectedOrder == .series
            let isSectionCollapsed = isSectionCollapsible && collapsedGroupIDs.contains(section.id)

            Section {
                if !isSectionCollapsed {
                    if !section.books.isEmpty {
                        CatalogCardGrid(
                            layoutMode: layoutMode.wrappedValue,
                            layoutMetrics: layoutMetrics
                        ) { cardSize, _, cardMetrics in
                            ForEach(section.books) { book in
                                bookCard(
                                    book,
                                    cardSize: cardSize,
                                    cardMetrics: cardMetrics
                                )
                            }
                        }
                    }

                    ForEach(section.subgroups) { subgroup in
                        let isSubgroupCollapsed = selectedOrder == .author
                            && collapsedGroupIDs.contains(subgroup.id)

                        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
                            LibraryBookSubgroupHeader(
                                title: subgroup.title,
                                isCollapsed: isSubgroupCollapsed,
                                onToggle: selectedOrder == .author
                                    ? { toggleCollapsedGroup(subgroup.id) }
                                    : nil
                            )

                            if !isSubgroupCollapsed {
                                CatalogCardGrid(
                                    layoutMode: layoutMode.wrappedValue,
                                    layoutMetrics: layoutMetrics
                                ) { cardSize, _, cardMetrics in
                                    ForEach(subgroup.books) { book in
                                        bookCard(
                                            book,
                                            cardSize: cardSize,
                                            cardMetrics: cardMetrics
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            } header: {
                LibraryGroupedSectionHeader(
                    title: section.title,
                    detailText: section.detailText,
                    isCollapsed: isSectionCollapsible ? isSectionCollapsed : nil,
                    onToggle: isSectionCollapsible
                        ? { toggleCollapsedGroup(section.id) }
                        : nil
                )
                .id(section.id)
            }
        }
    }

    private func toggleCollapsedGroup(_ id: String) {
        withAnimation(.snappy(duration: 0.2)) {
            var updated = collapsedGroupIDs
            if updated.contains(id) {
                updated.remove(id)
            } else {
                updated.insert(id)
            }
            collapsedGroupIDs = updated
        }
    }

    private func bookCard(
        _ book: BookRecord,
        cardSize: CGSize,
        cardMetrics: CatalogCardLayoutMode.CardMetrics,
        allowsManagementActions: Bool = true
    ) -> some View {
        let onSelect: (() -> Void)? = canEditLibrary && allowsManagementActions
            ? { enterSelectionMode(with: book.id) }
            : nil
        let contextMenu: (() -> AnyView)? = canEditLibrary && allowsManagementActions
            ? { AnyView(bookCardContextMenu(for: book)) }
            : nil

        return CatalogInteractiveCard(
            cardSize: cardSize,
            isSelected: selection.selectedIDs.contains(book.id),
            isSelectionModeEnabled: selection.isEnabled,
            onTap: {
                handleBookCardTap(book)
            },
            onSelect: onSelect,
            selectTitle: String(localized: "bell.context.select"),
            contextMenu: contextMenu
        ) {
            BookCardView(
                book: book,
                style: CatalogCardContentStyle.style(for: layoutMode.wrappedValue),
                cardSize: cardSize,
                cardMetrics: cardMetrics
            )
        }
    }

    private func handleBookCardTap(_ book: BookRecord) {
        if selection.isEnabled {
            toggleBookSelection(book.id)
        } else {
            onBookSelected?(book.id)
        }
    }

    private func bookCardContextMenu(for book: BookRecord) -> some View {
        CatalogCardManagementMenu(
            moveTitle: String(localized: "bell.context.move"),
            onMove: {
                bookPendingMove = book
            },
            onDelete: {
                bookPendingDeletion = book
                isPresentingDeleteConfirmation = true
            }
        )
    }

    private var visibleBooks: [BookRecord] {
        let candidates: [BookRecord]

        switch displayModel.layout {
        case .empty:
            candidates = []
        case .flat(let books):
            candidates = books
        case .grouped(let sections):
            candidates = sections.flatMap { section in
                section.books + section.subgroups.flatMap(\.books)
            }
        }

        var seen: Set<UUID> = []
        return candidates.filter { seen.insert($0.id).inserted }
    }

    private var visibleBookIDs: Set<UUID> {
        Set(visibleBooks.map(\.id))
    }

    private var selectedVisibleBookIDs: Set<UUID> {
        selection.selectedVisibleIDs(in: visibleBookIDs)
    }

    private var selectedBooks: [BookRecord] {
        let selectedVisibleBookIDs = selectedVisibleBookIDs
        return visibleBooks.filter { selectedVisibleBookIDs.contains($0.id) }
    }

    private func enterSelectionMode(with bookID: UUID) {
        withAnimation(.snappy(duration: 0.2)) {
            selection.enter(with: bookID)
        }
    }

    private func toggleBookSelection(_ bookID: UUID) {
        withAnimation(.snappy(duration: 0.2)) {
            selection.toggle(bookID)
        }
    }

    private func pruneSelectionToVisibleBooks() {
        selection.prune(to: visibleBookIDs)
    }

    private func cancelSelectionMode() {
        withAnimation(.snappy(duration: 0.2)) {
            selection.cancel()
        }
    }

    private func presentHomeEditor(for homeID: UUID, thenMove book: BookRecord) {
        guard let snapshot = catalogSnapshot,
              let home = snapshot.homes.first(where: { $0.id == homeID }) else { return }

        draftHome = home
        draftHomeLocations = snapshot.locationsByHomeID[homeID] ?? []
        bookPendingMoveAfterHomeEditor = book
        isPresentingHomeEditor = true
    }

    private func continueQuickMoveIfNeeded() {
        guard let book = bookPendingMoveAfterHomeEditor else { return }
        bookPendingMoveAfterHomeEditor = nil
        isPresentingHomeEditor = false

        DispatchQueue.main.async {
            bookPendingMove = book
        }
    }

    private func moveBooks(_ books: [BookRecord], to locationID: UUID?) {
        guard canEditLibrary else { return }

        let location = locationID.flatMap { locationsByID[$0] }
        let storagePath = location.map(storagePath(for:))

        for book in books {
            var updatedItem = book.item
            updatedItem.setStorageLocation(location, path: storagePath)
            (repository as! any BookCatalogRepository).saveBookRecord(
                BookRecord(item: updatedItem, details: book.details)
            )
        }
    }

    private func deleteBooks(_ books: [BookRecord]) {
        guard canEditLibrary else { return }

        for book in books {
            (repository as! any BookCatalogRepository).deleteBookRecord(bookID: book.id)
        }
    }

    private func storagePath(for location: Location) -> StoragePath {
        var components = [
            StoragePath.Component(
                kind: location.kind,
                name: location.name
            )
        ]
        var currentParentID = location.parentLocationID

        while let parentID = currentParentID, let parent = locationsByID[parentID] {
            components.insert(
                StoragePath.Component(
                    kind: parent.kind,
                    name: parent.name
                ),
                at: 0
            )
            currentParentID = parent.parentLocationID
        }

        return StoragePath(components: components)
    }

    private func stripScreenWidth(
        cardSize: CGSize,
        gridMetrics: CatalogCardLayoutMode.GridMetrics
    ) -> CGFloat {
        let totalSpacing = gridMetrics.spacing * CGFloat(max(gridMetrics.columnCount - 1, 0))
        return cardSize.width * CGFloat(gridMetrics.columnCount)
            + totalSpacing
            + CatalogCardLayoutMode.screenHorizontalPadding * 2
    }

    private var libraryBackground: some View {
        CatalogBackgrounds.collection(
            collection.backgroundStyle.accentColor,
            scheme: colorScheme
        )
        .ignoresSafeArea()
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        if selection.isEnabled {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    cancelSelectionMode()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(String(localized: "common.cancel"))
            }

            ToolbarItem(placement: .principal) {
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "common.selected_format"),
                        CollectionKind.bookCountLabel(for: selectedVisibleBookIDs.count)
                    )
                )
                .lineLimit(1)
                .contentTransition(.numericText())
            }

            if canEditLibrary && !selectedVisibleBookIDs.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        bookPendingMove = selectedBooks.first
                    } label: {
                        Image(systemName: "folder")
                    }
                    .tint(collection.backgroundStyle.accentColor)
                }

                ToolbarSpacer(.flexible, placement: .bottomBar)

                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        bookPendingDeletion = selectedBooks.first
                        isPresentingDeleteConfirmation = bookPendingDeletion != nil
                    } label: {
                        Image(systemName: "trash")
                    }
                    .tint(CatalogSemanticColors.destructive)
                }
            }
        } else {
            CatalogCollectionToolbar(
                selectedSort: selectedOrderBinding,
                selectedLayoutMode: layoutMode,
                isPresentingAddOptions: $isPresentingAddBookOptions,
                sortOptions: LibraryOrderMode.allCases,
                sortSectionTitle: String(localized: "common.sort"),
                sortTitle: { $0.title },
                canEdit: canEditLibrary,
                onEdit: {
                    isPresentingEditLibrary = true
                },
                onPhotoLibrary: {
                    guard canEditLibrary else { return }
                    isPresentingPhotoPicker = true
                },
                onCamera: {
                    guard canEditLibrary else { return }
                    isPresentingCamera = true
                }
            )
        }
    }

    private var editLibrarySheet: some View {
        CollectionEditorView(
            homes: homes,
            screenTitle: String(localized: "library.action.edit"),
            initialTitle: collection.name,
            initialNotes: collection.subtitle,
            initialHomeID: collection.homeID,
            initialBackgroundStyle: collection.backgroundStyle,
            hasPlacedItems: hasPlacedItems,
            allowsDeletion: true,
            sharingDestination: sharingDestination
        ) { title, notes, homeID, backgroundStyle in
            saveLibraryEdits(
                title: title,
                notes: notes,
                homeID: homeID,
                backgroundStyle: backgroundStyle
            )
        } onDelete: {
            repository.deleteCollection(collectionID: collection.id)
            dismiss()
        }
    }

    private func updateLibrarySource() {
        viewModel.updateSource(
            books: sourceBooks,
            series: series
        )
        pruneSelectionToVisibleBooks()
    }

    private func clearDraftBook() {
        draftMediaAssets = []
    }

    private func handlePhotoCreationMode(_ mode: CatalogMultiPhotoCreationMode) {
        switch mode {
        case .singleItem:
            isPresentingAddBook = true
        case .batch:
            isPresentingBatchAdd = true
        }
    }

    @MainActor
    private func addDraftPhotosAndPresentEditor(from items: [PhotosPickerItem]) async {
        guard canEditLibrary, !items.isEmpty else { return }

        var newAssets: [MediaAsset] = []

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }

            let contentType = item.supportedContentTypes.first
            guard let media = try? imageMediaBuilder.build(
                from: data,
                image: image,
                preferredFileExtension: contentType?.preferredFilenameExtension,
                mimeType: contentType?.preferredMIMEType
            ) else { continue }

            newAssets.append(media.asset.with(sortOrder: newAssets.count))
        }

        selectedPhotoItems = []

        guard !newAssets.isEmpty else { return }
        draftMediaAssets = newAssets

        if newAssets.count == 1 {
            isPresentingAddBook = true
        } else {
            isPresentingPhotoCreationChoice = true
        }
    }

    @MainActor
    private func addCapturedPhotoAndPresentEditor(_ image: UIImage) async {
        guard canEditLibrary,
              let media = try? imageMediaBuilder.build(from: image) else { return }

        draftMediaAssets = [media.asset.with(sortOrder: 0)]
        shouldPresentEditorAfterCamera = true
    }

    private func saveLibraryEdits(
        title: String,
        notes: String,
        homeID: UUID,
        backgroundStyle: CollectionBackgroundStyle
    ) {
        guard canEditLibrary else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        repository.saveCollection(
            Collection(
                id: collection.id,
                homeID: homeID,
                kind: collection.kind,
                title: trimmedTitle.isEmpty ? collection.name : trimmedTitle,
                notes: trimmedNotes,
                backgroundStyle: backgroundStyle
            )
        )
    }

    @MainActor
    private func loadCollectionSharingState() async {
        collectionSharingState = nil
        collectionSharingLoadError = nil

        do {
            collectionSharingState = try await CloudKitCollectionSharingService(
                persistentContainer: coreDataContainer
            ).sharingState(for: collection.id)
        } catch {
            collectionSharingLoadError = error
        }
    }
}

private struct LibraryGroupedSectionHeader: View {
    let title: String
    let detailText: String?
    let isCollapsed: Bool?
    let onToggle: (() -> Void)?

    var body: some View {
        Group {
            if let isCollapsed, let onToggle {
                Button(action: onToggle) {
                    headerContent(isCollapsed: isCollapsed)
                }
                .buttonStyle(.plain)
            } else {
                headerContent(isCollapsed: nil)
            }
        }
        .padding(.vertical, CatalogMetrics.Spacing.sm)
        .padding(.horizontal, CatalogMetrics.Spacing.md)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 0.5)
        }
    }

    private func headerContent(isCollapsed: Bool?) -> some View {
        HStack(spacing: CatalogMetrics.Spacing.sm) {
            Text(title)
                .font(CatalogTypography.sectionTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let isCollapsed {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(CatalogTypography.chipLabel)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let detailText {
                Text(detailText)
                    .font(CatalogTypography.chipLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct LibraryBookSubgroupHeader: View {
    let title: String
    let isCollapsed: Bool
    let onToggle: (() -> Void)?

    var body: some View {
        Group {
            if let onToggle {
                Button(action: onToggle) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: CatalogMetrics.Spacing.xs) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if onToggle != nil {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, CatalogMetrics.Spacing.xs)
        .contentShape(Rectangle())
    }
}

private struct LibraryAlphabetIndex: View {
    let sections: [LibraryGroupedSection]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 1) {
            ForEach(indexedSections) { section in
                Button(section.indexTitle ?? "") {
                    onSelect(section.id)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .frame(minWidth: 20, minHeight: 14)
            }
        }
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
    }

    private var indexedSections: [LibraryGroupedSection] {
        sections.filter { $0.indexTitle != nil }
    }
}

private struct LibrarySharingStateLoaderView: View {
    let collection: CollectionSummary
    private let sharingService: any CollectionSharingService

    @State private var state = CollectionSharingState(
        currentUserRole: .owner,
        participants: []
    )
    @State private var isLoading = true
    @State private var didFail = false

    init(
        collection: CollectionSummary,
        sharingService: any CollectionSharingService
    ) {
        self.collection = collection
        self.sharingService = sharingService
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView(String(localized: "collection.sharing.loading"))
            } else if didFail {
                CatalogEmptyStateView(
                    systemImage: "icloud.slash",
                    title: LocalizedStringKey(String(localized: "collection.sharing.load_failed.title")),
                    message: LocalizedStringKey(String(localized: "collection.sharing.load_failed.message")),
                    primaryActionTitle: LocalizedStringKey(String(localized: "common.retry")),
                    primaryAction: {
                        Task {
                            await loadSharingState()
                        }
                    }
                )
            } else {
                CollectionSharingView(
                    collection: collection,
                    state: state,
                    sharingService: sharingService
                ) {
                    Task {
                        await loadSharingState()
                    }
                }
            }
        }
        .task(id: collection.id) {
            await loadSharingState()
        }
    }

    @MainActor
    private func loadSharingState() async {
        isLoading = true
        didFail = false

        do {
            state = try await sharingService.sharingState(for: collection.id)
        } catch {
            didFail = true
        }

        isLoading = false
    }
}

#if DEBUG
#Preview {
    let container = PreviewContainer.makeBooksMinimal()
    let repository = CoreDataCatalogRepository(
        context: container.viewContext,
        persistentContainer: nil
    )
    let snapshot = CatalogSnapshot.load(from: container.viewContext)

    if let collection = snapshot.collections
        .compactMap({ snapshot.collectionSummary(id: $0.id) })
        .first(where: { $0.kind == .books }) {
        NavigationStack {
            LibraryView(
                collection: collection,
                catalogSnapshot: snapshot,
                repository: repository,
                coreDataContainer: container,
                layoutMode: .constant(.compact)
            )
        }
    }
}
#endif