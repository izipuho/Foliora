import CloudKit
import CoreData
import Foundation

@MainActor
final class CoreDataCatalogRepository: CatalogRepository {
    private let context: NSManagedObjectContext
    private let persistentContainer: NSPersistentCloudKitContainer?

    init(
        context: NSManagedObjectContext,
        persistentContainer: NSPersistentCloudKitContainer? = FolioraAppDelegate.coreDataContainer
    ) {
        self.context = context
        self.persistentContainer = persistentContainer
    }

    func saveHome(_ home: Home) {
        let entity = fetchEntity(named: "HomeEntity", by: home.id) ?? makeEntity(named: "HomeEntity")
        apply(home, to: entity)
        saveContext()
    }

    func saveLocations(_ locations: [Location], in homeID: UUID) {
        guard let home = fetchEntity(named: "HomeEntity", by: homeID) else { return }

        fetchEntities(named: "LocationEntity", predicate: NSPredicate(format: "home.id == %@", homeID as NSUUID))
            .forEach(context.delete)

        var entitiesByID: [UUID: NSManagedObject] = [:]

        for location in locations {
            let entity = makeEntity(named: "LocationEntity")
            apply(location, to: entity)
            entity.setValue(home, forKey: "home")
            entitiesByID[location.id] = entity
        }

        for location in locations {
            guard let entity = entitiesByID[location.id] else { continue }
            entity.setValue(location.parentLocationID.flatMap { entitiesByID[$0] }, forKey: "parent")
        }

        saveContext()
    }

    func deleteHome(homeID: UUID) {
        guard let entity = fetchEntity(named: "HomeEntity", by: homeID) else { return }
        context.delete(entity)
        saveContext()
    }

    func saveCollection(_ collection: Collection) {
        guard let home = fetchEntity(named: "HomeEntity", by: collection.homeID) else { return }

        let entity = fetchEntity(named: "CollectionEntity", by: collection.id) ?? makeEntity(named: "CollectionEntity")
        apply(collection, to: entity)
        entity.setValue(home, forKey: "home")
        saveContext()
    }

    func deleteResolution(for collectionID: UUID) -> CollectionDeleteResolution {
        guard
            let entity = fetchEntity(named: "CollectionEntity", by: collectionID),
            let share = share(for: entity)
        else {
            return .deletePrivateCollection
        }

        if share.currentUserParticipant?.role == .owner {
            return .deleteSharedCollectionAsOwner
        }

        return .leaveSharedCollectionAsParticipant
    }

    func deleteCollection(collectionID: UUID) {
        guard let entity = fetchEntity(named: "CollectionEntity", by: collectionID) else { return }

        switch deleteResolution(for: collectionID) {
        case .deletePrivateCollection, .deleteSharedCollectionAsOwner:
            context.delete(entity)
            saveContext()
        case .leaveSharedCollectionAsParticipant:
            leaveSharedCollection(entity)
        }
    }

    func saveBellRecord(_ bell: BellRecord) {
        guard let collection = fetchEntity(named: "CollectionEntity", by: bell.item.collectionID) else { return }

        let entity = fetchEntity(named: "BellEntity", by: bell.id) ?? makeEntity(named: "BellEntity")
        apply(bell, to: entity)
        entity.setValue(collection, forKey: "collection")
        entity.setValue(bell.item.locationID.flatMap { fetchEntity(named: "LocationEntity", by: $0) }, forKey: "location")
        entity.setValue(bell.originPlace.map(upsertPlace), forKey: "originPlace")
        replaceMediaAssets(bell.mediaAssets, for: entity)
        replaceTags(bell.tags, for: entity)
        saveContext()
    }

    func saveBellRecords(_ bells: [BellRecord]) {
        bells.forEach(saveBellRecord)
    }

    func deleteBellRecord(bellID: UUID) {
        guard let entity = fetchEntity(named: "BellEntity", by: bellID) else { return }
        context.delete(entity)
        saveContext()
    }

    private func apply(_ home: Home, to entity: NSManagedObject) {
        entity.setValue(home.id, forKey: "id")
        entity.setValue(home.name, forKey: "name")
        entity.setValue(home.iconName, forKey: "iconName")
        entity.setValue(home.notes, forKey: "notes")
    }

    private func apply(_ location: Location, to entity: NSManagedObject) {
        entity.setValue(location.id, forKey: "id")
        entity.setValue(location.kind.rawValue, forKey: "kindRaw")
        entity.setValue(location.name, forKey: "name")
        entity.setValue(location.notes, forKey: "notes")
    }

