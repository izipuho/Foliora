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

/// Single entry point that turns picker items and captured images into photo `MediaAsset`s.
///
/// Image decoding, JPEG encoding and checksum hashing run off the main actor;
/// only the lightweight `MediaAsset` assembly happens on the caller's actor.
struct ImageMediaBuilder {
    /// Builds media from a Photos picker item.
    ///
    /// - Throws: `CocoaError(.fileReadCorruptFile)` when the item cannot be loaded or decoded.
    func build(from item: PhotosPickerItem) async throws -> ImageMedia {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let contentType = item.supportedContentTypes.first
        let encoded = try await Self.encode(pickedData: data)
        return makeMedia(
            from: encoded,
            preferredFileExtension: contentType?.preferredFilenameExtension,
            mimeType: contentType?.preferredMIMEType
        )
    }

    /// Builds media from Photos picker items in their original order.
    ///
    /// Items that cannot be loaded or decoded are skipped.
    func build(from items: [PhotosPickerItem]) async -> [ImageMedia] {
        var media: [ImageMedia] = []
        media.reserveCapacity(items.count)

        for item in items {
            guard let built = try? await build(from: item) else { continue }
            media.append(built)
        }

        return media
    }

    /// Builds JPEG media from a camera-captured image.
    ///
    /// - Throws: `CocoaError(.fileWriteUnknown)` when the image cannot be JPEG-encoded.
    func build(from image: UIImage) async throws -> ImageMedia {
        let encoded = try await Self.encode(capturedImage: image)
        return makeMedia(from: encoded, preferredFileExtension: "jpg", mimeType: "image/jpeg")
    }

    private func makeMedia(
        from encoded: EncodedImage,
        preferredFileExtension: String?,
        mimeType: String?
    ) -> ImageMedia {
        let assetID = UUID()
        let fileExtension = preferredFileExtension
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "jpg"
        let asset = MediaAsset(
            id: assetID,
            itemID: UUID(),
            kind: .photo,
            displayName: nil,
            sortOrder: 0,
            fileName: "photo-\(assetID.uuidString).\(fileExtension)",
            mimeType: mimeType ?? Self.mimeType(for: preferredFileExtension),
            byteSize: encoded.data.count,
            checksum: encoded.checksum,
            width: encoded.width,
            height: encoded.height,
            originalData: encoded.data
        )

        return ImageMedia(asset: asset, uiImage: encoded.image)
    }

    /// Decodes picked image data and hashes it off the main actor.
    @concurrent
    private static func encode(pickedData data: Data) async throws -> EncodedImage {
        guard let image = UIImage(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return EncodedImage(data: data, image: image)
    }

    /// JPEG-encodes a captured image and hashes it off the main actor.
    @concurrent
    private static func encode(capturedImage image: UIImage) async throws -> EncodedImage {
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw CocoaError(.fileWriteUnknown)
        }

        return EncodedImage(data: data, image: image)
    }

    private static func mimeType(for fileExtension: String?) -> String? {
        guard let fileExtension else { return nil }
        return UTType(filenameExtension: fileExtension)?.preferredMIMEType
    }
}

/// Encoded image bytes with the values derived from them off the main actor.
nonisolated private struct EncodedImage: Sendable {
    let data: Data
    let image: UIImage
    let checksum: String
    let width: Int
    let height: Int

    init(data: Data, image: UIImage) {
        self.data = data
        self.image = image
        self.checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        self.width = Int(image.size.width * image.scale)
        self.height = Int(image.size.height * image.scale)
    }
}
