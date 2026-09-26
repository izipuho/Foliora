import Testing
import UIKit
@testable import Foliora_Books

@MainActor
struct BookCreationServiceTests {
    @Test
    func originalFallbackCreatesDedicatedSelfContainedCover() throws {
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 40, height: 60)
        ).image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }
        let itemID = UUID()

        let cover = try #require(
            ItemCreationService.makeOriginalBookCover(
                image,
                itemID: itemID
            )
        )
        defer {
            LocalMediaFileStore.shared.deleteFile(for: cover.localIdentifier)
        }

        #expect(cover.itemID == itemID)
        #expect(!cover.localIdentifier.isEmpty)
        #expect(cover.displayName == String(localized: "editor.media.cover"))
        #expect(cover.originalData?.isEmpty == false)
        #expect(LocalMediaFileStore.shared.fileURL(for: cover.localIdentifier) != nil)

        let originalData = try #require(cover.originalData)
        #expect(UIImage(data: originalData) != nil)
    }
}
