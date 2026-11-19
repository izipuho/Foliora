import SwiftUI

/// Displays the books stored in one location, with the same selection and actions as the library.
struct BookStorageItemsView: View {
    let books: [BookRecord]
    let layoutMode: CatalogCardLayoutMode
    let actions: BookCardActions
    let tint: Color
    let onBookSelected: ((UUID) -> Void)?

    @State private var cardManagement = CatalogCardManagementState<BookRecord>()
    @State private var haptics = CatalogHapticTrigger()

    var body: some View {
        BookGridView(
            books: books,
            layoutMode: layoutMode,
            cardManagement: $cardManagement,
            canManage: actions.canEdit,
            onOpen: { book in
                onBookSelected?(book.id)
            },
            deleteTitle: String(localized: "book.delete.title"),
            deleteMessage: String(localized: "book.delete.message"),
            onDelete: { books in
                actions.delete(books)
                haptics.play(.destructiveCompleted)
            }
        )
        .modifier(
            CatalogCardManagementModifier(
                state: $cardManagement,
                visibleItems: books,
                actions: actions,
                tint: tint,
                showsSelectButton: true,
                onMoved: { haptics.play(.completed) },
                onDeleted: { haptics.play(.destructiveCompleted) }
            )
        )
        .catalogHaptics(haptics)
        .onChange(of: books.map(\.id)) {
            cardManagement.pruneSelection(to: books)
        }
    }
}
