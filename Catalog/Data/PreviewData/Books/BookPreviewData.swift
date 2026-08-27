import CoreData
import Foundation

@MainActor
extension PreviewData {
    static func populateMinimalBooks(context: NSManagedObjectContext) {
        let repository = CoreDataCatalogRepository(
            context: context,
            persistentContainer: nil
        )
        let core = makeCoreMinimal(collectionKind: .books)
        let books = makeMinimalBookRecords(from: core)

        saveCore(core, using: repository)
        repository.saveBookRecords(books)
    }

    private static func makeMinimalBookRecords(from core: CoreMinimal) -> [BookRecord] {
        let publicationPlace = Place(
            id: UUID(),
            displayName: "London, United Kingdom",
            countryCode: "GB",
            countryName: "United Kingdom",
            regionName: nil,
            cityName: "London",
            latitude: nil,
            longitude: nil
        )
        let series = BookSeries(
            id: UUID(),
            collectionID: core.items[0].collectionID,
            name: "Preview Series",
            totalBookCount: 3
        )

        return core.items.enumerated().map { index, sourceItem in
            var item = sourceItem
            item.kind = .books

            switch index {
            case 0:
                item.title = "First Book"
                item.isFavorite = true
                item.tags = ["fiction", "classic"]
                item.mediaAssets = previewBookPhotos(
                    itemID: item.id,
                    names: ["IMG_7502.HEIC", "IMG_7503.HEIC", "IMG_7504.HEIC"]
                )

                return BookRecord(
                    item: item,
                    details: BookDetails(
                        itemID: item.id,
                        languageCode: "en",
                        pageCount: 320,
                        publicationPlaceName: "London",
                        publicationYear: 1954,
                        volumeNumber: 1,
                        publicationPlace: publicationPlace,
                        contributors: [
                            BookContributor(
                                role: .author,
                                order: 0,
                                person: Person(
                                    id: UUID(),
                                    name: "Author One",
                                    birthYear: nil,
                                    deathYear: nil,
                                    biography: nil,
                                    birthPlace: nil,
                                    deathPlace: nil
                                )
                            )
                        ],
                        series: series
                    )
                )

            case 1:
                item.title = "Second Book"
                item.tags = ["translated"]
                item.mediaAssets = previewBookPhotos(
                    itemID: item.id,
                    names: ["IMG_7505.HEIC", "IMG_7506.HEIC", "IMG_7507.HEIC"]
                )

                return BookRecord(
                    item: item,
                    details: BookDetails(
                        itemID: item.id,
                        languageCode: "ru",
                        pageCount: 480,
                        publicationPlaceName: nil,
                        publicationYear: 1987,
                        volumeNumber: nil,
                        publicationPlace: nil,
                        contributors: [
                            BookContributor(
                                role: .author,
                                order: 0,
                                person: Person(
                                    id: UUID(),
                                    name: "Author Two",
                                    birthYear: nil,
                                    deathYear: nil,
                                    biography: nil,
                                    birthPlace: nil,
                                    deathPlace: nil
                                )
                            ),
                            BookContributor(
                                role: .translator,
                                order: 1,
                                person: Person(
                                    id: UUID(),
                                    name: "Translator One",
                                    birthYear: nil,
                                    deathYear: nil,
                                    biography: nil,
                                    birthPlace: nil,
                                    deathPlace: nil
                                )
                            )
                        ]
                    )
                )

            default:
                item.title = "Third Book"
                item.isFavorite = true
                item.mediaAssets = previewBookPhotos(
                    itemID: item.id,
                    names: ["IMG_7508.HEIC", "IMG_7509.HEIC", "IMG_7510.HEIC"]
                )

                return BookRecord(
                    item: item,
                    details: BookDetails(
                        itemID: item.id,
                        languageCode: "en",
                        pageCount: nil,
                        publicationPlaceName: nil,
                        publicationYear: nil,
                        volumeNumber: 2,
                        publicationPlace: nil,
                        contributors: [
                            BookContributor(
                                role: .editor,
                                order: 0,
                                person: Person(
                                    id: UUID(),
                                    name: "Editor One",
                                    birthYear: nil,
                                    deathYear: nil,
                                    biography: nil,
                                    birthPlace: nil,
                                    deathPlace: nil
                                )
                            )
                        ],
                        series: series
                    )
                )
            }
        }
    }

    private static func previewBookPhotos(itemID: UUID, names: [String]) -> [MediaAsset] {
        names.enumerated().map { index, name in
            makePreviewPhoto(
                itemID: itemID,
                resourcePath: "Media/\(name)",
                sortOrder: index
            )
        }
    }
}

@MainActor
extension PreviewContainer {
    static func makeBooksMinimal() -> NSPersistentCloudKitContainer {
        do {
            let container = try FolioraCoreDataStack.makeInMemoryContainer()
            PreviewData.populateMinimalBooks(context: container.viewContext)
            return container
        } catch {
            fatalError("Failed to create books preview container: \(error)")
        }
    }
}
