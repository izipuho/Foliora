import SwiftUI

/// Displays book cards using the shared catalog grid mechanics, with optional card management.
struct BookGridView: View {
    let books: [BookRecord]
    let layoutMode: CatalogCardLayoutMode
    let bottomContentMargin: CGFloat?
    let layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics?
    @Binding var cardManagement: CatalogCardManagementState<BookRecord>
    let canManage: Bool
    let shouldHandleTap: (BookRecord) -> Bool
    let onOpen: (BookRecord) -> Void
    let visibleItems: [BookRecord]
    let deleteTitle: String
    let deleteMessage: String
    let onDelete: ([BookRecord]) -> Void
    let accessories: (BookRecord) -> [CatalogCardAccessory]

    init(
        books: [BookRecord],
        layoutMode: CatalogCardLayoutMode,
        bottomContentMargin: CGFloat? = nil,
        layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics? = nil,
        cardManagement: Binding<CatalogCardManagementState<BookRecord>>,
        canManage: Bool,
        shouldHandleTap: @escaping (BookRecord) -> Bool = { _ in true },
        onOpen: @escaping (BookRecord) -> Void,
        visibleItems: [BookRecord]? = nil,
        deleteTitle: String = "",
        deleteMessage: String = "",
        onDelete: @escaping ([BookRecord]) -> Void = { _ in },
        accessories: @escaping (BookRecord) -> [CatalogCardAccessory] = { _ in [] }
    ) {
        self.books = books
        self.layoutMode = layoutMode
        self.bottomContentMargin = bottomContentMargin
        self.layoutMetrics = layoutMetrics
        self._cardManagement = cardManagement
        self.canManage = canManage
        self.shouldHandleTap = shouldHandleTap
        self.onOpen = onOpen
        self.visibleItems = visibleItems ?? books
        self.deleteTitle = deleteTitle
        self.deleteMessage = deleteMessage
        self.onDelete = onDelete
        self.accessories = accessories
    }

    /// Creates a read-only grid: tapping a card opens it, no context menu or selection.
    init(
        books: [BookRecord],
        layoutMode: CatalogCardLayoutMode,
        bottomContentMargin: CGFloat? = nil,
        layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics? = nil,
        accessories: @escaping (BookRecord) -> [CatalogCardAccessory] = { _ in [] },
        onBookSelected: ((UUID) -> Void)?
    ) {
        self.init(
            books: books,
            layoutMode: layoutMode,
            bottomContentMargin: bottomContentMargin,
            layoutMetrics: layoutMetrics,
            cardManagement: .constant(CatalogCardManagementState()),
            canManage: false,
            onOpen: { book in
                onBookSelected?(book.id)
            },
            accessories: accessories
        )
    }

    var body: some View {
        CatalogCardGrid(
            layoutMode: layoutMode,
            bottomContentMargin: bottomContentMargin,
            layoutMetrics: layoutMetrics
        ) { cardSize, _, cardMetrics in
            ForEach(books) { book in
                CatalogInteractiveCard(
                    item: book,
                    state: $cardManagement,
                    cardSize: cardSize,
                    canManage: canManage,
                    shouldHandleTap: shouldHandleTap,
                    onOpen: onOpen,
                    selectTitle: String(localized: "bell.context.select"),
                    moveTitle: String(localized: "bell.context.move"),
                    visibleItems: visibleItems,
                    deleteTitle: deleteTitle,
                    deleteMessage: deleteMessage,
                    onDelete: onDelete
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
        layoutMode: .compact,
        onBookSelected: nil
    )
    .previewEnvironment(container)
}
#endif
