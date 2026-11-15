import SwiftUI
import UIKit

/// Displays the media preview image interface.
///
/// Pass `originalData` when the bytes are already in memory (unsaved media). Otherwise the image is
/// taken from the thumbnail cache or loaded by `assetID` through the environment's `MediaDataLoader`.
struct MediaPreviewImage: View {
    let assetID: UUID
    let originalData: Data?
    let size: CGSize
    let contentMode: ContentMode
    private let thumbnailCache = ThumbnailImageCache.shared
    @Environment(\.displayScale) private var displayScale
    @Environment(\.mediaDataLoader) private var mediaDataLoader
    @State private var image: UIImage?

    init(
        assetID: UUID,
        originalData: Data? = nil,
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
        if let cachedImage = await thumbnailCache.cachedImage(
            assetID: assetID,
            targetSize: size,
            scale: displayScale
        ) {
            image = cachedImage
            return
        }

        let resolvedData: Data?
        if let originalData {
            resolvedData = originalData
        } else {
            resolvedData = await mediaDataLoader?.data(forAssetID: assetID)
        }

        guard !Task.isCancelled else { return }
        guard let originalData = resolvedData else {
            image = nil
            return
        }

        if let loadedImage = await thumbnailCache.image(
            assetID: assetID,
            data: originalData,
            targetSize: size,
            scale: displayScale
        ) {
            guard !Task.isCancelled else { return }
            image = loadedImage
            return
        }

        guard !Task.isCancelled else { return }
        image = UIImage(data: originalData)
    }
}
