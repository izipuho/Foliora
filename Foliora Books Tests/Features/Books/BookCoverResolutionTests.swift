import Foundation
import Testing
@testable import Foliora_Books

struct BookCoverResolutionTests {
    @Test
    func dedicatedCoverWinsOverMediaPhoto() {
        let dedicatedCover = photo(identifier: "dedicated")
        let mediaPhoto = photo(identifier: "media")
        let book = makeBook(
            coverImage: dedicatedCover,
            mediaAssets: [mediaPhoto]
        )

        #expect(book.cover == .image(dedicatedCover))
    }

    @Test
    func mediaPhotoDoesNotBecomeCoverWithoutDedicatedCover() {
        let bookID = UUID()
        let mediaPhoto = photo(identifier: "media")
        let book = makeBook(id: bookID, title: "Book", mediaAssets: [mediaPhoto])

        #expect(
            book.cover == .generated(
                BookGeneratedCover(
                    bookID: bookID,
                    title: "Book",
                    authorNames: []
                )
            )
        )
    }

    @Test
    func generatedCoverIsFinalFallback() {
        let bookID = UUID()
        let book = makeBook(id: bookID, title: "The Empty Book")

        #expect(
            book.cover == .generated(
                BookGeneratedCover(
                    bookID: bookID,
                    title: "The Empty Book",
                    authorNames: []
                )
            )
        )
    }

    private func makeBook(
        id: UUID = UUID(),
        title: String = "Book",
        coverImage: MediaAsset? = nil,
        mediaAssets: [MediaAsset] = []
    ) -> BookRecord {
        BookRecord(
            item: ItemRecord(
                id: id,
                collectionID: UUID(),
                kind: .books,
                locationID: nil,
                originPlaceID: nil,
                createdAt: .now,
                createdBy: "test",
                title: title,
                notes: "",
                acquiredYear: nil,
                condition: .good,
                acquisitionMethod: .bought,
                isFavorite: false,
                tags: [],
                originPlace: nil,
                storageLocation: nil,
                storagePath: nil,
                mediaAssets: mediaAssets
            ),
            details: BookDetails(
                itemID: id,
                languageCode: nil,
                pageCount: nil,
                publicationYear: nil,
                volumeNumber: nil,
                coverImage: coverImage,
                contributors: []
            )
        )
    }

    private func photo(
        identifier: String,
        sortOrder: Int = 0
    ) -> MediaAsset {
        MediaAsset(
            id: UUID(),
            kind: .photo,
            localIdentifier: identifier,
            displayName: nil,
            sortOrder: sortOrder
        )
    }
}
