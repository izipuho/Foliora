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
        guard let originalData else {
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
