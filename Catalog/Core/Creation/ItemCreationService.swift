import UIKit

@MainActor
protocol ItemCreationRecognitionController: AnyObject {
    init()
    var isAnalyzing: Bool { get }
    func configurePersistence(
        itemID: UUID,
        repository: any CatalogRepository,
        currentSnapshot: ItemRecognitionMediaSnapshot
    )
    func analyze(photos: [(assetID: UUID, image: UIImage)])
    func clear()
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

    @MainActor
    static func configureRecognition<Controller: ItemCreationRecognitionController>(
        itemID: UUID,
        assets: [MediaAsset],
        repository: any CatalogRepository,
        controller: Controller
    ) {
        controller.configurePersistence(
            itemID: itemID,
            repository: repository,
            currentSnapshot: recognitionSnapshot(from: assets)
        )
    }

    @MainActor
    static func startRecognition<Controller: ItemCreationRecognitionController>(
        itemID: UUID,
        assets: [MediaAsset],
        repository: any CatalogRepository,
        as type: Controller.Type
    ) {
        let photos = recognitionPhotos(from: assets)
        guard !photos.isEmpty else { return }

        let controller = ItemRecognitionSessionStore.shared.session(
            for: itemID,
            as: type,
            create: Controller.init
        )
        configureRecognition(
            itemID: itemID,
            assets: assets,
            repository: repository,
            controller: controller
        )
        controller.analyze(photos: photos)
    }

    @MainActor
    static func finishEditorSave<Controller: ItemCreationRecognitionController>(
        itemID: UUID,
        controller: Controller
    ) {
        guard !controller.isAnalyzing else { return }
        controller.clear()
        ItemRecognitionSessionStore.shared.discardSession(for: itemID)
    }


}
