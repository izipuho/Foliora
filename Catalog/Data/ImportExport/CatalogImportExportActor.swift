import Foundation
import SwiftData

@ModelActor
actor CatalogImportExportActor {
    struct ImportResult: Sendable {
        var missingMediaIdentifiers: [String] = []
    }

    func exportArchiveData() throws -> Data {
        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("catalog-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: workDirectory) }

        let mediaDirectory = workDirectory.appendingPathComponent("Media", isDirectory: true)
        try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)

        let bundle = try exportBundle()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(bundle).write(to: workDirectory.appendingPathComponent("catalog.json"), options: .atomic)

        let mediaStore = LocalMediaFileStore.shared
        for identifier in mediaIdentifiers(in: bundle) {
            guard let sourceURL = mediaStore.exportFileURL(for: identifier) else { continue }
            try fileManager.copyItem(
                at: sourceURL,
                to: mediaDirectory.appendingPathComponent(identifier)
            )
        }

        let archiveURL = fileManager.temporaryDirectory
            .appendingPathComponent("catalog-export-\(UUID().uuidString).zip")
        defer { try? fileManager.removeItem(at: archiveURL) }

        try CatalogArchiveService().createArchive(from: workDirectory, to: archiveURL)
        return try Data(contentsOf: archiveURL)
    }

    @discardableResult
    func importArchive(from archiveURL: URL) throws -> ImportResult {
        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("catalog-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: workDirectory) }

        try CatalogArchiveService().extractArchive(at: archiveURL, to: workDirectory)

        let catalogURL = workDirectory.appendingPathComponent("catalog.json")
        guard fileManager.fileExists(atPath: catalogURL.path) else {
            throw CatalogArchiveService.ArchiveError.missingCatalogJSON
        }

        let data = try Data(contentsOf: catalogURL)
        let decoder = JSONDecoder()
        let bundle = try decoder.decode(CatalogTransferBundle.self, from: data)
        try replaceAllData(with: bundle)

        let mediaStore = LocalMediaFileStore.shared
        let mediaDirectory = workDirectory.appendingPathComponent("Media", isDirectory: true)
        for identifier in mediaIdentifiers(in: bundle) {
            let sourceURL = mediaDirectory.appendingPathComponent(identifier)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            try mediaStore.restoreFile(from: sourceURL, identifier: identifier)
        }

        let missing = mediaIdentifiers(in: bundle).filter {
            mediaStore.fileURL(for: $0) == nil
        }
        return ImportResult(missingMediaIdentifiers: missing)
    }

    private func exportBundle() throws -> CatalogTransferBundle {
        let homeEntities = try modelContext.fetch(FetchDescriptor<HomeEntity>(sortBy: [SortDescriptor(\.name)]))
        let locationEntities = try modelContext.fetch(FetchDescriptor<LocationEntity>(sortBy: [SortDescriptor(\.name)]))
        let collectionEntities = try modelContext.fetch(FetchDescriptor<CollectionEntity>(sortBy: [SortDescriptor(\.title)]))
        let membershipEntities = try modelContext.fetch(FetchDescriptor<MembershipEntity>())
        let placeEntities = try modelContext.fetch(FetchDescriptor<PlaceEntity>(sortBy: [SortDescriptor(\.displayName)]))
        let bellEntities = try modelContext.fetch(BellEntity.allDescriptor())

        let bellItems = bellEntities.map { bell in
            let record = bell.recordSnapshot
            return BellTransferItem(
                item: record.item,
                details: record.details,
                mediaAssets: record.mediaAssets,
                createdBy: record.createdBy,
                tags: record.tags
            )
        }

        return CatalogTransferBundle(
            homes: homeEntities.map(\.homeSnapshot),
            locations: locationEntities.map(\.locationSnapshot),
            collections: collectionEntities.map(\.collectionSnapshot),
            memberships: membershipEntities.map(\.membershipSnapshot),
            places: placeEntities.map(\.placeSnapshot),
            bellItems: bellItems,
            userDirectory: defaultUserDirectory
        )
    }

    private func replaceAllData(with bundle: CatalogTransferBundle) throws {
        try deleteExistingData()

        var homeEntities: [UUID: HomeEntity] = [:]
        var locationEntities: [UUID: LocationEntity] = [:]
        var collectionEntities: [UUID: CollectionEntity] = [:]
        var placeEntities: [UUID: PlaceEntity] = [:]

        for home in bundle.homes {
            let entity = HomeEntity(id: home.id, name: home.name, iconName: home.iconName, notes: home.notes)
            modelContext.insert(entity)
            homeEntities[home.id] = entity
        }

        for location in bundle.locations {
            let entity = LocationEntity(
                id: location.id,
                kindRaw: location.kind.rawValue,
                name: location.name,
                notes: location.notes
            )
            entity.home = homeEntities[location.homeID]
            modelContext.insert(entity)
            locationEntities[location.id] = entity
        }

        for location in bundle.locations {
            guard let entity = locationEntities[location.id] else { continue }
            entity.parent = location.parentLocationID.flatMap { locationEntities[$0] }
        }

        for collection in bundle.collections {
            let entity = CollectionEntity(
                id: collection.id,
                kindRaw: collection.kind.rawValue,
                title: collection.title,
                notes: collection.notes,
                backgroundStyleRaw: collection.backgroundStyle.rawValue
            )
            entity.home = homeEntities[collection.homeID]
            modelContext.insert(entity)
            collectionEntities[collection.id] = entity
        }

        for membership in bundle.memberships {
            let entity = MembershipEntity(
                id: membership.id,
                userID: membership.userID,
                roleRaw: membership.role.rawValue,
                statusRaw: membership.status.rawValue
            )
            entity.collection = collectionEntities[membership.collectionID]
            modelContext.insert(entity)
        }

        for place in bundle.places {
            let entity = PlaceEntity(
                id: place.id,
                displayName: place.displayName,
                countryCode: place.countryCode,
                countryName: place.countryName,
                regionName: place.regionName,
                cityName: place.cityName,
                latitude: place.latitude,
                longitude: place.longitude
            )
            modelContext.insert(entity)
            placeEntities[place.id] = entity
        }

        for bell in bundle.bellItems {
            let entity = BellEntity(
                id: bell.item.id,
                title: bell.item.title,
                notes: bell.item.notes,
                acquiredYear: bell.item.acquiredYear,
                createdAt: bell.item.createdAt,
                conditionRaw: bell.item.condition.rawValue,
                acquisitionMethodRaw: bell.item.acquisitionMethod.rawValue,
                materialRaw: bell.details.material.rawValue,
                customMaterialName: bell.details.customMaterialName,
                createdBy: bell.createdBy
            )
            entity.collection = collectionEntities[bell.item.collectionID]
            entity.location = bell.item.locationID.flatMap { locationEntities[$0] }
            entity.originPlace = bell.details.originPlaceID.flatMap { placeEntities[$0] }
            modelContext.insert(entity)

            let mediaEntities = bell.mediaAssets.map { asset in
                MediaAssetEntity(
                    id: asset.id,
                    kindRaw: asset.kind.rawValue,
                    localIdentifier: asset.localIdentifier,
                    displayName: asset.displayName,
                    sortOrder: asset.sortOrder
                )
            }
            mediaEntities.forEach { $0.bell = entity }
            mediaEntities.forEach(modelContext.insert)
            entity.mediaAssets = mediaEntities

            let tagEntities = bell.tags.enumerated().map { index, tag in
                BellTagEntity(value: tag, sortOrder: index)
            }
            tagEntities.forEach { $0.bell = entity }
            tagEntities.forEach(modelContext.insert)
            entity.tags = tagEntities
        }

        try modelContext.save()
    }

    private func mediaIdentifiers(in bundle: CatalogTransferBundle) -> [String] {
        let identifiers = bundle.bellItems
            .flatMap(\.mediaAssets)
            .map(\.localIdentifier)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(identifiers)).sorted()
    }

    private func deleteExistingData() throws {
        try modelContext.fetch(FetchDescriptor<MediaAssetEntity>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<BellTagEntity>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<BellEntity>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<MembershipEntity>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<CollectionEntity>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<LocationEntity>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<PlaceEntity>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<HomeEntity>()).forEach(modelContext.delete)
        try modelContext.save()
    }

    private var defaultUserDirectory: [String: String] {
        [
            "me": "Вы",
            "marina": "Марина",
            "alexey": "Алексей",
            "nina": "Нина"
        ]
    }
}
