import ImageIO
import UIKit

@MainActor
protocol ItemCreationRecognitionController: AnyObject {
    init()
    var isAnalyzing: Bool { get }
    var requiresFullAnalysis: Bool { get }

    func configurePersistence(
        itemID: UUID,
        repository: any CatalogRepository,
        currentSnapshot: ItemRecognitionMediaSnapshot
    )
    func reconcileMediaSnapshot(_ snapshot: ItemRecognitionMediaSnapshot)
    func analyze(photos: [(assetID: UUID, image: UIImage)])
    func analyzeAddedPhoto(assetID: UUID, image: UIImage)
    func clear()
}

extension ItemCreationRecognitionController {
    func configureCreation(
        itemID: UUID,
        assets: [MediaAsset],
        repository: any CatalogRepository
    ) {
        let snapshot = ItemCreationService.recognitionSnapshot(from: assets)
        configurePersistence(
            itemID: itemID,
            repository: repository,
            currentSnapshot: snapshot
        )
    }

    @discardableResult
    func analyzeCreation(assets: [MediaAsset]) -> Bool {
        let photos = ItemCreationService.recognitionPhotos(from: assets)
        guard !photos.isEmpty else { return false }
        analyze(photos: photos)
        return true
    }

    func reconcileCreation(assets: [MediaAsset]) {
        reconcileMediaSnapshot(ItemCreationService.recognitionSnapshot(from: assets))
        if requiresFullAnalysis {
            _ = analyzeCreation(assets: assets)
        }
    }

    func analyzeAddedCreation(
        assetID: UUID,
        image: UIImage,
        assets: [MediaAsset]
    ) {
        if requiresFullAnalysis {
            _ = analyzeCreation(assets: assets)
        } else {
            analyzeAddedPhoto(assetID: assetID, image: image)
        }
    }

    func finishCreation(itemID: UUID) {
        guard !isAnalyzing else { return }
        clear()
        ItemRecognitionSessionStore.shared.discardSession(for: itemID)
    }

    static func startCreation(
        itemID: UUID,
        assets: [MediaAsset],
        repository: any CatalogRepository
    ) {
        let controller = ItemRecognitionSessionStore.shared.session(
            for: itemID,
            as: Self.self,
            create: { Self.init() }
        )
        controller.configureCreation(
            itemID: itemID,
            assets: assets,
            repository: repository
        )
        _ = controller.analyzeCreation(assets: assets)
    }
}

enum ItemCreationService {
    static func image(for asset: MediaAsset) -> UIImage? {
        guard let data = asset.originalData else { return nil }
        return UIImage(data: data)
    }

    /// Longest side of images handed to recognition; Vision does not need full camera resolution.
    static let recognitionMaxPixelSize = 2560

    static func recognitionPhotos(from assets: [MediaAsset]) -> [(assetID: UUID, image: UIImage)] {
        assets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { asset in
                recognitionImage(for: asset).map { (assetID: asset.id, image: $0) }
            }
    }

    /// Decodes a downsampled copy of the photo for recognition instead of the full-resolution bitmap.
    static func recognitionImage(for asset: MediaAsset) -> UIImage? {
        guard let data = asset.originalData,
              let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ) else {
            return nil
        }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: recognitionMaxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    static func recognitionSnapshot(from assets: [MediaAsset]) -> ItemRecognitionMediaSnapshot {
        ItemRecognitionMediaSnapshot(
            photoAssetIDs: Set(assets.filter { $0.kind == .photo }.map(\.id))
        )
    }
}
