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
        repository.saveBookSeries(
            BookSeries(
                id: UUID(),
                collectionID: core.items[0].collectionID,
                name: "Standalone Preview Series",
                totalBookCount: nil,
                publisher: nil
            )
        )
    }

    private static func makeMinimalBookRecords(from core: CoreMinimal) -> [BookRecord] {
        let publisherLocation = Place(
            id: UUID(),
            displayName: "London, United Kingdom",
            countryCode: "GB",
            countryName: "United Kingdom",
            regionName: "England",
            cityName: "London",
            latitude: 51.5072,
            longitude: -0.1276
        )
        let publisher = Publisher(
            id: UUID(),
            name: "Preview Publisher",
            location: publisherLocation,
            logos: [
                makePreviewPhoto(
                    resourcePath: "Media/IMG_7502.HEIC",
                    sortOrder: 0
                )
            ]
        )
        let series = BookSeries(
            id: UUID(),
            collectionID: core.items[0].collectionID,
            name: "Preview Series",
            totalBookCount: 3,
            publisher: publisher
        )

        let author = Person(
            id: UUID(),
            name: "Author One",
            birthYear: 1927,
            deathYear: 2014,
            biography: "Preview biography for the primary book author.",
            birthPlace: nil,
            deathPlace: nil,
            photos: [
                makePreviewPhoto(
                    resourcePath: "Media/IMG_7503.HEIC",
                    sortOrder: 0
                )
            ]
        )
        let translator = Person(
            id: UUID(),
            name: "Translator One",
            birthYear: 1950,
            deathYear: nil,
            biography: nil,
            birthPlace: nil,
            deathPlace: nil
        )
        let editor = Person(
            id: UUID(),
            name: "Editor One",
            birthYear: nil,
            deathYear: nil,
            biography: nil,
            birthPlace: nil,
            deathPlace: nil
        )
        let illustrator = Person(
            id: UUID(),
            name: "Illustrator One",
            birthYear: nil,
            deathYear: nil,
            biography: nil,
            birthPlace: nil,
            deathPlace: nil
        )

        return core.items.enumerated().map { index, sourceItem in
            var item = sourceItem
            item.kind = .books

            switch index {
            case 0:
                item.title = "First Book"
                item.notes = "A fully populated preview record used to validate the book detail layout on iPhone and in the iPad inspector."
                item.acquiredYear = 2021
                item.condition = .good
                item.acquisitionMethod = .bought
                item.isFavorite = true
                item.tags = ["fiction", "classic", "latin america"]
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
                        publicationYear: 1967,
                        volumeNumber: 1,
                        publisher: publisher,
                        contributors: [
                            BookContributor(role: .author, order: 0, person: author),
                            BookContributor(role: .translator, order: 1, person: translator),
                            BookContributor(role: .editor, order: 2, person: editor),
                            BookContributor(role: .illustrator, order: 3, person: illustrator)
                        ],
                        series: series,
                        identifiers: [
                            BookIdentifier(type: .isbn13, value: "978-1-23456-789-0"),
                            BookIdentifier(type: .isbn10, value: "1-23456-789-X"),
                            BookIdentifier(type: .asin, value: "B012345678"),
                            BookIdentifier(type: .inventory, value: "BOOK-0001")
                        ]
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
                        publicationYear: 1987,
                        volumeNumber: nil,
                        publisher: nil,
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
                                    name: "Translator Two",
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
                        publicationYear: nil,
                        volumeNumber: 2,
                        publisher: nil,
                        contributors: [
                            BookContributor(
                                role: .editor,
                                order: 0,
                                person: Person(
                                    id: UUID(),
                                    name: "Editor Two",
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
