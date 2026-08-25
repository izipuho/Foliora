import CoreData
import Foundation

@MainActor
extension PreviewData {
    static func populateCollectionsMinimal(context: NSManagedObjectContext) {
        let repository = CoreDataCatalogRepository(
            context: context,
            persistentContainer: nil
        )
        let base = makeCoreMinimal(collectionKind: .bells)

        var booksCollection = base.secondaryCollection
        booksCollection.kind = .books
        booksCollection.title = CollectionKind.books.title
        booksCollection.notes = "Books collected at the lake house."
        booksCollection.backgroundStyle = .mint

        var bellItems = base.items
        for index in bellItems.indices {
            bellItems[index].kind = .bells
        }

        let bookItems = [
            makeCollectionsPreviewItem(
                title: "The First Book",
                collectionID: booksCollection.id,
                kind: .books
            ),
            makeCollectionsPreviewItem(
                title: "The Second Book",
                collectionID: booksCollection.id,
                kind: .books
            )
        ]

        let mixed = CoreMinimal(
            home: base.home,
            locations: base.locations,
            collection: base.collection,
            secondaryCollection: booksCollection,
            items: bellItems + bookItems
        )

        saveCore(mixed, using: repository)
        repository.saveItemRecords(mixed.items)
    }

    private static func makeCollectionsPreviewItem(
        title: String,
        collectionID: UUID,
        kind: CollectionKind
    ) -> ItemRecord {
        ItemRecord(
            id: UUID(),
            collectionID: collectionID,
            kind: kind,
            locationID: nil,
            originPlaceID: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            createdBy: "",
            title: title,
            notes: "",
            acquiredYear: nil,
            condition: .good,
            acquisitionMethod: .other,
            isFavorite: false,
            tags: [],
            originPlace: nil,
            storageLocation: nil,
            storagePath: nil,
            mediaAssets: []
        )
    }
}
