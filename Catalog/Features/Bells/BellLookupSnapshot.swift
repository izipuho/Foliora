import CoreData
import Foundation

/// Represents bell lookup snapshot data and behavior.
struct BellLookupSnapshot {
    var bells: [BellRecord] = []
    var locations: [Location] = []
    var collections: [Collection] = []
    var homes: [Home] = []
    var places: [Place] = []
    var locationPathByID: [UUID: String] = [:]

    init() {}
}

/// Defines the interface for bell lookup snapshot loading implementations.
protocol BellLookupSnapshotLoading {
    func loadSnapshot(collectionID: UUID?, homeID: UUID?) -> BellLookupSnapshot
    func loadBell(id: UUID) -> BellRecord?
}

/// Provides core data bell lookup snapshot loader operations.
struct CoreDataBellLookupSnapshotLoader: BellLookupSnapshotLoading {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func loadSnapshot(collectionID: UUID? = nil, homeID: UUID? = nil) -> BellLookupSnapshot {
        let bellEntities = fetchEntities(
            named: "BellEntity",
            predicate: collectionID.map { NSPredicate(format: "collection.id == %@", $0 as NSUUID) },
            sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)]
        )
        let collectionEntities = fetchEntities(
            named: "CollectionEntity",
            predicate: collectionID.map { NSPredicate(format: "id == %@", $0 as NSUUID) },
            sortDescriptors: [NSSortDescriptor(key: "title", ascending: true)]
        )
        var locationEntities = collectionID.map {
            fetchEntities(
                named: "CollectionLocationEntity",
                predicate: NSPredicate(format: "collection.id == %@", $0 as NSUUID),
                sortDescriptors: [NSSortDescriptor(key: "sortOrder", ascending: true)]
            )
        } ?? []
        if collectionID == nil || locationEntities.isEmpty {
            let resolvedHomeID = collectionEntities.first.map(collectionHomeID) ?? homeID
            locationEntities = fetchEntities(
                named: "LocationEntity",
                predicate: resolvedHomeID.map { NSPredicate(format: "home.id == %@", $0 as NSUUID) },
                sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
            )
        }
        let homeEntities = fetchEntities(
            named: "HomeEntity",
            predicate: homeID.map { NSPredicate(format: "id == %@", $0 as NSUUID) },
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )
        let placeEntities = fetchEntities(
            named: "PlaceEntity",
            sortDescriptors: [NSSortDescriptor(key: "displayName", ascending: true)]
        )

        let bells = bellEntities.map { CoreDataDomainMapper.bellRecord(from: $0) }
        let locations = locationEntities.map { CoreDataDomainMapper.location(from: $0) }

        var snapshot = BellLookupSnapshot()
        snapshot.bells = bells
        snapshot.locations = locations
        snapshot.collections = collectionEntities.map(collection)
        snapshot.homes = homeEntities.map(home)
        snapshot.places = placeEntities.map { CoreDataDomainMapper.place(from: $0) }
        snapshot.locationPathByID = Dictionary(
            uniqueKeysWithValues: locationEntities.map { (uuidValue($0, "id"), locationPath(from: $0)) }
        )
        return snapshot
    }

    func loadBell(id: UUID) -> BellRecord? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "BellEntity")
        request.predicate = NSPredicate(format: "item.id == %@", id as NSUUID)
        request.fetchLimit = 1

        guard let entity = try? context.fetch(request).first else {
            return nil
        }

        return CoreDataDomainMapper.bellRecord(from: entity)
    }

    private func fetchEntities(
        named entityName: String,
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor] = []
    ) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        return (try? context.fetch(request)) ?? []
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
            kind: collectionKind(from: stringValue(entity, "kindRaw", default: CollectionKind.bells.rawValue)),
            title: stringValue(entity, "title"),
            notes: stringValue(entity, "notes"),
            backgroundStyle: collectionBackgroundStyle(from: stringValue(entity, "backgroundStyleRaw", default: CollectionBackgroundStyle.amber.rawValue))
        )
    }

    private func locationPath(from entity: NSManagedObject) -> String {
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

    private func collectionHomeID(from entity: NSManagedObject) -> UUID {
        (entity.value(forKey: "home") as? NSManagedObject).map { uuidValue($0, "id") }
            ?? entity.value(forKey: "homeID") as? UUID
            ?? UUID()
    }

    private func stringValue(_ entity: NSManagedObject, _ key: String, default defaultValue: String = "") -> String {
        entity.value(forKey: key) as? String ?? defaultValue
    }

    private func collectionKind(from rawValue: String) -> CollectionKind {
        CollectionKind(rawValue: rawValue) ?? .bells
    }

    private func collectionBackgroundStyle(from rawValue: String) -> CollectionBackgroundStyle {
        CollectionBackgroundStyle(rawValue: rawValue) ?? .amber
    }
}
