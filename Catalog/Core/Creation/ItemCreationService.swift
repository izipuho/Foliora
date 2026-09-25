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
            create: Self.init
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
        if let data = asset.originalData,
           let image = UIImage(data: data) {
            return image
        }

        guard !asset.localIdentifier.isEmpty,
              let url = LocalMediaFileStore.shared.fileURL(for: asset.localIdentifier) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }

    static func recognitionPhotos(from assets: [MediaAsset]) -> [(assetID: UUID, image: UIImage)] {
        assets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { asset in
                image(for: asset).map { (assetID: asset.id, image: $0) }
            }
    }

    static func recognitionSnapshot(from assets: [MediaAsset]) -> ItemRecognitionMediaSnapshot {
        ItemRecognitionMediaSnapshot(
            photoAssetIDs: Set(assets.filter { $0.kind == .photo }.map(\.id))
        )
    }
}
