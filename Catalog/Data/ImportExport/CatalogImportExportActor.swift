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
        try restoreMediaData(for: bundle, mediaStore: mediaStore)

        let missing = mediaIdentifiers(in: bundle).filter {
            mediaStore.fileURL(for: $0) == nil
        }
        return ImportResult(missingMediaIdentifiers: missing)
    }

    private func exportBundle(selection: CatalogExportSelection) throws -> CatalogTransferBundle {
        let homeEntities = try fetchEntities(named: "HomeEntity", sortKey: "name")
        let locationEntities = try fetchEntities(named: "LocationEntity", sortKey: "name")
        let collectionEntities = try fetchEntities(named: "CollectionEntity", sortKey: "title")
        let placeEntities = try fetchEntities(named: "PlaceEntity", sortKey: "displayName")
        let bellEntities = try fetchEntities(named: "BellEntity", sortDescriptors: [
            NSSortDescriptor(key: "createdAt", ascending: false)
        ])

        let exportedHomeEntities: [NSManagedObject]
        let exportedLocationEntities: [NSManagedObject]
        let exportedCollectionEntities: [NSManagedObject]
        let exportedPlaceEntities: [NSManagedObject]
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
                    guard let collection = $0.value(forKey: "collection") as? NSManagedObject else { return false }
                    return collectionIDs.contains(uuidValue(collection, "id"))
                }
                .map(bellRecord)

            let placeIDs = Set(exportedBellRecords.compactMap(\.details.originPlaceID))
            exportedPlaceEntities = placeEntities.filter {
                placeIDs.contains(uuidValue($0, "id"))
            }

        case .homes(let ids):
            exportedHomeEntities = homeEntities.filter {
                ids.contains(uuidValue($0, "id"))
            }
            let homeIDs = Set(exportedHomeEntities.map { uuidValue($0, "id") })

            exportedLocationEntities = locationEntities.filter {
                homeIDs.contains(locationHomeID(from: $0))
            }
            exportedCollectionEntities = []
            exportedPlaceEntities = []
            exportedBellRecords = []
        }

        let bellItems = exportedBellRecords.map { record in
            return BellTransferItem(
                item: record.item,
                details: record.details,
                mediaAssets: record.mediaAssets,
                createdBy: record.createdBy,
                tags: record.tags
            )
        }

        return CatalogTransferBundle(
            homes: exportedHomeEntities.map(home),
            locations: exportedLocationEntities.map(location),
            collections: exportedCollectionEntities.map(collection),
            places: exportedPlaceEntities.map(place),
            bellItems: bellItems
        )
    }

    private func replaceAllData(with bundle: CatalogTransferBundle) throws {
        try deleteExistingData()

        var homeEntities: [UUID: NSManagedObject] = [:]
        var locationEntities: [UUID: NSManagedObject] = [:]
        var collectionEntities: [UUID: NSManagedObject] = [:]
        var collectionLocationEntities: [UUID: [UUID: NSManagedObject]] = [:]
        var placeEntities: [UUID: NSManagedObject] = [:]

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

        for place in bundle.places {
            let entity = makeEntity(named: "PlaceEntity")
            entity.setValue(place.id, forKey: "id")
            entity.setValue(place.displayName, forKey: "displayName")
            entity.setValue(place.countryCode, forKey: "countryCode")
            entity.setValue(place.countryName, forKey: "countryName")
            entity.setValue(place.regionName, forKey: "regionName")
            entity.setValue(place.cityName, forKey: "cityName")
            entity.setValue(place.latitude, forKey: "latitude")
            entity.setValue(place.longitude, forKey: "longitude")
            placeEntities[place.id] = entity
        }

        var tagEntitiesByCollectionAndName: [UUID: [String: NSManagedObject]] = [:]

        for bell in bundle.bellItems {
            let entity = makeEntity(named: "BellEntity")
            entity.setValue(bell.item.id, forKey: "id")
            entity.setValue(bell.item.title, forKey: "title")
            entity.setValue(bell.item.notes, forKey: "notes")
            entity.setValue(bell.item.acquiredYear, forKey: "acquiredYear")
            entity.setValue(bell.item.createdAt, forKey: "createdAt")
            entity.setValue(bell.item.condition.rawValue, forKey: "conditionRaw")
            entity.setValue(bell.item.acquisitionMethod.rawValue, forKey: "acquisitionMethodRaw")
            entity.setValue(bell.details.material.rawValue, forKey: "materialRaw")
            entity.setValue(bell.details.customMaterialName, forKey: "customMaterialName")
            entity.setValue(bell.createdBy, forKey: "createdBy")
            entity.setValue(collectionEntities[bell.item.collectionID], forKey: "collection")
            entity.setValue(bell.item.locationID.flatMap { collectionLocationEntities[bell.item.collectionID]?[$0] }, forKey: "collectionLocation")
            entity.setValue(bell.item.locationID.flatMap { locationEntities[$0] }, forKey: "location")
            entity.setValue(bell.details.originPlaceID.flatMap { placeEntities[$0] }, forKey: "originPlace")

            let mediaEntities = bell.mediaAssets.map { asset in
                let mediaEntity = makeEntity(named: "MediaAssetEntity")
                mediaEntity.setValue(asset.id, forKey: "id")
                mediaEntity.setValue(asset.kind.rawValue, forKey: "kindRaw")
                mediaEntity.setValue(asset.localIdentifier, forKey: "localIdentifier")
                mediaEntity.setValue(asset.displayName, forKey: "displayName")
                mediaEntity.setValue(asset.sortOrder, forKey: "sortOrder")
                mediaEntity.setValue(asset.fileName, forKey: "fileName")
                mediaEntity.setValue(asset.mimeType, forKey: "mimeType")
                mediaEntity.setValue(asset.byteSize, forKey: "byteSize")
                mediaEntity.setValue(asset.checksum, forKey: "checksum")
                mediaEntity.setValue(asset.width, forKey: "width")
                mediaEntity.setValue(asset.height, forKey: "height")
                mediaEntity.setValue(asset.duration, forKey: "duration")
                mediaEntity.setValue(asset.metadataJSON, forKey: "metadataJSON")
                mediaEntity.setValue(nil, forKey: "thumbnailData")
                mediaEntity.setValue(nil, forKey: "originalData")
                mediaEntity.setValue(entity, forKey: "bell")
                return mediaEntity
            }
            entity.setValue(Set(mediaEntities), forKey: "mediaAssets")

            var seenNormalizedNames = Set<String>()
            let tagEntities = bell.tags.enumerated().compactMap { index, tag -> NSManagedObject? in
                guard let collectionEntity = collectionEntities[bell.item.collectionID] else { return nil }

                let normalizedName = normalizedTagName(tag)
                guard !normalizedName.isEmpty, seenNormalizedNames.insert(normalizedName).inserted else { return nil }

                let existingTagEntity = tagEntitiesByCollectionAndName[bell.item.collectionID]?[normalizedName]
                let tagEntity = existingTagEntity ?? makeEntity(named: "BellTagEntity")
                if tagEntity.value(forKey: "id") == nil {
                    tagEntity.setValue(UUID(), forKey: "id")
                }
                tagEntity.setValue(normalizedName, forKey: "normalizedName")
                tagEntity.setValue(tag, forKey: "value")
                tagEntity.setValue(index, forKey: "sortOrder")
                tagEntity.setValue(collectionEntity, forKey: "collection")
                tagEntitiesByCollectionAndName[bell.item.collectionID, default: [:]][normalizedName] = tagEntity
                return tagEntity
            }
            entity.setValue(Set(tagEntities), forKey: "tags")
        }

        try context.save()
    }

    private func mediaIdentifiers(in bundle: CatalogTransferBundle) -> [String] {
        let identifiers = bundle.bellItems
            .flatMap(\.mediaAssets)
            .map(\.localIdentifier)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(identifiers)).sorted()
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

    private func location(from entity: NSManagedObject) -> Location {
        Location(
            id: uuidValue(entity, "id"),
            homeID: locationHomeID(from: entity),
            parentLocationID: (entity.value(forKey: "parent") as? NSManagedObject).map { uuidValue($0, "id") },
            kind: LocationKind(rawValue: stringValue(entity, "kindRaw", default: LocationKind.room.rawValue)) ?? .room,
            name: stringValue(entity, "name"),
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

    private func place(from entity: NSManagedObject) -> Place {
        Place(
            id: uuidValue(entity, "id"),
            displayName: stringValue(entity, "displayName"),
            countryCode: stringValue(entity, "countryCode"),
            countryName: stringValue(entity, "countryName"),
            regionName: entity.value(forKey: "regionName") as? String,
            cityName: entity.value(forKey: "cityName") as? String,
            latitude: optionalDoubleValue(entity, "latitude"),
            longitude: optionalDoubleValue(entity, "longitude")
        )
    }

    private func bellRecord(from entity: NSManagedObject) -> BellRecord {
        let locationEntity = (entity.value(forKey: "collectionLocation") as? NSManagedObject)
            ?? entity.value(forKey: "location") as? NSManagedObject
        let originPlaceEntity = entity.value(forKey: "originPlace") as? NSManagedObject
        let tags = ((entity.value(forKey: "tags") as? Set<NSManagedObject>) ?? [])
            .sorted { intValue($0, "sortOrder") < intValue($1, "sortOrder") }
            .map { stringValue($0, "value") }
        let mediaAssets = ((entity.value(forKey: "mediaAssets") as? Set<NSManagedObject>) ?? [])
            .sorted { intValue($0, "sortOrder") < intValue($1, "sortOrder") }
            .map { mediaAsset(from: $0, itemID: uuidValue(entity, "id")) }

        return BellRecord(
            item: Item(
                id: uuidValue(entity, "id"),
                collectionID: (entity.value(forKey: "collection") as? NSManagedObject).map { uuidValue($0, "id") } ?? UUID(),
                locationID: locationEntity.map { uuidValue($0, "id") },
                createdAt: dateValue(entity, "createdAt"),
                title: stringValue(entity, "title"),
                notes: stringValue(entity, "notes"),
                acquiredYear: optionalIntValue(entity, "acquiredYear"),
                condition: ItemCondition(rawValue: stringValue(entity, "conditionRaw", default: ItemCondition.good.rawValue)) ?? .good,
                acquisitionMethod: AcquisitionMethod(
                    rawValue: stringValue(entity, "acquisitionMethodRaw", default: AcquisitionMethod.bought.rawValue)
                ) ?? .other
            ),
            details: BellDetails(
                itemID: uuidValue(entity, "id"),
                originPlaceID: originPlaceEntity.map { uuidValue($0, "id") },
                material: BellMaterial(rawValue: stringValue(entity, "materialRaw", default: BellMaterial.unknown.rawValue)) ?? .unknown,
                customMaterialName: entity.value(forKey: "customMaterialName") as? String
            ),
            originPlace: originPlaceEntity.map(place),
            storageLocation: locationEntity.map(location),
            storagePath: locationEntity.map(storagePath) ?? "",
            mediaAssets: mediaAssets,
            createdBy: stringValue(entity, "createdBy"),
            tags: tags
        )
    }

    private func mediaAsset(from entity: NSManagedObject, itemID: UUID) -> MediaAsset {
        MediaAsset(
            id: uuidValue(entity, "id"),
            itemID: itemID,
            kind: MediaKind(rawValue: stringValue(entity, "kindRaw", default: MediaKind.photo.rawValue)) ?? .photo,
            localIdentifier: stringValue(entity, "localIdentifier"),
            displayName: entity.value(forKey: "displayName") as? String,
            sortOrder: intValue(entity, "sortOrder"),
            fileName: entity.value(forKey: "fileName") as? String,
            mimeType: entity.value(forKey: "mimeType") as? String,
            byteSize: optionalIntValue(entity, "byteSize"),
            checksum: entity.value(forKey: "checksum") as? String,
            width: optionalIntValue(entity, "width"),
            height: optionalIntValue(entity, "height"),
            duration: optionalDoubleValue(entity, "duration"),
            metadataJSON: entity.value(forKey: "metadataJSON") as? String,
            thumbnailData: nil,
            originalData: nil
        )
    }

    private func storagePath(from entity: NSManagedObject) -> String {
        var parts: [String] = []
        var current: NSManagedObject? = entity

        while let location = current {
            parts.insert(stringValue(location, "name"), at: 0)
            current = location.value(forKey: "parent") as? NSManagedObject
        }

        return parts.joined(separator: " / ")
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

    private func intValue(_ entity: NSManagedObject, _ key: String) -> Int {
        optionalIntValue(entity, key) ?? 0
    }

    private func optionalIntValue(_ entity: NSManagedObject, _ key: String) -> Int? {
        if let value = entity.value(forKey: key) as? Int {
            return value
        }

        return (entity.value(forKey: key) as? NSNumber)?.intValue
    }

    private func optionalDoubleValue(_ entity: NSManagedObject, _ key: String) -> Double? {
        if let value = entity.value(forKey: key) as? Double {
            return value
        }

        return (entity.value(forKey: key) as? NSNumber)?.doubleValue
    }

    private func dateValue(_ entity: NSManagedObject, _ key: String) -> Date {
        entity.value(forKey: key) as? Date ?? Date()
    }
}
