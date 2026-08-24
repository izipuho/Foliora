import SwiftUI
import UIKit

/// Displays the media preview image interface.
struct MediaPreviewImage: View {
    let identifier: String?
    let originalData: Data?
    let size: CGSize
    private let mediaStore = LocalMediaFileStore.shared
    private let thumbnailCache = ThumbnailImageCache.shared
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
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
        return "\(identifier ?? "data")-\(originalData?.count ?? 0)-\(pixelWidth)x\(pixelHeight)"
    }

    @MainActor
    private func loadImage() async {
        if let identifier {
            if mediaStore.thumbnailFileURL(for: identifier) == nil,
               let originalData {
                await Task.detached(priority: .utility) {
                    try? mediaStore.materializePhoto(
                        data: originalData,
                        identifier: identifier
                    )
                }.value
            }

            if let url = mediaStore.thumbnailFileURL(for: identifier) ?? mediaStore.fileURL(for: identifier) {
                if let loadedImage = await thumbnailCache.image(
                    identifier: identifier,
                    url: url,
                    targetSize: size,
                    scale: displayScale
                ) {
                    image = loadedImage
                    return
                }
            }
        }

        if let originalData,
           let loadedImage = UIImage(data: originalData) {
            image = loadedImage
        }
    }
}