    private func apply(_ collection: Collection, to entity: NSManagedObject) {
        entity.setValue(collection.id, forKey: "id")
        entity.setValue(collection.kind.rawValue, forKey: "kindRaw")
        entity.setValue(collection.title, forKey: "title")
        entity.setValue(collection.notes, forKey: "notes")
        entity.setValue(collection.backgroundStyle.rawValue, forKey: "backgroundStyleRaw")
    }

    private func apply(_ bell: BellRecord, to entity: NSManagedObject) {
        entity.setValue(bell.id, forKey: "id")
        entity.setValue(bell.item.title, forKey: "title")
        entity.setValue(bell.item.notes, forKey: "notes")
        entity.setValue(bell.item.acquiredYear, forKey: "acquiredYear")
        entity.setValue(bell.item.createdAt, forKey: "createdAt")
        entity.setValue(bell.item.condition.rawValue, forKey: "conditionRaw")
        entity.setValue(bell.item.acquisitionMethod.rawValue, forKey: "acquisitionMethodRaw")
        entity.setValue(bell.details.material.rawValue, forKey: "materialRaw")
        entity.setValue(bell.details.customMaterialName, forKey: "customMaterialName")
        entity.setValue(bell.createdBy, forKey: "createdBy")
    }

    private func upsertPlace(_ place: Place) -> NSManagedObject {
        let entity = fetchEntity(named: "PlaceEntity", by: place.id) ?? makeEntity(named: "PlaceEntity")
        entity.setValue(place.id, forKey: "id")
        entity.setValue(place.displayName, forKey: "displayName")
        entity.setValue(place.countryCode, forKey: "countryCode")
        entity.setValue(place.countryName, forKey: "countryName")
        entity.setValue(place.regionName, forKey: "regionName")
        entity.setValue(place.cityName, forKey: "cityName")
        entity.setValue(place.latitude, forKey: "latitude")
        entity.setValue(place.longitude, forKey: "longitude")
        return entity
    }

    private func replaceTags(_ tags: [String], for bell: NSManagedObject) {
        let existingTags = (bell.value(forKey: "tags") as? Set<NSManagedObject>) ?? []
        existingTags.forEach(context.delete)

        let newTags = tags.enumerated().map { index, tag in
            let entity = makeEntity(named: "BellTagEntity")
            entity.setValue(UUID(), forKey: "id")
            entity.setValue(tag, forKey: "value")
            entity.setValue(index, forKey: "sortOrder")
            entity.setValue(bell, forKey: "bell")
            return entity
        }

        bell.setValue(Set(newTags), forKey: "tags")
    }

