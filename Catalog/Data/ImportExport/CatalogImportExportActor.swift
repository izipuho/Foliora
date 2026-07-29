import CoreData
import Foundation

enum CatalogExportSelection {
    case collections(Set<UUID>)
    case homes(Set<UUID>)
}

@MainActor
final class CatalogImportExportActor {
    struct ImportResult: Sendable {
        var missingMediaIdentifiers: [String] = []
    }

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func exportArchiveData(selection: CatalogExportSelection) throws -> Data {
        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("catalog-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: workDirectory) }

        let mediaDirectory = workDirectory.appendingPathComponent("Media", isDirectory: true)
        try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)

        let bundle = try exportBundle(selection: selection)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(jsonBundle(from: bundle)).write(
            to: workDirectory.appendingPathComponent("catalog.json"),
            options: .atomic
        )

        for asset in mediaAssets(in: bundle) {
            let identifier = asset.localIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty, let originalData = asset.originalData else { continue }
            try originalData.write(to: mediaDirectory.appendingPathComponent(identifier), options: .atomic)
        }

        let archiveURL = fileManager.temporaryDirectory
            .appendingPathComponent("catalog-export-\(UUID().uuidString).zip")
        defer { try? fileManager.removeItem(at: archiveURL) }

        try CatalogArchiveService().createArchive(from: workDirectory, to: archiveURL)
        return try Data(contentsOf: archiveURL)
    }

    @discardableResult
    func importArchive(
        from archiveURL: URL,
        selectedCollectionIDs: Set<UUID>
    ) throws -> ImportResult {
        guard !selectedCollectionIDs.isEmpty else {
            throw ImportError.emptySelection
        }

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
        let filteredBundle = filteredBundle(from: bundle, selectedCollectionIDs: selectedCollectionIDs)
        try mergeData(from: filteredBundle)

        let mediaStore = LocalMediaFileStore.shared
        let mediaDirectory = workDirectory.appendingPathComponent("Media", isDirectory: true)
        for identifier in mediaIdentifiers(in: filteredBundle) {
            let sourceURL = mediaDirectory.appendingPathComponent(identifier)
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            try mediaStore.restoreFile(from: sourceURL, identifier: identifier)
        }
        try restoreMediaData(for: filteredBundle, mediaStore: mediaStore)

        let missing = mediaIdentifiers(in: filteredBundle).filter {
            mediaStore.fileURL(for: $0) == nil
        }
        return ImportResult(missingMediaIdentifiers: missing)
    }

    private enum ImportError: LocalizedError {
        case emptySelection

        var errorDescription: String? {
            switch self {
            case .emptySelection:
                return "Select at least one collection to import."
            }
        }
    }

    private func exportBundle(selection: CatalogExportSelection) throws -> CatalogTransferBundle {
        let homeEntities = try fetchEntities(named: "HomeEntity", sortKey: "name")
        let locationEntities = try fetchEntities(named: "LocationEntity", sortKey: "name")
        let collectionEntities = try fetchEntities(named: "CollectionEntity", sortKey: "title")
        let bellEntities = try fetchEntities(named: "BellEntity", sortDescriptors: [
            NSSortDescriptor(key: "item.createdAt", ascending: false)
        ])

        let exportedHomeEntities: [NSManagedObject]
        let exportedLocationEntities: [NSManagedObject]
        let exportedCollectionEntities: [NSManagedObject]
        let exportedBellRecords: [BellRecord]

        switch selection {
        case .collections(let ids):
            exportedCollectionEntities = collectionEntities.filter {
                ids.contains(uuidValue($0, "id"))
            }
            let collectionIDs = Set(exportedCollectionEntities.map { uuidValue($0, "id") })
            let homeIDs = Set(exportedCollectionEntities.map(collectionHomeID))

            exportedHomeEntities = homeEntities.filter {
                homeIDs.contains(uuidValue($0, "id"))
            }
            exportedLocationEntities = locationEntities.filter {
                homeIDs.contains(locationHomeID(from: $0))
            }
            exportedBellRecords = bellEntities
                .filter {
                    guard
                        let item = $0.value(forKey: "item") as? NSManagedObject,
                        let collection = item.value(forKey: "collection") as? NSManagedObject
                    else { return false }
                    return collectionIDs.contains(uuidValue(collection, "id"))
                }
                .map(CoreDataDomainMapper.bellRecord)

        case .homes(let ids):
            exportedHomeEntities = homeEntities.filter {
                ids.contains(uuidValue($0, "id"))
            }
            let homeIDs = Set(exportedHomeEntities.map { uuidValue($0, "id") })

            exportedLocationEntities = locationEntities.filter {
                homeIDs.contains(locationHomeID(from: $0))
            }
            exportedCollectionEntities = []
            exportedBellRecords = []
        }

        let bellItems = exportedBellRecords.map { record in
            return BellTransferItem(
                item: record.item,
                details: record.details,
                originPlace: record.originPlace.flatMap(OriginPlaceTransferValue.init),
                mediaAssets: record.mediaAssets,
                createdBy: record.createdBy,
                tags: record.tags
            )
        }

        return CatalogTransferBundle(
            homes: exportedHomeEntities.map(home),
            locations: exportedLocationEntities.map(CoreDataDomainMapper.location),
            collections: exportedCollectionEntities.map(collection),
            places: [],
            bellItems: bellItems
        )
    }

