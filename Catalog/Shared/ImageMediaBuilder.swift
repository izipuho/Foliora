import CollectionDomain
import Foundation
import UIKit

struct ImageMedia {
    let asset: MediaAsset
    let uiImage: UIImage
}

struct ImageMediaBuilder {
    let store: LocalMediaFileStore

    func build(from image: UIImage) async throws -> ImageMedia {
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let identifier = try store.savePhoto(data: data, preferredFileExtension: "jpg")
        let asset = MediaAsset(
            id: UUID(),
            itemID: UUID(),
            kind: .photo,
            localIdentifier: identifier,
            displayName: nil,
            sortOrder: 0
        )

        return ImageMedia(asset: asset, uiImage: image)
    }
}
