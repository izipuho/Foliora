import CoreData
import Foundation
import SwiftUI

/// Loads stored media bytes by asset ID on a background context.
///
/// `CatalogSnapshot` maps media without `originalData`, so list models never fault in photo bytes.
/// Views and item screens that need the bytes load them here, off the main actor.
nonisolated final class MediaDataLoader: @unchecked Sendable {
    private let context: NSManagedObjectContext

    init(container: NSPersistentContainer) {
        context = container.newBackgroundContext()
    }

    /// Loads the stored bytes of the media asset with the given ID.
    func data(forAssetID assetID: UUID) async -> Data? {
        await context.perform { [context] in
            let request = NSFetchRequest<NSManagedObject>(entityName: "MediaAssetEntity")
            request.predicate = NSPredicate(format: "id == %@", assetID as CVarArg)
            request.fetchLimit = 1

            guard let entity = try? context.fetch(request).first else { return nil }
            let data = entity.value(forKey: "originalData") as? Data
            // Drop the row cache so the loader does not keep every loaded photo alive.
            context.refresh(entity, mergeChanges: false)
            return data
        }
    }
}

extension MediaDataLoader {
    /// Returns the bytes held by the asset, or loads the stored bytes when the asset has none.
    ///
    /// Assets that were added but not saved yet carry their bytes in memory and are not in the store,
    /// so in-memory data always wins.
    @MainActor
    func data(for asset: MediaAsset) async -> Data? {
        if let originalData = asset.originalData {
            return originalData
        }
        return await data(forAssetID: asset.id)
    }

    /// Returns the assets with stored bytes filled in where they are missing.
    @MainActor
    func hydrated(_ assets: [MediaAsset]) async -> [MediaAsset] {
        var result: [MediaAsset] = []
        result.reserveCapacity(assets.count)

        for asset in assets {
            guard asset.originalData == nil else {
                result.append(asset)
                continue
            }

            var hydratedAsset = asset
            hydratedAsset.originalData = await data(forAssetID: asset.id)
            result.append(hydratedAsset)
        }

        return result
    }

    /// Copies bytes from `previous` into assets that are unchanged (same ID and checksum).
    ///
    /// Item screens re-read their record from each new snapshot; reusing bytes they already hold
    /// keeps media visible while `hydrated(_:)` loads only what is new.
    @MainActor
    static func reusingData(_ assets: [MediaAsset], from previous: [MediaAsset]) -> [MediaAsset] {
        let previousByID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return assets.map { asset in
            guard asset.originalData == nil,
                  let previousAsset = previousByID[asset.id],
                  previousAsset.checksum == asset.checksum,
                  let originalData = previousAsset.originalData else {
                return asset
            }

            var reusedAsset = asset
            reusedAsset.originalData = originalData
            return reusedAsset
        }
    }
}

extension EnvironmentValues {
    /// Loader for media bytes that snapshot records do not carry. `nil` outside the app shell.
    @Entry var mediaDataLoader: MediaDataLoader? = nil
}