    private func filteredBundle(
        from bundle: CatalogTransferBundle,
        selectedCollectionIDs: Set<UUID>
    ) -> CatalogTransferBundle {
        let collections = bundle.collections.filter {
            selectedCollectionIDs.contains($0.id)
        }
        let collectionIDs = Set(collections.map(\.id))
        let homeIDs = Set(collections.map(\.homeID))
        let bellItems = bundle.bellItems.filter {
            collectionIDs.contains($0.item.collectionID)
        }

        var copy = bundle
        copy.homes = bundle.homes.filter { homeIDs.contains($0.id) }
        copy.locations = bundle.locations.filter { homeIDs.contains($0.homeID) }
        copy.collections = collections
        copy.bellItems = bellItems
        return copy
    }

    private func replaceAllData(with bundle: CatalogTransferBundle) throws {
        try deleteExistingData()

        var homeEntities: [UUID: NSManagedObject] = [:]
        var locationEntities: [UUID: NSManagedObject] = [:]
        var collectionEntities: [UUID: NSManagedObject] = [:]
        var collectionLocationEntities: [UUID: [UUID: NSManagedObject]] = [:]

        for home in bundle.homes {
            let entity = makeEntity(named: "HomeEntity")
            entity.setValue(home.id, forKey: "id")
            entity.setValue(home.name, forKey: "name")
            entity.setValue(home.iconName, forKey: "iconName")
            entity.setValue(home.notes, forKey: "notes")
            homeEntities[home.id] = entity
        }

        for location in bundle.locations {
            let entity = makeEntity(named: "LocationEntity")
            entity.setValue(location.id, forKey: "id")
            entity.setValue(location.kind.rawValue, forKey: "kindRaw")
            entity.setValue(location.name, forKey: "name")
            entity.setValue(location.notes, forKey: "notes")
            entity.setValue(homeEntities[location.homeID], forKey: "home")
            locationEntities[location.id] = entity
        }

        for location in bundle.locations {
            guard let entity = locationEntities[location.id] else { continue }
            entity.setValue(location.parentLocationID.flatMap { locationEntities[$0] }, forKey: "parent")
        }

        for collection in bundle.collections {
            let entity = makeEntity(named: "CollectionEntity")
            entity.setValue(collection.id, forKey: "id")
            entity.setValue(collection.kind.rawValue, forKey: "kindRaw")
            entity.setValue(collection.title, forKey: "title")
            entity.setValue(collection.notes, forKey: "notes")
            entity.setValue(collection.backgroundStyle.rawValue, forKey: "backgroundStyleRaw")
            if let home = homeEntities[collection.homeID] {
                entity.setValue(home, forKey: "home")
                entity.setValue(home.value(forKey: "id"), forKey: "homeID")
                entity.setValue(home.value(forKey: "name"), forKey: "homeName")
                entity.setValue(home.value(forKey: "iconName"), forKey: "homeIconName")
            }
            collectionEntities[collection.id] = entity
        }

        for collection in bundle.collections {
            guard let collectionEntity = collectionEntities[collection.id] else { continue }
            let collectionLocations = bundle.locations.filter { $0.homeID == collection.homeID }

            for (sortOrder, location) in collectionLocations.enumerated() {
                let entity = makeEntity(named: "CollectionLocationEntity")
                entity.setValue(location.id, forKey: "id")
                entity.setValue(location.id, forKey: "sourceLocationID")
                entity.setValue(location.kind.rawValue, forKey: "kindRaw")
                entity.setValue(location.name, forKey: "name")
                entity.setValue(location.notes, forKey: "notes")
                entity.setValue(sortOrder, forKey: "sortOrder")
                entity.setValue(false, forKey: "isArchived")
                entity.setValue(collectionEntity, forKey: "collection")
                collectionLocationEntities[collection.id, default: [:]][location.id] = entity
            }

            for location in collectionLocations {
                guard let entity = collectionLocationEntities[collection.id]?[location.id] else { continue }
                entity.setValue(location.parentLocationID.flatMap { collectionLocationEntities[collection.id]?[$0] }, forKey: "parent")
            }
        }

        var placeEntitiesByOriginPlace: [OriginPlaceTransferValue: NSManagedObject] = [:]

        for originPlace in bundle.bellItems.compactMap(\.originPlace) {
            guard placeEntitiesByOriginPlace[originPlace] == nil else { continue }

            let entity = makeEntity(named: "PlaceEntity")
            entity.setValue(UUID(), forKey: "id")
            entity.setValue(originPlace.displayName, forKey: "displayName")
            entity.setValue(originPlace.latitude, forKey: "latitude")
            entity.setValue(originPlace.longitude, forKey: "longitude")
            placeEntitiesByOriginPlace[originPlace] = entity
        }

        var tagEntitiesByCollectionAndName: [UUID: [String: NSManagedObject]] = [:]

        for bell in bundle.bellItems {
            let itemEntity = makeEntity(named: "ItemEntity")
            updateItemEntity(
                itemEntity,
                with: bell,
                collection: collectionEntities[bell.item.collectionID],
                collectionLocation: bell.item.locationID.flatMap { collectionLocationEntities[bell.item.collectionID]?[$0] },
                location: bell.item.locationID.flatMap { locationEntities[$0] },
                originPlace: bell.originPlace.flatMap { placeEntitiesByOriginPlace[$0] }
            )

            let bellEntity = makeEntity(named: "BellEntity")
            updateBellEntity(bellEntity, with: bell)
            bellEntity.setValue(itemEntity, forKey: "item")

            let mediaEntities = bell.mediaAssets.map { asset in
                let mediaEntity = makeEntity(named: "MediaAssetEntity")
                updateMediaEntity(mediaEntity, with: asset, item: itemEntity)
                return mediaEntity
            }
            itemEntity.setValue(Set(mediaEntities), forKey: "mediaAssets")

            var seenNormalizedNames = Set<String>()
            let tagEntities = bell.tags.enumerated().compactMap { index, tag -> NSManagedObject? in
                guard let collectionEntity = collectionEntities[bell.item.collectionID] else { return nil }

                let normalizedName = normalizedTagName(tag)
                guard !normalizedName.isEmpty, seenNormalizedNames.insert(normalizedName).inserted else { return nil }

                let existingTagEntity = tagEntitiesByCollectionAndName[bell.item.collectionID]?[normalizedName]
                let tagEntity = existingTagEntity ?? makeEntity(named: "ItemTagEntity")
                updateItemTagEntity(tagEntity, value: tag, normalizedName: normalizedName, sortOrder: index, collection: collectionEntity)
                tagEntitiesByCollectionAndName[bell.item.collectionID, default: [:]][normalizedName] = tagEntity
                return tagEntity
            }
            itemEntity.setValue(Set(tagEntities), forKey: "tags")
        }

        try context.save()
    }