    private func replaceMediaAssets(_ mediaAssets: [MediaAsset], for bell: NSManagedObject) {
        let existingAssets = (bell.value(forKey: "mediaAssets") as? Set<NSManagedObject>) ?? []
        existingAssets.forEach(context.delete)

        let newAssets = mediaAssets.map { asset in
            let entity = makeEntity(named: "MediaAssetEntity")
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
            entity.setValue(asset.thumbnailData, forKey: "thumbnailData")
            entity.setValue(asset.originalData, forKey: "originalData")
            entity.setValue(bell, forKey: "bell")
            return entity
        }

        bell.setValue(Set(newAssets), forKey: "mediaAssets")
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
            homeID: (entity.value(forKey: "home") as? NSManagedObject).map { uuidValue($0, "id") } ?? UUID(),
            parentLocationID: (entity.value(forKey: "parent") as? NSManagedObject).map { uuidValue($0, "id") },
            kind: locationKind(from: stringValue(entity, "kindRaw", default: LocationKind.room.rawValue)),
            name: stringValue(entity, "name"),
            notes: stringValue(entity, "notes")
        )
    }

    private func collection(from entity: NSManagedObject) -> Collection {
        Collection(
            id: uuidValue(entity, "id"),
            homeID: (entity.value(forKey: "home") as? NSManagedObject).map { uuidValue($0, "id") } ?? UUID(),
            kind: collectionKind(from: stringValue(entity, "kindRaw", default: CollectionKind.bells.rawValue)),
            title: stringValue(entity, "title"),
            notes: stringValue(entity, "notes"),
            backgroundStyle: collectionBackgroundStyle(from: stringValue(entity, "backgroundStyleRaw", default: CollectionBackgroundStyle.amber.rawValue))
        )
    }

    private func bellRecord(from entity: NSManagedObject) -> BellRecord {
        let locationEntity = entity.value(forKey: "location") as? NSManagedObject
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
                acquiredYear: entity.value(forKey: "acquiredYear") as? Int,
                condition: itemCondition(from: stringValue(entity, "conditionRaw", default: ItemCondition.good.rawValue)),
                acquisitionMethod: acquisitionMethod(from: stringValue(entity, "acquisitionMethodRaw", default: AcquisitionMethod.bought.rawValue))
            ),
            details: BellDetails(
                itemID: uuidValue(entity, "id"),
                originPlaceID: originPlaceEntity.map { uuidValue($0, "id") },
                material: bellMaterial(from: stringValue(entity, "materialRaw", default: BellMaterial.unknown.rawValue)),
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

    private func place(from entity: NSManagedObject) -> Place {
        Place(
            id: uuidValue(entity, "id"),
            displayName: stringValue(entity, "displayName"),
            countryCode: stringValue(entity, "countryCode"),
            countryName: stringValue(entity, "countryName"),
            regionName: entity.value(forKey: "regionName") as? String,
            cityName: entity.value(forKey: "cityName") as? String,
            latitude: entity.value(forKey: "latitude") as? Double,
            longitude: entity.value(forKey: "longitude") as? Double
        )
    }

    private func mediaAsset(from entity: NSManagedObject, itemID: UUID) -> MediaAsset {
        MediaAsset(
            id: uuidValue(entity, "id"),
            itemID: itemID,
            kind: mediaKind(from: stringValue(entity, "kindRaw", default: MediaKind.photo.rawValue)),
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
            thumbnailData: entity.value(forKey: "thumbnailData") as? Data,
            originalData: entity.value(forKey: "originalData") as? Data
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

    private func makeEntity(named entityName: String) -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
    }

    private func fetchEntity(named entityName: String, by id: UUID) -> NSManagedObject? {
        fetchEntities(named: entityName, predicate: NSPredicate(format: "id == %@", id as NSUUID), fetchLimit: 1).first
    }

    private func share(for entity: NSManagedObject) -> CKShare? {
        try? persistentContainer?.fetchShares(matching: [entity.objectID])[entity.objectID]
    }

    private func leaveSharedCollection(_ entity: NSManagedObject) {
        guard
            let persistentContainer,
            let persistentStore = entity.objectID.persistentStore,
            let share = share(for: entity)
        else {
            return
        }

        persistentContainer.purgeObjectsAndRecordsInZone(
            with: share.recordID.zoneID,
            in: persistentStore
        ) { _, error in
            if let error {
                assertionFailure("Failed to leave shared collection: \(error)")
            }
        }
    }

    private func fetchEntities(
        named entityName: String,
        predicate: NSPredicate? = nil,
        fetchLimit: Int = 0
    ) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = predicate
        request.fetchLimit = fetchLimit
        return (try? context.fetch(request)) ?? []
    }

    private func uuidValue(_ entity: NSManagedObject, _ key: String) -> UUID {
        entity.value(forKey: key) as? UUID ?? UUID()
    }

    private func stringValue(_ entity: NSManagedObject, _ key: String, default defaultValue: String = "") -> String {
        entity.value(forKey: key) as? String ?? defaultValue
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

    private func locationKind(from rawValue: String) -> LocationKind {
        LocationKind(rawValue: rawValue) ?? .room
    }

    private func collectionKind(from rawValue: String) -> CollectionKind {
        CollectionKind(rawValue: rawValue) ?? .bells
    }

    private func collectionBackgroundStyle(from rawValue: String) -> CollectionBackgroundStyle {
        CollectionBackgroundStyle(rawValue: rawValue) ?? .amber
    }

    private func itemCondition(from rawValue: String) -> ItemCondition {
        ItemCondition(rawValue: rawValue) ?? .good
    }

    private func acquisitionMethod(from rawValue: String) -> AcquisitionMethod {
        AcquisitionMethod(rawValue: rawValue) ?? .other
    }

    private func bellMaterial(from rawValue: String) -> BellMaterial {
        BellMaterial(rawValue: rawValue) ?? .unknown
    }

    private func mediaKind(from rawValue: String) -> MediaKind {
        MediaKind(rawValue: rawValue) ?? .photo
    }

    private func saveContext() {
        guard context.hasChanges else { return }

        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save Core Data catalog context: \(error)")
        }
    }
}
