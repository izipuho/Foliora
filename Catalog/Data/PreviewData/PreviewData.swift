import CoreData
import Foundation
import UIKit

@MainActor
enum PreviewData {
    struct CoreMinimal {
        let home: Home
        let locations: [Location]
        let collection: Collection
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
            notes: "My favorite collection at my lake house."
        )
        let items = [
            makeItem(
                title: "First Item",
                collectionID: collectionID,
                location: firstShelf,
                storagePath: "First Floor / Living Room / Cabinet / Top Shelf"
            ),
            makeItem(
                title: "Second Item",
                collectionID: collectionID,
                location: secondShelf,
                storagePath: "First Floor / Living Room / Cabinet / Bottom Shelf"
            ),
            makeItem(
                title: "Third Item",
                collectionID: collectionID,
                location: nil,
                storagePath: ""
            )
        ]

        return CoreMinimal(
            home: home,
            locations: [floor, room, cabinet, firstShelf, secondShelf],
            collection: collection,
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
                    makePreviewPhoto(itemID: item.id, resourceName: "IMG_8938", sortOrder: 0)
                ]
            case 2:
                item.mediaAssets = [
                    makePreviewPhoto(itemID: item.id, resourceName: "IMG_8934", sortOrder: 0),
                    makePreviewPhoto(itemID: item.id, resourceName: "IMG_8937", sortOrder: 1)
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

    static func makePreviewPhoto(itemID: UUID, resourceName: String, sortOrder: Int) -> MediaAsset {
        guard let image = UIImage(named: resourceName) else {
            fatalError("Preview image resource not found: \(resourceName)")
        }
        guard let originalData = image.jpegData(compressionQuality: 0.92),
              let thumbnailData = thumbnailData(for: image) else {
            fatalError("Preview image data could not be created: \(resourceName)")
        }

        return MediaAsset(
            id: UUID(),
            itemID: itemID,
            kind: .photo,
            localIdentifier: "",
            displayName: nil,
            sortOrder: sortOrder,
            fileName: "\(resourceName).jpg",
            mimeType: "image/jpeg",
            byteSize: originalData.count,
            width: pixelWidth(for: image),
            height: pixelHeight(for: image),
            thumbnailData: thumbnailData,
            originalData: originalData
        )
    }

    private static func pixelWidth(for image: UIImage) -> Int {
        image.cgImage?.width ?? Int((image.size.width * image.scale).rounded())
    }

    private static func pixelHeight(for image: UIImage) -> Int {
        image.cgImage?.height ?? Int((image.size.height * image.scale).rounded())
    }

    private static func thumbnailData(for image: UIImage) -> Data? {
        let maxPixelSize: CGFloat = 700
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let longestSide = max(pixelSize.width, pixelSize.height)
        guard longestSide > 0 else { return nil }

        let scale = min(1, maxPixelSize / longestSide)
        let targetSize = CGSize(
            width: max(1, (pixelSize.width * scale).rounded()),
            height: max(1, (pixelSize.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        return UIGraphicsImageRenderer(size: targetSize, format: format)
            .image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            .jpegData(compressionQuality: 0.82)
    }

    private static func makeItem(
        title: String,
        collectionID: UUID,
        location: Location?,
        storagePath: String
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
