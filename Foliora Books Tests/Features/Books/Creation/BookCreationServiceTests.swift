import CoreData
import Testing
import UIKit
@testable import Foliora_Books

@MainActor
struct BookCreationServiceTests {
    @Test
    func failedCoverCropUsesOriginalMediaAsCover() async throws {
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 40, height: 60)
        ).image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
        let originalData = try #require(image.jpegData(compressionQuality: 0.92))
        let source = MediaAsset(
            id: UUID(),
            itemID: UUID(),
            kind: .photo,
            displayName: nil,
            sortOrder: 0,
            mimeType: "image/jpeg",
            byteSize: originalData.count,
            width: 40,
            height: 60,
            originalData: originalData
        )

        let itemID = UUID()
        let prepared = await ItemCreationService.prepareBookDraft(
            [source],
            itemID: itemID
        )
        let cover = try #require(prepared.coverImage)

        #expect(prepared.itemID == itemID)
        #expect(prepared.usedOriginalCover)
        #expect(prepared.mediaAssets.isEmpty)
        #expect(cover.id != source.id)
        #expect(cover.itemID == itemID)
        #expect(cover.originalData == source.originalData)
        #expect(cover.originalData.flatMap(UIImage.init(data:)) != nil)
    }

    @Test
    func originalFallbackSurvivesPersistenceRoundTrip() async throws {
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 40, height: 60)
        ).image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
        let originalData = try #require(image.jpegData(compressionQuality: 0.92))
        let source = MediaAsset(
            id: UUID(),
            itemID: UUID(),
            kind: .photo,
            displayName: nil,
            sortOrder: 0,
            mimeType: "image/jpeg",
            byteSize: originalData.count,
            width: 40,
            height: 60,
            originalData: originalData
        )

        let draft = await ItemCreationService.prepareBookDraft([source])
        #expect(draft.usedOriginalCover)

        let container = try FolioraCoreDataStack.makeInMemoryContainer()
        let context = container.viewContext
        let repository = CoreDataCatalogRepository(
            context: context,
            persistentContainer: nil
        )
        let collectionID = UUID()
        repository.saveCollection(
            Collection(
                id: collectionID,
                homeID: UUID(),
                kind: .books,
                title: "Books",
                notes: ""
            )
        )

        var state = BookEditorState(
            book: nil,
            creationDraft: draft
        )
        state.title = "Book"
        repository.saveBookRecord(
            state.makeBook(
                itemID: draft.itemID,
                collectionID: collectionID,
                existingBook: nil,
                storageLocation: nil,
                storagePath: nil
            )
        )

        let request = NSFetchRequest<NSManagedObject>(entityName: "BookEntity")
        let entity = try #require(try context.fetch(request).first)
        let reloaded = CoreDataDomainMapper.bookRecord(from: entity)
        let persistedCover = try #require(reloaded.details.coverImage)

        #expect(persistedCover.id == draft.coverImage?.id)
        #expect(persistedCover.originalData?.isEmpty == false)
        #expect(persistedCover.originalData.flatMap(UIImage.init(data:)) != nil)
        #expect(reloaded.cover.mediaAsset?.id == persistedCover.id)
    }
}
