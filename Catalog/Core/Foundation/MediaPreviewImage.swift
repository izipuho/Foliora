import SwiftUI
import UIKit

/// Displays the media preview image interface.
struct MediaPreviewImage: View {
    let assetID: UUID
    let originalData: Data?
    let size: CGSize
    let contentMode: ContentMode
    private let thumbnailCache = ThumbnailImageCache.shared
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    init(
        assetID: UUID,
        originalData: Data?,
        size: CGSize,
        contentMode: ContentMode = .fill
    ) {
        self.assetID = assetID
        self.originalData = originalData
        self.size = size
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [
                        CatalogMediaContrast.onMediaPrimary.opacity(0.88),
                        CatalogMediaContrast.onMediaPrimary.opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: size.width, height: size.height)
            }
        }
        .task(id: thumbnailTaskID) {
            await loadImage()
        }
    }

    private var thumbnailTaskID: String {
        let pixelWidth = Int((size.width * displayScale).rounded(.up))
        let pixelHeight = Int((size.height * displayScale).rounded(.up))
        return "\(assetID.uuidString)-\(originalData?.count ?? 0)-\(pixelWidth)x\(pixelHeight)"
    }

    @MainActor
    private func loadImage() async {
        let tag = "asset=\(assetID.uuidString.prefix(8)) size=\(Int(size.width))x\(Int(size.height))"
        guard let originalData else {
            MediaDiagnostics.log("preview no data \(tag)")
            image = nil
            return
        }

        MediaDiagnostics.log("preview start \(tag) bytes=\(originalData.count) hasImage=\(image != nil)")

        if let loadedImage = await thumbnailCache.image(
            assetID: assetID,
            data: originalData,
            targetSize: size,
            scale: displayScale
        ) {
            guard !Task.isCancelled else {
                MediaDiagnostics.log("preview cancelled after decode \(tag) hasImage=\(image != nil)")
                return
            }
            image = loadedImage
            MediaDiagnostics.log("preview shown \(tag)")
            return
        }

        guard !Task.isCancelled else {
            MediaDiagnostics.log("preview cancelled after failed decode \(tag)")
            return
        }
        let fallbackImage = UIImage(data: originalData)
        if fallbackImage == nil {
            MediaDiagnostics.log("preview decode failed \(tag) bytes=\(originalData.count)")
        }
        image = fallbackImage
    }
}
