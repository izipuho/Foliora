import CoreGraphics
import Foundation
import ImageIO
import UIKit

private struct ThumbnailCacheKey: Hashable, Sendable {
    let identifier: String
    let pixelWidth: Int
    let pixelHeight: Int
}

private final class ThumbnailImageBox: @unchecked Sendable {
    let image: UIImage

    init(image: UIImage) {
        self.image = image
    }
}

actor ThumbnailImageCache {
    static let shared = ThumbnailImageCache()

    private var images: [ThumbnailCacheKey: ThumbnailImageBox] = [:]

    func image(
        identifier: String,
        url: URL,
        targetSize: CGSize,
        scale: CGFloat
    ) async -> UIImage? {
        let pixelWidth = max(Int((targetSize.width * scale).rounded(.up)), 1)
        let pixelHeight = max(Int((targetSize.height * scale).rounded(.up)), 1)
        let key = ThumbnailCacheKey(
            identifier: identifier,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )

        if let cachedImage = images[key]?.image {
            return cachedImage
        }

        let maxPixelSize = max(pixelWidth, pixelHeight)
        let decodedImage = await Task.detached(priority: .utility) {
            Self.decodeImage(url: url, maxPixelSize: maxPixelSize, scale: scale)
        }.value

        guard let decodedImage else { return nil }
        images[key] = ThumbnailImageBox(image: decodedImage)
        return decodedImage
    }

    private static func decodeImage(url: URL, maxPixelSize: Int, scale: CGFloat) -> UIImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary

        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
