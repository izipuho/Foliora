import SwiftUI

#if DEBUG
import CoreData
#endif

/// Displays the catalog details for a single book.
struct BookDetailView: View {
    @Binding var book: BookRecord
    let repository: any CatalogRepository
    let catalogSnapshot: CatalogSnapshot?
    let canEditCollection: Bool
    let canChangeFavorite: Bool
    let onClose: (() -> Void)?

    @State private var isPresentingEditor = false

    init(
        book: Binding<BookRecord>,
        repository: any CatalogRepository,
        catalogSnapshot: CatalogSnapshot?,
        canEditCollection: Bool,
        canChangeFavorite: Bool = false,
        onClose: (() -> Void)? = nil
    ) {
        _book = book
        self.repository = repository
        self.catalogSnapshot = catalogSnapshot
        self.canEditCollection = canEditCollection
        self.canChangeFavorite = canChangeFavorite
        self.onClose = onClose
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xl) {
                header
                metadata

                if !book.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    notes
                }
            }
            .padding(CatalogMetrics.Insets.screen)
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            CatalogItemDetailToolbar(
                onClose: onClose,
                favorite: favoriteToolbarAction,
                contentState: detailToolbarState
            )
        }
        .sheet(isPresented: $isPresentingEditor) {
            if canEditCollection, let collection = inferredCollection {
                BookEditorView(
                    collection: collection,
                    book: book
                ) { updatedBook in
                    save(updatedBook)
                }
            }
        }
    }

    private var detailToolbarState: CatalogItemDetailToolbar.ContentState {
        guard canEditCollection else { return .readOnly }

        return .viewing {
            isPresentingEditor = true
        }
    }

    private var favoriteToolbarAction: CatalogItemDetailToolbar.FavoriteAction? {
        guard canChangeFavorite else { return nil }

        return CatalogItemDetailToolbar.FavoriteAction(
            isFavorite: book.isFavorite,
            action: toggleFavorite
        )
    }

    private var inferredCollection: CollectionSummary? {
        catalogSnapshot?.collectionSummary(id: book.collectionID)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: CatalogMetrics.Spacing.xl) {
            cover

            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
                Text(book.title)
                    .font(.title2.weight(.semibold))

                if !authorNames.isEmpty {
                    Text(authorNames)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                if let publicationYear = book.details.publicationYear {
                    Text(String(publicationYear))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let coverPhoto {
            MediaPreviewImage(
                identifier: coverPhoto.localIdentifier,
                originalData: coverPhoto.originalData,
                size: CGSize(width: 128, height: 180)
            )
            .frame(width: 128, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.medium, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.medium, style: .continuous)
                .fill(.secondary.opacity(0.12))
                .frame(width: 128, height: 180)
                .overlay {
                    Image(systemName: "book.closed")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            if let publicationPlace = publicationPlaceDisplayName {
                metadataRow("Publication place", value: publicationPlace)
            }

            if let pageCount = book.details.pageCount {
                metadataRow("Pages", value: String(pageCount))
            }

            if let languageCode = book.details.languageCode, !languageCode.isEmpty {
                metadataRow("Language", value: languageCode.uppercased())
            }

            if let volumeNumber = book.details.volumeNumber {
                metadataRow("Volume", value: String(volumeNumber))
            }

            ForEach(otherContributors, id: \.self) { contributor in
                metadataRow(contributor.role.title, value: contributor.person.name)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .catalogSurfaceCard()
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
            Text("Notes")
                .font(.headline)

            Text(book.notes)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .catalogSurfaceCard()
    }

    private func metadataRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CatalogMetrics.Spacing.md) {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer(minLength: CatalogMetrics.Spacing.md)

            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private var coverPhoto: MediaAsset? {
        book.mediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first
    }

    private var authorNames: String {
        book.details.contributors
            .filter { $0.role == .author }
            .sorted { $0.order < $1.order }
            .map(\.person.name)
            .joined(separator: ", ")
    }

    private var otherContributors: [BookContributor] {
        book.details.contributors
            .filter { $0.role != .author }
            .sorted { $0.order < $1.order }
    }

    private var publicationPlaceDisplayName: String? {
        if let place = book.details.publicationPlace?.displayName, !place.isEmpty {
            return place
        }

        if let placeName = book.details.publicationPlaceName, !placeName.isEmpty {
            return placeName
        }

        return nil
    }

    private func toggleFavorite() {
        guard canChangeFavorite else { return }
        var updatedItem = book.item
        updatedItem.isFavorite.toggle()
        book = BookRecord(item: updatedItem, details: book.details)
        repository.setFavorite(updatedItem.isFavorite, for: updatedItem.id)
    }

    private func save(_ updatedBook: BookRecord) {
        book = updatedBook
        (repository as! any BookCatalogRepository).saveBookRecord(updatedBook)
    }
}

/// Resolves a book by identifier and keeps the presented detail synchronized with the catalog snapshot.
struct BookDetailContainer: View {
    let bookID: UUID
    let repository: any CatalogRepository
    let catalogSnapshot: CatalogSnapshot?
    let onClose: (() -> Void)?

    @State private var book: BookRecord?
    @State private var collectionSharingState: CollectionSharingState?
    @State private var collectionSharingLoadError: Error?

    init(
        bookID: UUID,
        repository: any CatalogRepository,
        catalogSnapshot: CatalogSnapshot?,
        onClose: (() -> Void)? = nil
    ) {
        self.bookID = bookID
        self.repository = repository
        self.catalogSnapshot = catalogSnapshot
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            if let bookBinding {
                BookDetailView(
                    book: bookBinding,
                    repository: repository,
                    catalogSnapshot: catalogSnapshot,
                    canEditCollection: canEditCollection,
                    canChangeFavorite: canChangeFavorite,
                    onClose: onClose
                )
            } else {
                CatalogEmptyStateView(
                    systemImage: "book.closed",
                    title: "Book not found",
                    message: "This book is no longer available."
                )
            }
        }
        .task(id: bookID) {
            syncBookFromCatalogSnapshot()
        }
        .task(id: currentCollectionID) {
            await loadCollectionSharingState()
        }
        .onChange(of: catalogSnapshot?.recordsByID[bookID]) { _, _ in
            syncBookFromCatalogSnapshot()
        }
    }

    private var canEditCollection: Bool {
        guard collectionSharingLoadError == nil else { return false }

        switch collectionSharingState?.currentUserRole {
        case .owner, .contributor:
            return true
        case .viewer, nil:
            return false
        }
    }

    private var canChangeFavorite: Bool {
        guard collectionSharingLoadError == nil else { return false }

        switch collectionSharingState?.currentUserRole {
        case .owner:
            return true
        case .contributor, .viewer, nil:
            return false
        }
    }

    private var bookBinding: Binding<BookRecord>? {
        guard let currentBook = book else { return nil }

        return Binding(
            get: {
                book ?? currentBook
            },
            set: {
                book = $0
            }
        )
    }

    private var currentCollectionID: UUID? {
        book?.collectionID ?? catalogSnapshot?.recordsByID[bookID]?.collectionID
    }

    private func syncBookFromCatalogSnapshot() {
        book = catalogSnapshot?.recordsByID[bookID]
    }

    @MainActor
    private func loadCollectionSharingState() async {
        collectionSharingState = nil
        collectionSharingLoadError = nil

        guard let collectionID = currentCollectionID,
              let persistentContainer = FolioraAppDelegate.coreDataContainer else {
            return
        }

        do {
            collectionSharingState = try await CloudKitCollectionSharingService(
                persistentContainer: persistentContainer
            ).sharingState(for: collectionID)
        } catch {
            collectionSharingLoadError = error
        }
    }
}

private extension BookContributorRole {
    var title: String {
        switch self {
        case .author: return "Author"
        case .translator: return "Translator"
        case .editor: return "Editor"
        case .illustrator: return "Illustrator"
        }
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

    if let book = snapshot.bookRecords.first {
        BookDetailContainer(
            bookID: book.id,
            repository: repository,
            catalogSnapshot: snapshot
        )
    }
}
#endif