    func mergeData(from bundle: CatalogTransferBundle) throws {
        var homeEntitiesByName = indexed(try fetchEntities(named: "HomeEntity", sortKey: "name")) {
            normalizedName(stringValue($0, "name"))
        }
        var homeEntities: [UUID: NSManagedObject] = [:]
        for home in bundle.homes {
            let key = normalizedName(home.name)
            let entity = homeEntitiesByName[key] ?? makeEntity(named: "HomeEntity")
            ensureID(entity)
            entity.setValue(home.name, forKey: "name")
            entity.setValue(home.iconName, forKey: "iconName")
            entity.setValue(home.notes, forKey: "notes")
            homeEntitiesByName[key] = entity
            homeEntities[home.id] = entity
        }

        var locationEntitiesByKey = indexed(try fetchEntities(named: "LocationEntity", sortKey: "name")) {
            locationKey(for: $0)
        }
        var locationEntities: [UUID: NSManagedObject] = [:]
        for location in bundle.locations {
            guard let homeEntity = homeEntities[location.homeID] else { continue }
            let key = locationKey(for: location, localHomeID: uuidValue(homeEntity, "id"))
            let entity = locationEntitiesByKey[key] ?? makeEntity(named: "LocationEntity")
            ensureID(entity)
            entity.setValue(location.kind.rawValue, forKey: "kindRaw")
            entity.setValue(location.name, forKey: "name")
            entity.setValue(location.notes, forKey: "notes")
            entity.setValue(homeEntity, forKey: "home")
            locationEntitiesByKey[key] = entity
            locationEntities[location.id] = entity
        }

        for location in bundle.locations {
            guard let entity = locationEntities[location.id] else { continue }
            if let parentPath = location.fullPath?.dropLast(), !parentPath.isEmpty {
                let localHomeID = (entity.value(forKey: "home") as? NSManagedObject).map { uuidValue($0, "id") } ?? UUID()
                let parentKey = locationKey(
                    homeID: localHomeID,
                    kindRaw: parentPath.last?.kind.rawValue ?? LocationKind.room.rawValue,
                    path: parentPath.map(locationPathComponentKey)
                )
                entity.setValue(locationEntitiesByKey[parentKey], forKey: "parent")
            } else {
                entity.setValue(location.parentLocationID.flatMap { locationEntities[$0] }, forKey: "parent")
            }
        }

        var collectionEntitiesByKey = indexed(try fetchEntities(named: "CollectionEntity", sortKey: "title")) {
            collectionKey(
                homeID: collectionHomeID(from: $0),
                kindRaw: stringValue($0, "kindRaw", default: CollectionKind.bells.rawValue),
                title: stringValue($0, "title")
            )
        }
        var collectionEntities: [UUID: NSManagedObject] = [:]
        for collection in bundle.collections {
            guard let homeEntity = homeEntities[collection.homeID] else { continue }
            let key = collectionKey(
                homeID: uuidValue(homeEntity, "id"),
                kindRaw: collection.kind.rawValue,
                title: collection.title
            )
            let entity = collectionEntitiesByKey[key] ?? makeEntity(named: "CollectionEntity")
            ensureID(entity)
            entity.setValue(collection.kind.rawValue, forKey: "kindRaw")
            entity.setValue(collection.title, forKey: "title")
            entity.setValue(collection.notes, forKey: "notes")
            entity.setValue(collection.backgroundStyle.rawValue, forKey: "backgroundStyleRaw")
            entity.setValue(homeEntity, forKey: "home")
            entity.setValue(homeEntity.value(forKey: "id"), forKey: "homeID")
            entity.setValue(homeEntity.value(forKey: "name"), forKey: "homeName")
            entity.setValue(homeEntity.value(forKey: "iconName"), forKey: "homeIconName")
            collectionEntitiesByKey[key] = entity
            collectionEntities[collection.id] = entity
        }

        var collectionLocationEntitiesByKey: [CollectionLocationKey: NSManagedObject] = indexed(try fetchEntities(named: "CollectionLocationEntity")) { entity in
            guard
                let collection = entity.value(forKey: "collection") as? NSManagedObject,
                let sourceLocationID = entity.value(forKey: "sourceLocationID") as? UUID
            else { return nil }
            return CollectionLocationKey(collectionID: uuidValue(collection, "id"), sourceLocationID: sourceLocationID)
        }
        var collectionLocationEntities: [UUID: [UUID: NSManagedObject]] = [:]
        for collection in bundle.collections {
            guard let collectionEntity = collectionEntities[collection.id] else { continue }
            let collectionLocations = bundle.locations.filter { $0.homeID == collection.homeID }

            for (sortOrder, location) in collectionLocations.enumerated() {
                guard let sourceLocation = locationEntities[location.id] else { continue }
                let localLocationID = uuidValue(sourceLocation, "id")
                let key = CollectionLocationKey(collectionID: uuidValue(collectionEntity, "id"), sourceLocationID: localLocationID)
                let entity = collectionLocationEntitiesByKey[key] ?? makeEntity(named: "CollectionLocationEntity")
                ensureID(entity)
                entity.setValue(localLocationID, forKey: "sourceLocationID")
                entity.setValue(location.kind.rawValue, forKey: "kindRaw")
                entity.setValue(location.name, forKey: "name")
                entity.setValue(location.notes, forKey: "notes")
                entity.setValue(sortOrder, forKey: "sortOrder")
                entity.setValue(false, forKey: "isArchived")
                entity.setValue(collectionEntity, forKey: "collection")
                collectionLocationEntitiesByKey[key] = entity
                collectionLocationEntities[collection.id, default: [:]][location.id] = entity
            }

            for location in collectionLocations {
                guard let entity = collectionLocationEntities[collection.id]?[location.id] else { continue }
                entity.setValue(location.parentLocationID.flatMap { collectionLocationEntities[collection.id]?[$0] }, forKey: "parent")
            }
        }

        var placeEntitiesByCoordinate: [PlaceKey: NSManagedObject] = indexed(try fetchEntities(named: "PlaceEntity")) { entity in
            guard
                let latitude = optionalDoubleValue(entity, "latitude"),
                let longitude = optionalDoubleValue(entity, "longitude")
            else { return nil }
            return PlaceKey(latitude: latitude, longitude: longitude)
        }

        for originPlace in bundle.bellItems.compactMap(\.originPlace) {
            let key = PlaceKey(latitude: originPlace.latitude, longitude: originPlace.longitude)
            guard placeEntitiesByCoordinate[key] == nil else { continue }

            let entity = makeEntity(named: "PlaceEntity")
            ensureID(entity)
            entity.setValue(originPlace.displayName, forKey: "displayName")
            entity.setValue(originPlace.latitude, forKey: "latitude")
            entity.setValue(originPlace.longitude, forKey: "longitude")
            placeEntitiesByCoordinate[key] = entity
        }

        var tagEntitiesByCollectionAndName: [UUID: [String: NSManagedObject]] = [:]
        for entity in try fetchEntities(named: "ItemTagEntity") {
            guard let collection = entity.value(forKey: "collection") as? NSManagedObject else { continue }
            let normalizedName = stringValue(entity, "normalizedName", default: normalizedTagName(stringValue(entity, "value")))
            tagEntitiesByCollectionAndName[uuidValue(collection, "id"), default: [:]][normalizedName] = entity
        }

        var itemEntitiesByCollectionAndID: [UUID: [UUID: NSManagedObject]] = [:]
        for entity in try fetchEntities(named: "ItemEntity") {
            guard let collection = entity.value(forKey: "collection") as? NSManagedObject else { continue }
            itemEntitiesByCollectionAndID[uuidValue(collection, "id"), default: [:]][uuidValue(entity, "id")] = entity
        }

        for bell in bundle.bellItems {
            guard let collectionEntity = collectionEntities[bell.item.collectionID] else { continue }
            let localCollectionID = uuidValue(collectionEntity, "id")
            let originPlace = bell.originPlace.flatMap {
                placeEntitiesByCoordinate[PlaceKey(latitude: $0.latitude, longitude: $0.longitude)]
            }
            let itemEntity = itemEntitiesByCollectionAndID[localCollectionID]?[bell.item.id] ?? makeEntity(named: "ItemEntity")
            updateItemEntity(
                itemEntity,
                with: bell,
                collection: collectionEntity,
                collectionLocation: bell.item.locationID.flatMap { collectionLocationEntities[bell.item.collectionID]?[$0] },
                location: bell.item.locationID.flatMap { locationEntities[$0] },
                originPlace: originPlace
            )
            itemEntitiesByCollectionAndID[localCollectionID, default: [:]][bell.item.id] = itemEntity

            let bellEntity = (itemEntity.value(forKey: "bell") as? NSManagedObject)
                ?? fetchBellEntity(for: itemEntity)
                ?? makeEntity(named: "BellEntity")
            updateBellEntity(bellEntity, with: bell)
            bellEntity.setValue(itemEntity, forKey: "item")

            var mediaEntitiesByID = indexed((itemEntity.value(forKey: "mediaAssets") as? Set<NSManagedObject>) ?? []) {
                uuidValue($0, "id")
            }
            for asset in bell.mediaAssets {
                let mediaEntity = mediaEntitiesByID[asset.id] ?? makeEntity(named: "MediaAssetEntity")
                updateMediaEntity(mediaEntity, with: asset, item: itemEntity)
                mediaEntitiesByID[asset.id] = mediaEntity
            }
            itemEntity.setValue(Set(mediaEntitiesByID.values), forKey: "mediaAssets")

            var seenNormalizedNames = Set<String>()
            let tagEntities = bell.tags.enumerated().compactMap { index, tag -> NSManagedObject? in
                let normalizedName = normalizedTagName(tag)
                guard !normalizedName.isEmpty, seenNormalizedNames.insert(normalizedName).inserted else { return nil }

                let existingTagEntity = tagEntitiesByCollectionAndName[localCollectionID]?[normalizedName]
                let tagEntity = existingTagEntity ?? makeEntity(named: "ItemTagEntity")
                updateItemTagEntity(tagEntity, value: tag, normalizedName: normalizedName, sortOrder: index, collection: collectionEntity)
                tagEntitiesByCollectionAndName[localCollectionID, default: [:]][normalizedName] = tagEntity
                return tagEntity
            }
            itemEntity.setValue(Set(tagEntities), forKey: "tags")
        }

        try context.save()
    }

