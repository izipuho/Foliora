import SwiftUI
import PhotosUI
import CoreData
import UIKit

private extension BookPresenceFilter {
    var title: String {
        switch self {
        case .missingCover:
            return "Missing Cover"
        case .missingAuthor:
            return "Missing Author"
        case .missingPublicationYear:
            return "Missing Publication Year"
        case .incompleteSeries:
            return "Incomplete Series"
        case .unknownSeriesSize:
            return "Series Size Unknown"
        }
    }
}

private extension BookFilters {
    var activeSelectionCount: Int {
        tokens.count
            + publicationYears.count
            + acquiredYears.count
            + conditions.count
            + acquisitionMethods.count
            + presence.count
    }

    var title: String? {
        guard activeSelectionCount > 0 else { return nil }

        if activeSelectionCount == 1, let presenceFilter = presence.first {
            return presenceFilter.title
        }

        return "\(activeSelectionCount) \(activeSelectionCount == 1 ? "filter" : "filters")"
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
    @State private var isPresentingFilters = false
    @State private var isPresentingEditLibrary = false
    @State private var isPresentingAddBookOptions = false
    @State private var isPresentingPhotoPicker = false
    @State private var isPresentingCamera = false
    @State private var shouldPresentEditorAfterCamera = false
    @State private var isPresentingAddBook = false
    @State private var isPresentingBatchAdd = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var draftMediaAssets: [MediaAsset] = []
    @State private var collectionSharingState: CollectionSharingState?
    @State private var collectionSharingLoadError: Error?
    @State private var isFavoritesCollapsed = false
    @State private var collapsedGroupIDs: Set<String> = []
    @State private var favoriteChangeRevision = 0
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
            }
            .onChange(of: filters) { _, newValue in
                viewModel.updateContext(filters: newValue)
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
            .sheet(isPresented: $isPresentingFilters) {
                BookLibraryFilterView(
                    books: sourceBooks,
                    filters: filters
                ) { updatedFilters in
                    filters = updatedFilters
                }
            }
            .task(id: collection.id) {
                await loadCollectionSharingState()
            }
    }

