import SwiftUI
import CoreData

private enum LibraryOrderMode: String, CaseIterable {
    case title
    case author
    case publicationYearNewest

    var title: String {
        switch self {
        case .title:
            return "Title"
        case .author:
            return "Author"
        case .publicationYearNewest:
            return "Publication year"
        }
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
    @State private var selectedBookID: UUID?
    @State private var isPresentingEditLibrary = false
    @State private var collectionSharingState: CollectionSharingState?
    @State private var collectionSharingLoadError: Error?

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
    }

    private var books: [BookRecord] {
        let source = catalogSnapshot?.bookRecords.filter { $0.collectionID == collection.id } ?? []

        switch selectedOrder {
        case .title:
            return source.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .author:
            return source.sorted { lhs, rhs in
                let lhsAuthor = primaryAuthorName(for: lhs)
                let rhsAuthor = primaryAuthorName(for: rhs)

                if lhsAuthor == rhsAuthor {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }

                if lhsAuthor.isEmpty { return false }
                if rhsAuthor.isEmpty { return true }
                return lhsAuthor.localizedStandardCompare(rhsAuthor) == .orderedAscending
            }
        case .publicationYearNewest:
            return source.sorted { lhs, rhs in
                let lhsYear = lhs.details.publicationYear
                let rhsYear = rhs.details.publicationYear

                switch (lhsYear, rhsYear) {
                case let (.some(lhsYear), .some(rhsYear)) where lhsYear != rhsYear:
                    return lhsYear > rhsYear
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
        }
    }

    private var selectedOrder: LibraryOrderMode {
        get {
            LibraryOrderMode(rawValue: selectedOrderRawValue) ?? .title
        }
        nonmutating set {
            selectedOrderRawValue = newValue.rawValue
        }
    }

    private var selectedBook: BookRecord? {
        guard let selectedBookID else { return nil }
        return books.first { $0.id == selectedBookID }
    }

    private var isBookDetailPresented: Binding<Bool> {
        Binding(
            get: { selectedBookID != nil },
            set: { isPresented in
                if !isPresented {
                    selectedBookID = nil
                }
            }
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
        content
            .navigationTitle(collection.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                libraryToolbar
            }
            .sheet(isPresented: $isPresentingEditLibrary) {
                editLibrarySheet
            }
            .sheet(isPresented: isBookDetailPresented) {
                if let selectedBook {
                    NavigationStack {
                        BookDetailView(book: selectedBook)
                    }
                    .presentationDragIndicator(.visible)
                }
            }
            .task(id: collection.id) {
                await loadCollectionSharingState()
            }
    }

    @ViewBuilder
    private var content: some View {
        if books.isEmpty {
            CatalogEmptyStateView(
                systemImage: "books.vertical",
                title: "No Books",
                message: "This library does not contain any books yet."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(libraryBackground)
        } else {
            CatalogCardGrid(layoutMode: layoutMode.wrappedValue) { cardSize, _, cardMetrics in
                ForEach(books) { book in
                    Button {
                        openBook(book)
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
            }
            .background(libraryBackground)
        }
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
        if canEditLibrary {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingEditLibrary = true
                } label: {
                    floatingToolbarIcon(systemName: "square.and.pencil")
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Sort") {
                    ForEach(LibraryOrderMode.allCases, id: \.self) { option in
                        Button {
                            selectedOrder = option
                        } label: {
                            if selectedOrder == option {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                }

                Section("Layout") {
                    ControlGroup {
                        Button {
                            zoomOutLayout()
                        } label: {
                            Image(systemName: "minus")
                        }
                        .disabled(!canZoomOut)

                        Text(layoutTitle(for: layoutMode.wrappedValue))

                        Button {
                            zoomInLayout()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(!canZoomIn)
                    } label: {
                        Label("Layout", systemImage: "square.grid.2x2")
                    }
                    .menuActionDismissBehavior(.disabled)
                }
            } label: {
                floatingToolbarIcon(systemName: "line.3.horizontal.decrease")
            }
        }

        if canEditLibrary {
            ToolbarItem(placement: .topBarTrailing) {
                Button {} label: {
                    floatingToolbarIcon(systemName: "plus")
                }
                .disabled(true)
            }
        }
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

    private var orderedLayoutModes: [CatalogCardLayoutMode] {
        [.covers, .mini, .compact, .wide, .showcase]
    }

    private var canZoomOut: Bool {
        guard let currentIndex = orderedLayoutModes.firstIndex(of: layoutMode.wrappedValue) else {
            return false
        }

        return currentIndex < orderedLayoutModes.count - 1
    }

    private var canZoomIn: Bool {
        guard let currentIndex = orderedLayoutModes.firstIndex(of: layoutMode.wrappedValue) else {
            return false
        }

        return currentIndex > 0
    }

    private func zoomOutLayout() {
        guard let currentIndex = orderedLayoutModes.firstIndex(of: layoutMode.wrappedValue),
              currentIndex < orderedLayoutModes.count - 1 else {
            return
        }

        layoutMode.wrappedValue = orderedLayoutModes[currentIndex + 1]
    }

    private func zoomInLayout() {
        guard let currentIndex = orderedLayoutModes.firstIndex(of: layoutMode.wrappedValue),
              currentIndex > 0 else {
            return
        }

        layoutMode.wrappedValue = orderedLayoutModes[currentIndex - 1]
    }

    private func layoutTitle(for mode: CatalogCardLayoutMode) -> String {
        switch mode {
        case .covers: return "Covers"
        case .mini: return "Mini"
        case .compact: return "Compact"
        case .wide: return "Wide"
        case .showcase: return "Showcase"
        }
    }

    private func primaryAuthorName(for book: BookRecord) -> String {
        book.details.contributors
            .filter { $0.role == .author }
            .sorted { $0.order < $1.order }
            .first?
            .person.name ?? ""
    }

    private func openBook(_ book: BookRecord) {
        if let onBookSelected {
            onBookSelected(book.id)
        } else {
            selectedBookID = book.id
        }
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

private func floatingToolbarIcon(systemName: String) -> some View {
    Image(systemName: systemName)
        .font(.system(size: 17, weight: .semibold))
        .frame(width: 30, height: 30)
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
