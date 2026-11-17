import SwiftUI

/// Displays the books stored in one location, with the same selection and actions as the library.
struct BookStorageItemsView: View {
    let books: [BookRecord]
    let layoutMode: CatalogCardLayoutMode
    let actions: BookCardActions
    let tint: Color
    let onBookSelected: ((UUID) -> Void)?

    @State private var cardManagement = CatalogCardManagementState<BookRecord>()
    @State private var moveFeedbackToken = 0
    @State private var deleteFeedbackToken = 0

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
                deleteFeedbackToken += 1
            }
        )
        .modifier(
            CatalogCardManagementModifier(
                state: $cardManagement,
                visibleItems: books,
                actions: actions,
                tint: tint,
                showsSelectButton: true,
                onMoved: { moveFeedbackToken += 1 },
                onDeleted: { deleteFeedbackToken += 1 }
            )
        )
        .sensoryFeedback(.success, trigger: moveFeedbackToken)
        .sensoryFeedback(.warning, trigger: deleteFeedbackToken)
        .onChange(of: books.map(\.id)) {
            cardManagement.pruneSelection(to: books)
        }
    }
}
