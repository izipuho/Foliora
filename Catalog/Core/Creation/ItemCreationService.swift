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

extension BellPhotoAnalysisController: ItemCreationRecognitionController {}
extension BookPhotoAnalysisController: ItemCreationRecognitionController {}

enum ItemCreationService {
    struct PreparedBookMedia {
        let coverImage: MediaAsset?
        let mediaAssets: [MediaAsset]
        let didFailToExtractCover: Bool
    }

    struct NormalizedBookPhoto {
        let asset: MediaAsset?
        let analysisImage: UIImage
    }

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

    @MainActor
    static func prepareBookMedia(
        _ assets: [MediaAsset],
        itemID: UUID
    ) async -> PreparedBookMedia {
        let photos = assets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard let coverID = photos.first?.id else {
            return PreparedBookMedia(
                coverImage: nil,
                mediaAssets: assets.map { $0.with(itemID: itemID) },
                didFailToExtractCover: false
            )
        }

        var coverImage: MediaAsset?
        var mediaAssets = assets
        var didFailToExtractCover = false

        for source in photos {
            guard let sourceImage = image(for: source) else { continue }

            let isCover = source.id == coverID
            let normalized = await normalizeBookPhoto(
                sourceImage,
                sourceAsset: source,
                itemID: itemID,
                asCover: isCover
            )

            guard let asset = normalized.asset else {
                didFailToExtractCover = didFailToExtractCover || isCover
                continue
            }

            if isCover {
                coverImage = asset
                mediaAssets.removeAll { $0.id == source.id }
            } else if let index = mediaAssets.firstIndex(where: { $0.id == source.id }) {
                mediaAssets[index] = asset
            }
        }

        mediaAssets = mediaAssets
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { $0.element.with(itemID: itemID, sortOrder: $0.offset) }

        return PreparedBookMedia(
            coverImage: coverImage,
            mediaAssets: mediaAssets,
            didFailToExtractCover: didFailToExtractCover
        )
    }

    @MainActor
    static func normalizeBookPhoto(
        _ image: UIImage,
        sourceAsset: MediaAsset,
        itemID: UUID,
        asCover: Bool
    ) async -> NormalizedBookPhoto {
        guard let extracted = await BookCoverExtractor().extractCover(from: image) else {
            return NormalizedBookPhoto(asset: nil, analysisImage: image)
        }

        if !sourceAsset.localIdentifier.isEmpty {
            LocalMediaFileStore.shared.deleteFile(for: sourceAsset.localIdentifier)
        }

        let analysisImage = extracted.originalData.flatMap(UIImage.init(data:)) ?? image
        if asCover {
            return NormalizedBookPhoto(
                asset: extracted.with(
                    itemID: itemID,
                    displayName: String(localized: "editor.media.cover"),
                    sortOrder: 0
                ),
                analysisImage: analysisImage
            )
        }

        let asset = sourceAsset.with(
            itemID: sourceAsset.itemID ?? itemID,
            localIdentifier: ""
        ) { copy in
            copy.fileName = extracted.fileName
            copy.mimeType = extracted.mimeType
            copy.byteSize = extracted.byteSize
            copy.checksum = extracted.checksum
            copy.width = extracted.width
            copy.height = extracted.height
            copy.duration = extracted.duration
            copy.metadataJSON = extracted.metadataJSON
            copy.originalData = extracted.originalData
        }

        return NormalizedBookPhoto(asset: asset, analysisImage: analysisImage)
    }
}