    private func mediaIdentifiers(in bundle: CatalogTransferBundle) -> [String] {
        let identifiers = mediaAssets(in: bundle)
            .map(\.localIdentifier)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(identifiers)).sorted()
    }

    private func mediaAssets(in bundle: CatalogTransferBundle) -> [MediaAsset] {
        var seenIdentifiers = Set<String>()
        return bundle.bellItems
            .flatMap(\.mediaAssets)
            .filter { asset in
                let identifier = asset.localIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                return !identifier.isEmpty && seenIdentifiers.insert(identifier).inserted
            }
    }

    private func jsonBundle(from bundle: CatalogTransferBundle) -> CatalogTransferBundle {
        var copy = bundle
        copy.bellItems = copy.bellItems.map { bell in
            var bell = bell
            bell.mediaAssets = bell.mediaAssets.map { asset in
                asset.with { asset in
                    asset.thumbnailData = nil
                    asset.originalData = nil
                }
            }
            return bell
        }
        return copy
    }

    private func restoreMediaData(
        for bundle: CatalogTransferBundle,
        mediaStore: LocalMediaFileStore
    ) throws {
        let identifiers = mediaIdentifiers(in: bundle)
        guard !identifiers.isEmpty else { return }

        let request = NSFetchRequest<NSManagedObject>(entityName: "MediaAssetEntity")
        request.predicate = NSPredicate(format: "localIdentifier IN %@", identifiers)
        let mediaEntities = try context.fetch(request)

        for entity in mediaEntities {
            let identifier = stringValue(entity, "localIdentifier")
            guard let fileURL = mediaStore.fileURL(for: identifier) else { continue }

            entity.setValue(try Data(contentsOf: fileURL), forKey: "originalData")
            if let thumbnailURL = mediaStore.thumbnailFileURL(for: identifier) {
                entity.setValue(try Data(contentsOf: thumbnailURL), forKey: "thumbnailData")
            }
        }

        if context.hasChanges {
            try context.save()
        }
    }

    private func deleteExistingData() throws {
        try deleteEntities(named: "MediaAssetEntity")
        try deleteEntities(named: "BellTagEntity")
        try deleteEntities(named: "BellEntity")
        try deleteEntities(named: "ItemTagEntity")
        try deleteEntities(named: "ItemEntity")
        try deleteEntities(named: "CollectionLocationEntity")
        try deleteEntities(named: "CollectionEntity")
        try deleteEntities(named: "LocationEntity")
        try deleteEntities(named: "PlaceEntity")
        try deleteEntities(named: "HomeEntity")
        try context.save()
    }

    private func makeEntity(named entityName: String) -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
    }

    private func fetchEntities(
        named entityName: String,
        sortKey: String? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil
    ) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        if let sortDescriptors {
            request.sortDescriptors = sortDescriptors
        } else if let sortKey {
            request.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: true)]
        }
        return try context.fetch(request)
    }

    private func deleteEntities(named entityName: String) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        try context.fetch(request).forEach(context.delete)
    }

    private func home(from entity: NSManagedObject) -> Home {
        Home(
            id: uuidValue(entity, "id"),
            name: stringValue(entity, "name"),
            iconName: stringValue(entity, "iconName", default: "house.fill"),
            notes: stringValue(entity, "notes")
        )
    }

    private func collection(from entity: NSManagedObject) -> Collection {
        Collection(
            id: uuidValue(entity, "id"),
            homeID: collectionHomeID(from: entity),
            kind: CollectionKind(rawValue: stringValue(entity, "kindRaw", default: CollectionKind.bells.rawValue)) ?? .bells,
            title: stringValue(entity, "title"),
            notes: stringValue(entity, "notes"),
            backgroundStyle: CollectionBackgroundStyle(
                rawValue: stringValue(entity, "backgroundStyleRaw", default: CollectionBackgroundStyle.amber.rawValue)
            ) ?? .amber
        )
    }

    private func collectionHomeID(from entity: NSManagedObject) -> UUID {
        (entity.value(forKey: "home") as? NSManagedObject).map { uuidValue($0, "id") }
            ?? entity.value(forKey: "homeID") as? UUID
            ?? UUID()
    }

    private func locationHomeID(from entity: NSManagedObject) -> UUID {
        if entity.entity.name == "LocationEntity",
           let home = entity.value(forKey: "home") as? NSManagedObject {
            return uuidValue(home, "id")
        }

        if entity.entity.name == "CollectionLocationEntity",
           let collection = entity.value(forKey: "collection") as? NSManagedObject {
            return collectionHomeID(from: collection)
        }

        return UUID()
    }

    private struct LocationKey: Hashable {
        var homeID: UUID
        var kindRaw: String
        var path: [LocationPathComponentKey]
    }

    private struct LocationPathComponentKey: Hashable {
        var kindRaw: String
        var name: String
    }

    private struct CollectionKey: Hashable {
        var homeID: UUID
        var kindRaw: String
        var title: String
    }

    private struct CollectionLocationKey: Hashable {
        var collectionID: UUID
        var sourceLocationID: UUID
    }

    private struct PlaceKey: Hashable {
        var latitude: Double
        var longitude: Double
    }

    private func locationKey(for entity: NSManagedObject) -> LocationKey? {
        guard let home = entity.value(forKey: "home") as? NSManagedObject else { return nil }
        return LocationKey(
            homeID: uuidValue(home, "id"),
            kindRaw: stringValue(entity, "kindRaw", default: LocationKind.room.rawValue),
            path: locationPathComponentKeys(for: entity)
        )
    }

    private func locationKey(for location: LocationTransferRecord, localHomeID: UUID) -> LocationKey {
        let path = location.fullPath ?? [StoragePath.Component(kind: location.kind, name: location.name)]
        return LocationKey(
            homeID: localHomeID,
            kindRaw: location.kind.rawValue,
            path: path.map(locationPathComponentKey)
        )
    }

    private func locationKey(
        homeID: UUID,
        kindRaw: String,
        path: [LocationPathComponentKey]
    ) -> LocationKey {
        LocationKey(homeID: homeID, kindRaw: kindRaw, path: path)
    }

    private func locationPathComponentKeys(for entity: NSManagedObject) -> [LocationPathComponentKey] {
        var path: [LocationPathComponentKey] = []
        var current: NSManagedObject? = entity
        var visitedObjectIDs = Set<NSManagedObjectID>()

        while let location = current, visitedObjectIDs.insert(location.objectID).inserted {
            path.insert(
                locationPathComponentKey(
                    kindRaw: stringValue(location, "kindRaw", default: LocationKind.room.rawValue),
                    name: stringValue(location, "name")
                ),
                at: 0
            )
            current = location.value(forKey: "parent") as? NSManagedObject
        }

        return path
    }

    private func locationPathComponentKey(for component: StoragePath.Component) -> LocationPathComponentKey {
        locationPathComponentKey(kindRaw: component.kind.rawValue, name: component.name)
    }

    private func locationPathComponentKey(kindRaw: String, name: String) -> LocationPathComponentKey {
        LocationPathComponentKey(kindRaw: kindRaw, name: normalizedName(name))
    }

    private func collectionKey(homeID: UUID, kindRaw: String, title: String) -> CollectionKey {
        CollectionKey(homeID: homeID, kindRaw: kindRaw, title: normalizedName(title))
    }

    private func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func indexed<Key: Hashable, Entities: Sequence>(
        _ entities: Entities,
        _ key: (NSManagedObject) -> Key?
    ) -> [Key: NSManagedObject] where Entities.Element == NSManagedObject {
        entities.reduce(into: [:]) { result, entity in key(entity).map { result[$0] = entity } }
    }

    private func ensureID(_ entity: NSManagedObject) {
        if entity.value(forKey: "id") == nil {
            entity.setValue(UUID(), forKey: "id")
        }
    }

    private func updateItemEntity(
        _ entity: NSManagedObject,
        with bell: BellTransferItem,
        collection: NSManagedObject?,
        collectionLocation: NSManagedObject?,
        location: NSManagedObject?,
        originPlace: NSManagedObject?
    ) {
        entity.setValue(bell.item.id, forKey: "id")
        entity.setValue(bell.item.title, forKey: "title")
        entity.setValue(bell.item.notes, forKey: "notes")
        entity.setValue(bell.item.acquiredYear, forKey: "acquisitionYear")
        entity.setValue(bell.item.createdAt, forKey: "createdAt")
        entity.setValue(bell.item.createdBy, forKey: "createdBy")
        entity.setValue(bell.item.condition.rawValue, forKey: "condition")
        entity.setValue(bell.item.acquisitionMethod.rawValue, forKey: "acquisitionMethod")
        entity.setValue(bell.item.isFavorite, forKey: "isFavorite")
        entity.setValue(collection, forKey: "collection")
        entity.setValue(collectionLocation, forKey: "collectionLocation")
        entity.setValue(location, forKey: "location")
        entity.setValue(originPlace, forKey: "originPlace")
    }

    private func updateBellEntity(_ entity: NSManagedObject, with bell: BellTransferItem) {
        entity.setValue(bell.details.material.rawValue, forKey: "materialRaw")
        entity.setValue(bell.details.customMaterialName, forKey: "customMaterialName")
    }

    private func updateMediaEntity(
        _ entity: NSManagedObject,
        with asset: MediaAsset,
        item: NSManagedObject
    ) {
        entity.setValue(asset.id, forKey: "id")
        entity.setValue(asset.kind.rawValue, forKey: "kindRaw")
        entity.setValue(asset.localIdentifier, forKey: "localIdentifier")
        entity.setValue(asset.displayName, forKey: "displayName")
        entity.setValue(asset.sortOrder, forKey: "sortOrder")
        entity.setValue(asset.fileName, forKey: "fileName")
        entity.setValue(asset.mimeType, forKey: "mimeType")
        entity.setValue(asset.byteSize, forKey: "byteSize")
        entity.setValue(asset.checksum, forKey: "checksum")
        entity.setValue(asset.width, forKey: "width")
        entity.setValue(asset.height, forKey: "height")
        entity.setValue(asset.duration, forKey: "duration")
        entity.setValue(asset.metadataJSON, forKey: "metadataJSON")
        entity.setValue(nil, forKey: "thumbnailData")
        entity.setValue(nil, forKey: "originalData")
        if entity.entity.attributesByName["itemID"] != nil {
            entity.setValue(item.value(forKey: "id"), forKey: "itemID")
        }
        entity.setValue(item, forKey: "item")
    }

    private func updateItemTagEntity(
        _ entity: NSManagedObject,
        value: String,
        normalizedName: String,
        sortOrder: Int,
        collection: NSManagedObject
    ) {
        ensureID(entity)
        entity.setValue(normalizedName, forKey: "normalizedName")
        entity.setValue(value, forKey: "value")
        entity.setValue(sortOrder, forKey: "sortOrder")
        entity.setValue(collection, forKey: "collection")
    }

    private func fetchBellEntity(for item: NSManagedObject) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "BellEntity")
        request.predicate = NSPredicate(format: "item == %@", item)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private func uuidValue(_ entity: NSManagedObject, _ key: String) -> UUID {
        entity.value(forKey: key) as? UUID ?? UUID()
    }

    private func stringValue(_ entity: NSManagedObject, _ key: String, default defaultValue: String = "") -> String {
        entity.value(forKey: key) as? String ?? defaultValue
    }

    private func normalizedTagName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func optionalDoubleValue(_ entity: NSManagedObject, _ key: String) -> Double? {
        if let value = entity.value(forKey: key) as? Double {
            return value
        }

        return (entity.value(forKey: key) as? NSNumber)?.doubleValue
    }
}
