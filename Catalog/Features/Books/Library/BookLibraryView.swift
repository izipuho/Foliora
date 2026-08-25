import SwiftUI

#if DEBUG
import CoreData
#endif

/// Displays the books contained in a single library collection.
struct BookLibraryView: View {
    let collection: CollectionSummary
    let catalogSnapshot: CatalogSnapshot?
    let repository: any CatalogRepository
    let layoutMode: Binding<CatalogCardLayoutMode>
    let onBookSelected: ((UUID) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedBookID: UUID?

    init(
        collection: CollectionSummary,
        catalogSnapshot: CatalogSnapshot?,
        repository: any CatalogRepository,
        layoutMode: Binding<CatalogCardLayoutMode>,
        onBookSelected: ((UUID) -> Void)? = nil
    ) {
        self.collection = collection
        self.catalogSnapshot = catalogSnapshot
        self.repository = repository
        self.layoutMode = layoutMode
        self.onBookSelected = onBookSelected
    }

    private var books: [BookRecord] {
        catalogSnapshot?.bookRecords
            .filter { $0.collectionID == collection.id }
            .sorted { lhs, rhs in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            } ?? []
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

    var body: some View {
        content
            .navigationTitle(collection.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: isBookDetailPresented) {
                if let selectedBook {
                    NavigationStack {
                        BookDetailView(book: selectedBook)
                    }
                    .presentationDragIndicator(.visible)
                }
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
            .background(
                CatalogBackgrounds.collection(
                    collection.backgroundStyle.accentColor,
                    scheme: colorScheme
                )
                .ignoresSafeArea()
            )
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
        }
    }

    private func openBook(_ book: BookRecord) {
        if let onBookSelected {
            onBookSelected(book.id)
        } else {
            selectedBookID = book.id
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

    if let collection = snapshot.collections
        .compactMap({ snapshot.collectionSummary(id: $0.id) })
        .first(where: { $0.kind == .books }) {
        NavigationStack {
            BookLibraryView(
                collection: collection,
                catalogSnapshot: snapshot,
                repository: repository,
                layoutMode: .constant(.compact)
            )
        }
    }
}
#endif
