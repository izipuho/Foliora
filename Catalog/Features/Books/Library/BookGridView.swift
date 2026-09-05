import SwiftUI

/// Displays book cards using the shared catalog grid mechanics.
struct BookGridView: View {
    let books: [BookRecord]
    let layoutMode: CatalogCardLayoutMode
    let layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics?
    let bottomContentMargin: CGFloat?
    let accessories: (BookRecord) -> [CatalogCardAccessory]
    let onBookSelected: ((UUID) -> Void)?

    init(
        books: [BookRecord],
        layoutMode: CatalogCardLayoutMode,
        layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics? = nil,
        bottomContentMargin: CGFloat? = nil,
        accessories: @escaping (BookRecord) -> [CatalogCardAccessory] = { _ in [] },
        onBookSelected: ((UUID) -> Void)? = nil
    ) {
        self.books = books
        self.layoutMode = layoutMode
        self.layoutMetrics = layoutMetrics
        self.bottomContentMargin = bottomContentMargin
        self.accessories = accessories
        self.onBookSelected = onBookSelected
    }

    var body: some View {
        CatalogCardGrid(
            layoutMode: layoutMode,
            bottomContentMargin: bottomContentMargin,
            layoutMetrics: layoutMetrics
        ) { cardSize, _, cardMetrics in
            ForEach(books) { book in
                CatalogInteractiveCard(
                    cardSize: cardSize,
                    onTap: {
                        onBookSelected?(book.id)
                    }
                ) {
                    BookCardView(
                        book: book,
                        style: CatalogCardContentStyle.style(for: layoutMode),
                        cardSize: cardSize,
                        cardMetrics: cardMetrics,
                        accessories: accessories(book)
                    )
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    let container = PreviewContainer.makeBooksMinimal()
    let snapshot = CatalogSnapshot.load(from: container.viewContext)

    BookGridView(
        books: snapshot.bookRecords,
        layoutMode: .compact
    )
}
#endif
