import CoreData
import Foundation
import UIKit

/// Groups preview data values and behavior.
@MainActor
enum PreviewData {
    struct CoreMinimal {
        let home: Home
        let locations: [Location]
        let collection: Collection
        let secondaryCollection: Collection
        let items: [ItemRecord]
    }

    static func populateMinimal(context: NSManagedObjectContext) {
        let repository = CoreDataCatalogRepository(
            context: context,
            persistentContainer: nil
        )
        let core = makeCoreMinimal(collectionKind: .bells)
        let bells = makeMinimalBells(from: core)

        repository.saveHome(core.home)
        repository.saveLocations(core.locations, in: core.home.id)
        repository.saveCollection(core.collection)
        repository.saveCollection(core.secondaryCollection)
        repository.saveBellRecords(bells)
    }

    static func makeCoreMinimal(collectionKind: CollectionKind) -> CoreMinimal {
        let homeID = UUID()
        let floorID = UUID()
        let roomID = UUID()
        let cabinetID = UUID()
        let firstShelfID = UUID()
        let secondShelfID = UUID()
        let collectionID = UUID()
        let secondaryCollectionID = UUID()

        let home = Home(
            id: homeID,
            name: "Lake House",
            notes: "My cozy house at the lake shore. I have small collection here."
        )
        let floor = Location(
            id: floorID,
            homeID: homeID,
            parentLocationID: nil,
            kind: .floor,
            name: "First Floor",
            notes: "",
            sortOrder: 0
        )
        let room = Location(
            id: roomID,
            homeID: homeID,
            parentLocationID: floorID,
            kind: .room,
            name: "Living Room",
            notes: "",
            sortOrder: 0
        )
        let cabinet = Location(
            id: cabinetID,
            homeID: homeID,
            parentLocationID: roomID,
            kind: .cabinet,
            name: "Cabinet",
            notes: "",
            sortOrder: 0
        )
        let firstShelf = Location(
            id: firstShelfID,
            homeID: homeID,
            parentLocationID: cabinetID,
            kind: .shelf,
            name: "Top Shelf",
            notes: "",
            sortOrder: 0
        )
        let secondShelf = Location(
            id: secondShelfID,
            homeID: homeID,
            parentLocationID: cabinetID,
            kind: .shelf,
            name: "Bottom Shelf",
            notes: "",
            sortOrder: 1
        )
        let collection = Collection(
            id: collectionID,
            homeID: homeID,
            kind: collectionKind,
            title: collectionKind.title,
            notes: "My favorite collection at my lake house.",
            backgroundStyle: .amber
        )
        let secondaryCollection = Collection(
            id: secondaryCollectionID,
            homeID: homeID,
            kind: collectionKind,
            title: "Travel Finds",
            notes: "Pieces waiting to be cataloged from recent trips.",
            backgroundStyle: .sky
        )
        let items = [
            makeItem(
                title: "First Item",
                collectionID: collectionID,
                location: firstShelf,
                storagePath: StoragePath(
                    components: [
                        .init(kind: .floor, name: "First Floor"),
                        .init(kind: .room, name: "Living Room"),
                        .init(kind: .cabinet, name: "Cabinet"),
                        .init(kind: .shelf, name: "Top Shelf")
                    ]
                )
            ),
            makeItem(
                title: "Second Item",
                collectionID: collectionID,
                location: secondShelf,
                storagePath: StoragePath(
                    components: [
                        .init(kind: .floor, name: "First Floor"),
                        .init(kind: .room, name: "Living Room"),
                        .init(kind: .cabinet, name: "Cabinet"),
                        .init(kind: .shelf, name: "Bottom Shelf")
                    ]
                )
            ),
            makeItem(
                title: "Third Item",
                collectionID: collectionID,
                location: nil,
                storagePath: nil
            )
        ]

        return CoreMinimal(
            home: home,
            locations: [floor, room, cabinet, firstShelf, secondShelf],
            collection: collection,
            secondaryCollection: secondaryCollection,
            items: items
        )
    }

    static func makeMinimalBells(from core: CoreMinimal) -> [BellRecord] {
        let materials: [BellMaterial] = [.unknown, .brass, .ceramic]

        return zip(core.items, materials).enumerated().map { index, pair in
            var item = pair.0
            let material = pair.1

            switch index {
            case 0:
                item.mediaAssets = [
                    makePreviewPhoto(itemID: item.id, resourcePath: "Bells/IMG_8938.HEIC", sortOrder: 0)
                ]
            case 2:
                item.mediaAssets = [
                    makePreviewPhoto(itemID: item.id, resourcePath: "Bells/IMG_8934.HEIC", sortOrder: 0),
                    makePreviewPhoto(itemID: item.id, resourcePath: "Bells/IMG_8937.HEIC", sortOrder: 1)
                ]
            default:
                item.mediaAssets = []
            }

            return BellRecord(
                item: item,
                details: BellDetails(
                    itemID: item.id,
                    material: material,
                    customMaterialName: nil
                )
            )
        }
    }

    static func makePreviewPhoto(itemID: UUID, resourcePath: String, sortOrder: Int) -> MediaAsset {
        guard let image = UIImage(named: resourcePath) ?? bundlePreviewImage(at: resourcePath) else {
            fatalError("Preview image resource not found: \(resourcePath)")
        }
        guard let originalData = image.jpegData(compressionQuality: 0.92) else {
            fatalError("Preview image data could not be created: \(resourcePath)")
        }

        return MediaAsset(
            id: UUID(),
            itemID: itemID,
            kind: .photo,
            localIdentifier: "",
            displayName: nil,
            sortOrder: sortOrder,
            fileName: (resourcePath as NSString).lastPathComponent,
            mimeType: "image/jpeg",
            byteSize: originalData.count,
            width: pixelWidth(for: image),
            height: pixelHeight(for: image),
            originalData: originalData
        )
    }

    private static func bundlePreviewImage(at resourcePath: String) -> UIImage? {
        let filePath = (resourcePath as NSString).lastPathComponent as NSString
        guard let url = Bundle.main.url(
            forResource: filePath.deletingPathExtension,
            withExtension: filePath.pathExtension
        ) else {
            return nil
        }

        return UIImage(contentsOfFile: url.path)
    }

    private static func pixelWidth(for image: UIImage) -> Int {
        image.cgImage?.width ?? Int((image.size.width * image.scale).rounded())
    }

    private static func pixelHeight(for image: UIImage) -> Int {
        image.cgImage?.height ?? Int((image.size.height * image.scale).rounded())
    }

    private static func makeItem(
        title: String,
        collectionID: UUID,
        location: Location?,
        storagePath: StoragePath?
    ) -> ItemRecord {
        ItemRecord(
            id: UUID(),
            collectionID: collectionID,
            locationID: location?.id,
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
            storageLocation: location,
            storagePath: storagePath,
            mediaAssets: []
        )
    }
}
