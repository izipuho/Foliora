import SwiftUI

#if DEBUG
import CoreData
#endif

/// Displays the catalog details for a single book.
struct BookDetailView: View {
    let book: BookRecord

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
}

/// Resolves a book by identifier and keeps the presented detail synchronized with the catalog snapshot.
struct BookDetailContainer: View {
    let bookID: UUID
    let repository: any CatalogRepository
    let catalogSnapshot: CatalogSnapshot?
    let onClose: (() -> Void)?

    @State private var book: BookRecord?

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
            if let book {
                BookDetailView(book: book)
            } else {
                CatalogEmptyStateView(
                    systemImage: "book.closed",
                    title: "Book not found",
                    message: "This book is no longer available."
                )
            }
        }
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .task(id: bookID) {
            syncBookFromCatalogSnapshot()
        }
        .onChange(of: catalogSnapshot?.recordsByID[bookID]) { _, _ in
            syncBookFromCatalogSnapshot()
        }
    }

    private func syncBookFromCatalogSnapshot() {
        book = catalogSnapshot?.recordsByID[bookID]
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