    @ViewBuilder
    private var content: some View {
        if canEditLibrary && collection.itemCount == 0 {
            CatalogEmptyStateView(
                systemImage: "books.vertical",
                title: "No Books",
                message: "This library does not contain any books yet.",
                primaryActionTitle: "Add Book",
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

                    if hasActiveFilter {
                        activeFilterSection
                    }

                    if !favoriteBooks.isEmpty {
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
                                    cardMetrics: favoriteCardMetrics
                                )
                            }
                        }

                        if !displayModel.layout.isGrouped {
                            CatalogSectionHeader(title: String(localized: "Library"))
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
                if (selectedOrder == .author || selectedOrder == .title),
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
        cardMetrics: CatalogCardLayoutMode.CardMetrics
    ) -> some View {
        Button {
            onBookSelected?(book.id)
        } label: {
            BookCardView(
                book: book,
                style: CatalogCardContentStyle.style(for: layoutMode.wrappedValue),
                cardSize: cardSize,
                cardMetrics: cardMetrics
            )
        }
        .buttonStyle(.plain)
        .frame(width: cardSize.width, height: cardSize.height)
        .contentShape(Rectangle())
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
        CatalogCollectionToolbar(
            selectedSort: selectedOrderBinding,
            selectedLayoutMode: layoutMode,
            isPresentingAddOptions: $isPresentingAddBookOptions,
            sortOptions: LibraryOrderMode.allCases,
            sortSectionTitle: "Sort",
            sortTitle: { $0.title },
            hasActiveFilters: hasActiveFilter,
            onFilters: {
                isPresentingFilters = true
            },
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

    private var editLibrarySheet: some View {
        CollectionEditorView(
            homes: homes,
            screenTitle: "Edit Library",
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
    }

    private func clearDraftBook() {
        draftMediaAssets = []
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
            isPresentingBatchAdd = true
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

private struct BookLibraryFilterView: View {
    let books: [BookRecord]
    let onApply: (BookFilters) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftFilters: BookFilters

    init(
        books: [BookRecord],
        filters: BookFilters,
        onApply: @escaping (BookFilters) -> Void
    ) {
        self.books = books
        self.onApply = onApply
        _draftFilters = State(initialValue: filters)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Catalog") {
                    tokenFilterLink(
                        title: "People",
                        systemImage: "person.text.rectangle",
                        category: .person,
                        tokens: personTokens
                    )
                    tokenFilterLink(
                        title: "Publishers",
                        systemImage: "building.2",
                        category: .publisher,
                        tokens: publisherTokens
                    )
                    tokenFilterLink(
                        title: "Series",
                        systemImage: "books.vertical",
                        category: .series,
                        tokens: seriesTokens
                    )
                    tokenFilterLink(
                        title: "Languages",
                        systemImage: "character.book.closed",
                        category: .language,
                        tokens: languageTokens
                    )
                    tokenFilterLink(
                        title: "Genres",
                        systemImage: "text.book.closed",
                        category: .genre,
                        tokens: genreTokens
                    )
                    tokenFilterLink(
                        title: "Tags",
                        systemImage: "tag",
                        category: .tag,
                        tokens: tagTokens
                    )
                }

                Section("Dates") {
                    if !publicationYears.isEmpty {
                        NavigationLink {
                            BookFilterSelectionView(
                                title: "Publication year",
                                values: publicationYears,
                                selection: $draftFilters.publicationYears,
                                label: String.init
                            )
                        } label: {
                            filterLabel(
                                title: "Publication year",
                                systemImage: "calendar",
                                count: draftFilters.publicationYears.count
                            )
                        }
                    }

                    if !acquiredYears.isEmpty {
                        NavigationLink {
                            BookFilterSelectionView(
                                title: "Acquired year",
                                values: acquiredYears,
                                selection: $draftFilters.acquiredYears,
                                label: String.init
                            )
                        } label: {
                            filterLabel(
                                title: "Acquired year",
                                systemImage: "calendar.badge.plus",
                                count: draftFilters.acquiredYears.count
                            )
                        }
                    }
                }

                Section("Collection") {
                    if !conditions.isEmpty {
                        NavigationLink {
                            BookFilterSelectionView(
                                title: "Condition",
                                values: conditions,
                                selection: $draftFilters.conditions,
                                label: { $0.displayName }
                            )
                        } label: {
                            filterLabel(
                                title: "Condition",
                                systemImage: "checkmark.seal",
                                count: draftFilters.conditions.count
                            )
                        }
                    }

                    if !acquisitionMethods.isEmpty {
                        NavigationLink {
                            BookFilterSelectionView(
                                title: "Acquisition",
                                values: acquisitionMethods,
                                selection: $draftFilters.acquisitionMethods,
                                label: { $0.displayName }
                            )
                        } label: {
                            filterLabel(
                                title: "Acquisition",
                                systemImage: "bag",
                                count: draftFilters.acquisitionMethods.count
                            )
                        }
                    }
                }

                Section("Data Quality") {
                    NavigationLink {
                        BookFilterSelectionView(
                            title: "Data Quality",
                            values: presenceFilters,
                            selection: $draftFilters.presence,
                            label: { $0.title }
                        )
                    } label: {
                        filterLabel(
                            title: "Missing or incomplete data",
                            systemImage: "checklist",
                            count: draftFilters.presence.count
                        )
                    }
                }

                if !draftFilters.isEmpty {
                    Section {
                        Button("Clear All", role: .destructive) {
                            draftFilters = BookFilters()
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.apply")) {
                        onApply(draftFilters)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func tokenFilterLink(
        title: String,
        systemImage: String,
        category: BookSearchToken.Category,
        tokens: [BookSearchToken]
    ) -> some View {
        if !tokens.isEmpty {
            NavigationLink {
                BookFilterSelectionView(
                    title: title,
                    values: tokens,
                    selection: tokenSelectionBinding(for: category),
                    label: tokenTitle
                )
            } label: {
                filterLabel(
                    title: title,
                    systemImage: systemImage,
                    count: selectedTokenCount(for: category)
                )
            }
        }
    }

    private func filterLabel(
        title: String,
        systemImage: String,
        count: Int
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)

            Spacer()

            if count > 0 {
                Text(String(count))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tokenSelectionBinding(
        for category: BookSearchToken.Category
    ) -> Binding<Set<BookSearchToken>> {
        Binding(
            get: {
                Set(draftFilters.tokens.filter { $0.category == category })
            },
            set: { selection in
                draftFilters.tokens = Set(
                    draftFilters.tokens.filter { $0.category != category }
                ).union(selection)
            }
        )
    }

    private func selectedTokenCount(for category: BookSearchToken.Category) -> Int {
        draftFilters.tokens.filter { $0.category == category }.count
    }

    private var peopleByID: [UUID: Person] {
        Dictionary(
            books
                .flatMap { $0.details.contributors.map(\.person) }
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var publishersByID: [UUID: Publisher] {
        Dictionary(
            books.compactMap(\.details.publisher).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var seriesByID: [UUID: BookSeries] {
        Dictionary(
            books.compactMap(\.details.series).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var personTokens: [BookSearchToken] {
        peopleByID.values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { .person($0.id) }
    }

    private var publisherTokens: [BookSearchToken] {
        publishersByID.values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { .publisher($0.id) }
    }

    private var seriesTokens: [BookSearchToken] {
        seriesByID.values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { .series($0.id) }
    }

    private var languageTokens: [BookSearchToken] {
        uniqueValues(books.compactMap(\.details.languageCode)).map(BookSearchToken.language)
    }

    private var genreTokens: [BookSearchToken] {
        uniqueValues(books.compactMap(\.details.genre)).map(BookSearchToken.genre)
    }

    private var tagTokens: [BookSearchToken] {
        uniqueValues(books.flatMap(\.tags)).map(BookSearchToken.tag)
    }

    private var publicationYears: [Int] {
        Array(Set(books.compactMap(\.details.publicationYear))).sorted(by: >)
    }

    private var acquiredYears: [Int] {
        Array(Set(books.compactMap(\.acquiredYear))).sorted(by: >)
    }

    private var conditions: [ItemCondition] {
        ItemCondition.allCases.filter { condition in
            books.contains { $0.condition == condition }
        }
    }

    private var acquisitionMethods: [AcquisitionMethod] {
        AcquisitionMethod.allCases.filter { method in
            books.contains { $0.acquisitionMethod == method }
        }
    }

    private var presenceFilters: [BookPresenceFilter] {
        [
            .missingCover,
            .missingAuthor,
            .missingPublicationYear,
            .incompleteSeries,
            .unknownSeriesSize
        ]
    }

    private func tokenTitle(_ token: BookSearchToken) -> String {
        switch token {
        case .library:
            return "Library"
        case .person(let personID):
            return peopleByID[personID]?.name ?? "Person"
        case .publisher(let publisherID):
            return publishersByID[publisherID]?.name ?? "Publisher"
        case .series(let seriesID):
            return seriesByID[seriesID]?.name ?? "Series"
        case .language(let languageCode):
            return Locale.current.localizedString(forLanguageCode: languageCode) ?? languageCode.uppercased()
        case .genre(let genre):
            return genre
        case .tag(let tag):
            return tag
        }
    }

    private func uniqueValues(_ values: [String]) -> [String] {
        var seen: Set<String> = []

        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert(normalized($0)).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private struct BookFilterSelectionView<Value: Hashable>: View {
    let title: String
    let values: [Value]
    @Binding var selection: Set<Value>
    let label: (Value) -> String

    var body: some View {
        List {
            ForEach(values, id: \.self) { value in
                Button {
                    if selection.contains(value) {
                        selection.remove(value)
                    } else {
                        selection.insert(value)
                    }
                } label: {
                    HStack {
                        Text(label(value))
                            .foregroundStyle(.primary)

                        Spacer()

                        if selection.contains(value) {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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