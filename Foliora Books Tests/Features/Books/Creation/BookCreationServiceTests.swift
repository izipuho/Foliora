import CoreData
import Testing
import UIKit
@testable import Foliora_Books

@MainActor
struct BookCreationServiceTests {
    @Test
    func failedCoverCropUsesOriginalMediaAsCover() async throws {
        let originalData = try noiseJPEGData()
        let source = MediaAsset(
            id: UUID(),
            itemID: UUID(),
            kind: .photo,
            displayName: nil,
            sortOrder: 0,
            mimeType: "image/jpeg",
            byteSize: originalData.count,
            width: 120,
            height: 180,
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
        let originalData = try noiseJPEGData()
        let source = MediaAsset(
            id: UUID(),
            itemID: UUID(),
            kind: .photo,
            displayName: nil,
            sortOrder: 0,
            mimeType: "image/jpeg",
            byteSize: originalData.count,
            width: 120,
            height: 180,
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

    /// JPEG data of seeded per-pixel noise: a photo in which cover detection has nothing to find.
    ///
    /// A blank image does not work here, document segmentation reports it as a document.
    private func noiseJPEGData() throws -> Data {
        let width = 120
        let height = 180
        // A fixed seed keeps the fixture identical between runs.
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in pixels.indices {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            pixels[index] = UInt8(truncatingIfNeeded: state >> 56)
        }

        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )

        return try #require(UIImage(cgImage: image).jpegData(compressionQuality: 0.92))
    }
}
