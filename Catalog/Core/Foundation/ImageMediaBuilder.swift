import Foundation
import CryptoKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ImageMedia {
    let asset: MediaAsset
    let uiImage: UIImage
}

struct ImageMediaBuilder {
    let store: LocalMediaFileStore

    @MainActor
    func build(from item: PhotosPickerItem) async throws -> ImageMedia {
        guard let data = try await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let contentType = item.supportedContentTypes.first
        return try build(
            from: data,
            image: image,
            preferredFileExtension: contentType?.preferredFilenameExtension,
            mimeType: contentType?.preferredMIMEType
        )
    }

    func build(from image: UIImage) throws -> ImageMedia {
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw CocoaError(.fileWriteUnknown)
        }

        return try build(
            from: data,
            image: image,
            preferredFileExtension: "jpg",
            mimeType: "image/jpeg"
        )
    }

    func build(
        from data: Data,
        image: UIImage,
        preferredFileExtension: String?,
        mimeType: String? = nil
    ) throws -> ImageMedia {
        let identifier = try store.savePhoto(data: data, preferredFileExtension: preferredFileExtension)
        let asset = MediaAsset(
            id: UUID(),
            itemID: UUID(),
            kind: .photo,
            localIdentifier: identifier,
            displayName: nil,
            sortOrder: 0,
            fileName: identifier,
            mimeType: mimeType ?? Self.mimeType(for: preferredFileExtension),
            byteSize: data.count,
            checksum: Self.checksum(for: data),
            width: Int(image.size.width * image.scale),
            height: Int(image.size.height * image.scale),
            thumbnailData: Self.thumbnailData(for: image),
            originalData: data
        )

        return ImageMedia(asset: asset, uiImage: image)
    }

    private static func checksum(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func mimeType(for fileExtension: String?) -> String? {
        guard let fileExtension else { return nil }
        return UTType(filenameExtension: fileExtension)?.preferredMIMEType
    }

    private static func pixelWidth(for image: UIImage) -> Int {
        image.cgImage?.width ?? Int((image.size.width * image.scale).rounded())
    }

    private static func pixelHeight(for image: UIImage) -> Int {
        image.cgImage?.height ?? Int((image.size.height * image.scale).rounded())
    }

    private static func thumbnailData(for image: UIImage) -> Data? {
        let maxPixelSize: CGFloat = 700
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let longestSide = max(pixelSize.width, pixelSize.height)
        guard longestSide > 0 else { return nil }

        let scale = min(1, maxPixelSize / longestSide)
        let targetSize = CGSize(
            width: max(1, (pixelSize.width * scale).rounded()),
            height: max(1, (pixelSize.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        return UIGraphicsImageRenderer(size: targetSize, format: format)
            .image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            .jpegData(compressionQuality: 0.82)
    }
}
