import Foundation
import CryptoKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Represents image media data and behavior.
struct ImageMedia {
    let asset: MediaAsset
    let uiImage: UIImage
}

/// Provides image media builder operations.
struct ImageMediaBuilder {
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
        let assetID = UUID()
        let fileExtension = preferredFileExtension
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "jpg"
        let fileName = "photo-\(assetID.uuidString).\(fileExtension)"
        let asset = MediaAsset(
            id: assetID,
            itemID: UUID(),
            kind: .photo,
            localIdentifier: "",
            displayName: nil,
            sortOrder: 0,
            fileName: fileName,
            mimeType: mimeType ?? Self.mimeType(for: preferredFileExtension),
            byteSize: data.count,
            checksum: Self.checksum(for: data),
            width: Int(image.size.width * image.scale),
            height: Int(image.size.height * image.scale),
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

}
