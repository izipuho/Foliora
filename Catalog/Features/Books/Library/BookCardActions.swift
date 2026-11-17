import Foundation

/// Persists book card-management actions (move, delete, batch edit) for every screen that manages books.
struct BookCardActions {
    let repository: any AppRepository
    let snapshot: CatalogSnapshot?
    let collection: CollectionSummary?
    let canEdit: Bool

    func saveHome(_ home: Home, locations: [Location]) {
        repository.saveHome(home)
        repository.saveLocations(locations, in: home.id)
    }

    func move(_ books: [BookRecord], to locationID: UUID?) {
        guard canEdit else { return }

        let storageContext = CatalogStorageContext(snapshot: snapshot, collection: collection)
        let location = storageContext.location(for: locationID)
        for book in books {
            repository.saveBookRecord(
                book.moving(
                    to: location,
                    storagePath: location.map(storageContext.storagePath(for:))
                )
            )
        }
    }

    func delete(_ books: [BookRecord]) {
        guard canEdit else { return }

        for book in books {
            repository.deleteBookRecord(bookID: book.id)
        }
    }

    func batchEdit(
        _ books: [BookRecord],
        itemEdit: ItemBatchEdit,
        bookEdit: BookBatchEdit
    ) {
        guard canEdit, !books.isEmpty else { return }

        let updatedBooks = books.map { book in
            BookRecord(
                item: itemEdit.applying(to: book.item),
                details: bookEdit.applying(to: book.details)
            )
        }
        repository.saveBookRecords(updatedBooks)
    }
}
