#if DEBUG
import CoreData
import SwiftUI

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
        let book = snapshot.bookRecords.first { $0.item.collectionID == collection.id }

        BookEditorView(
            collection: collection,
            book: book
        ) { updatedBook in
            repository.saveBookRecord(updatedBook)
        }
        .previewEnvironment(container)
    }
}
#endif
