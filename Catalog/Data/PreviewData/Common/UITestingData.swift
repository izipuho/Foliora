#if DEBUG
import CoreData
import Foundation

/// Fixed UI-test layout shared by every app: one collection, three items on Top Shelf,
/// one on Bottom Shelf and one without a location. UI tests rely on these titles.
@MainActor
extension PreviewData {
    struct UITestingItem {
        let title: String
        let tags: [String]
        let template: ItemRecord
    }

    /// Saves the home, its locations and a single collection, so the app opens it directly.
    static func saveUITestingCore(
        collectionKind: CollectionKind,
        using repository: CoreDataCatalogRepository
    ) -> [UITestingItem] {
        let core = makeCoreMinimal(collectionKind: collectionKind)
        repository.saveHome(core.home)
        repository.saveLocations(core.locations, in: core.home.id)
        repository.saveCollection(core.collection)

        let topShelf = core.items[0]
        let bottomShelf = core.items[1]
        let unassigned = core.items[2]
        let prefix = collectionKind == .books ? "Book" : "Bell"

        return [
            UITestingItem(title: "Top \(prefix) A", tags: ["souvenir"], template: topShelf),
            UITestingItem(title: "Top \(prefix) B", tags: [], template: topShelf),
            UITestingItem(title: "Top \(prefix) C", tags: [], template: topShelf),
            UITestingItem(title: "Bottom \(prefix)", tags: [], template: bottomShelf),
            UITestingItem(title: "Loose \(prefix)", tags: [], template: unassigned)
        ]
    }

    /// Builds a new item in the template's collection and location.
    static func makeUITestingItemRecord(_ item: UITestingItem) -> ItemRecord {
        let template = item.template
        return ItemRecord(
            id: UUID(),
            collectionID: template.collectionID,
            kind: template.kind,
            locationID: template.locationID,
            originPlaceID: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            createdBy: "",
            title: item.title,
            notes: "",
            acquiredYear: nil,
            condition: .good,
            acquisitionMethod: .other,
            isFavorite: false,
            tags: item.tags,
            originPlace: nil,
            storageLocation: template.storageLocation,
            storagePath: template.storagePath,
            mediaAssets: []
        )
    }
}
#endif
