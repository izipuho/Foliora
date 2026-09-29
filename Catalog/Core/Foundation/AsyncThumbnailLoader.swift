import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// Provides thumbnail image cache operations.
///
/// Thumbnails are keyed by asset and pixel size, so every layout mode adds a new set.
/// `NSCache` bounds the total decoded size and evicts under memory pressure.
actor ThumbnailImageCache {
    static let shared = ThumbnailImageCache()

    /// Upper bound for decoded thumbnail bitmaps kept in memory.
    nonisolated private static let totalCostLimit = 128 * 1_048_576

    private let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = ThumbnailImageCache.totalCostLimit
        return cache
    }()

    func image(
        assetID: UUID,
        data: Data,
        targetSize: CGSize,
        scale: CGFloat
    ) async -> UIImage? {
        let pixelWidth = max(Int((targetSize.width * scale).rounded(.up)), 1)
        let pixelHeight = max(Int((targetSize.height * scale).rounded(.up)), 1)
        let key = "\(assetID.uuidString)-\(pixelWidth)x\(pixelHeight)" as NSString

        if let cachedImage = images.object(forKey: key) {
            return cachedImage
        }

        let maxPixelSize = max(pixelWidth, pixelHeight)
        let decodedImage = await Task.detached(priority: .utility) {
            Self.decodeImage(data: data, maxPixelSize: maxPixelSize, scale: scale)
        }.value

        guard let decodedImage else { return nil }
        images.setObject(decodedImage, forKey: key, cost: Self.cost(of: decodedImage))
        return decodedImage
    }

    nonisolated private static func cost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private static func decodeImage(data: Data, maxPixelSize: Int, scale: CGFloat) -> UIImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary

        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
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
