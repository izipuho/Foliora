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
        let source = try ImageMediaBuilder(store: .shared).build(from: image).asset
        defer {
            LocalMediaFileStore.shared.deleteFile(for: source.localIdentifier)
        }

        let itemID = UUID()
        let prepared = await ItemCreationService.prepareBookMedia(
            [source],
            itemID: itemID
        )
        let cover = try #require(prepared.coverImage)

        #expect(prepared.usedOriginalCover)
        #expect(prepared.mediaAssets.isEmpty)
        #expect(cover.id == source.id)
        #expect(cover.itemID == itemID)
        #expect(cover.localIdentifier == source.localIdentifier)
        #expect(cover.originalData == source.originalData)
        #expect(LocalMediaFileStore.shared.fileURL(for: source.localIdentifier) != nil)
    }
}
