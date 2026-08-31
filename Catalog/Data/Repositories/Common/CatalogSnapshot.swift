import CoreData
import Foundation

/// Represents catalog snapshot data and behavior.
struct CatalogSnapshot {
    private(set) var homes: [Home] = []
    private(set) var locations: [Location] = []
    private(set) var collectionLocations: [Location] = []
    private(set) var collections: [Collection] = []
    private(set) var places: [Place] = []
    private(set) var collectionEntities: [NSManagedObject] = []
    private(set) var itemEntities: [NSManagedObject] = []
    private(set) var publisherEntities: [NSManagedObject] = []
    private(set) var personEntities: [NSManagedObject] = []
    private(set) var locationsByHomeID: [UUID: [Location]] = [:]
    private(set) var collectionLocationsByCollectionID: [UUID: [Location]] = [:]
    private(set) var collectionCountsByHomeID: [UUID: Int] = [:]
    private(set) var itemCountsByCollectionID: [UUID: Int] = [:]
    private(set) var locationPathByID: [UUID: String] = [:]
    private(set) var collectionLocationPathByCollectionID: [UUID: [UUID: String]] = [:]

    private init() {}

    func collectionSummary(id collectionID: UUID) -> CollectionSummary? {
        guard let collection = collections.first(where: { $0.id == collectionID }) else { return nil }
        return collectionSummary(from: collection)
    }

    nonisolated static func load(from context: NSManagedObjectContext) -> CatalogSnapshot {
        let homeEntities = fetchEntities(
            named: "HomeEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )
        let locationEntities = fetchEntities(
            named: "LocationEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )
        let collectionLocationEntities = fetchEntities(
            named: "CollectionLocationEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "sortOrder", ascending: true)]
        )
        let collectionEntities = fetchEntities(
            named: "CollectionEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "title", ascending: true)]
        )
        let itemEntities = fetchEntities(
            named: "ItemEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)]
        )
        let placeEntities = fetchEntities(
            named: "PlaceEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "displayName", ascending: true)]
        )
        let publisherEntities = fetchEntities(
            named: "PublisherEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )
        let personEntities = fetchEntities(
            named: "PersonEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )
        let privateStore = context.persistentStoreCoordinator?.persistentStores.first {
            $0.url?.lastPathComponent == "Private.sqlite"
        }
        let userSortOrderEntities = privateStore.map {
            fetchEntities(named: "UserSortOrderEntity", in: context, affectedStores: [$0])
        } ?? []
        let sortOrderByItemID = Dictionary(
            userSortOrderEntities.compactMap { entity -> (UUID, Int)? in
                guard let itemID = entity.value(forKey: "itemID") as? UUID else { return nil }
                return (itemID, CoreDataDomainMapper.intValue(entity, "sortOrder"))
            },
            uniquingKeysWith: { _, latest in latest }
        )
        let collectionSortOrderByItemID = Dictionary(
            userSortOrderEntities.compactMap { entity -> (UUID, Int)? in
                guard
                    stringValue(entity, "scope") == "Collection",
                    let itemID = entity.value(forKey: "itemID") as? UUID
                else { return nil }
                return (itemID, CoreDataDomainMapper.intValue(entity, "sortOrder"))
            },
            uniquingKeysWith: { _, latest in latest }
        )
        let homeSortOrderByItemID = Dictionary(
            userSortOrderEntities.compactMap { entity -> (UUID, Int)? in
                guard
                    stringValue(entity, "scope") == "Home",
                    let itemID = entity.value(forKey: "itemID") as? UUID
                else { return nil }
                return (itemID, CoreDataDomainMapper.intValue(entity, "sortOrder"))
            },
            uniquingKeysWith: { _, latest in latest }
        )
        var snapshot = CatalogSnapshot()
        snapshot.homes = homeEntities
            .map(home)
            .sorted { lhs, rhs in
                switch (homeSortOrderByItemID[lhs.id], homeSortOrderByItemID[rhs.id]) {
                case let (lhsOrder?, rhsOrder?):
                    if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }

                let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        snapshot.locations = locationEntities.map { CoreDataDomainMapper.location(from: $0, sortOrder: sortOrderByItemID[uuidValue($0, "id")]) }
        snapshot.collectionLocations = collectionLocationEntities.map { CoreDataDomainMapper.location(from: $0, sortOrder: sortOrderByItemID[uuidValue($0, "id")]) }
        snapshot.collections = collectionEntities
            .map(collection)
            .sorted { lhs, rhs in
                switch (collectionSortOrderByItemID[lhs.id], collectionSortOrderByItemID[rhs.id]) {
                case let (lhsOrder?, rhsOrder?):
                    if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }

                let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        snapshot.places = placeEntities.map { CoreDataDomainMapper.place(from: $0) }
        snapshot.collectionEntities = collectionEntities
        snapshot.itemEntities = itemEntities
        snapshot.publisherEntities = publisherEntities
        snapshot.personEntities = personEntities
        snapshot.locationsByHomeID = Dictionary(grouping: locationEntities.compactMap { locationRow(from: $0, sortOrderByItemID: sortOrderByItemID) }, by: \.0)
            .mapValues { rows in
                rows.map(\.1).sorted { lhs, rhs in
                    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        snapshot.collectionLocationsByCollectionID = Dictionary(
            grouping: collectionLocationEntities.compactMap { collectionLocationRow(from: $0, sortOrderByItemID: sortOrderByItemID) },
            by: \.0
        )
        .mapValues { rows in rows.map(\.1) }
        snapshot.collectionCountsByHomeID = Dictionary(
            collectionEntities.compactMap(collectionHomeID).map { ($0, 1) },
            uniquingKeysWith: +
        )
        snapshot.itemCountsByCollectionID = Dictionary(
            itemEntities.compactMap(collectionItemCollectionID).map { ($0, 1) },
            uniquingKeysWith: +
        )
        snapshot.locationPathByID = Dictionary(
            uniqueKeysWithValues: locationEntities.map { (uuidValue($0, "id"), storageLocationPath(from: $0)) }
        )
        snapshot.collectionLocationPathByCollectionID = Dictionary(
            grouping: collectionLocationEntities.compactMap(collectionLocationPathRow),
            by: \.0
        )
        .mapValues { rows in Dictionary(rows.map(\.1), uniquingKeysWith: { first, _ in first }) }
        return snapshot
    }

    nonisolated private static func fetchEntities(
        named entityName: String,
        in context: NSManagedObjectContext,
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor] = [],
        affectedStores: [NSPersistentStore]? = nil
    ) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        request.affectedStores = affectedStores
        return (try? context.fetch(request)) ?? []
    }

    nonisolated private static func home(from entity: NSManagedObject) -> Home {
        Home(
            id: uuidValue(entity, "id"),
            name: stringValue(entity, "name"),
            iconName: stringValue(entity, "iconName", default: "house.fill"),
            notes: stringValue(entity, "notes"),
            isShared: isSharedStoreEntity(entity)
        )
    }

    nonisolated private static func isSharedStoreEntity(_ entity: NSManagedObject) -> Bool {
        entity.objectID.persistentStore?.url?.lastPathComponent == "Shared.sqlite"
    }

    nonisolated private static func collection(from entity: NSManagedObject) -> Collection {
        Collection(
            id: uuidValue(entity, "id"),
            homeID: collectionHomeID(from: entity),
            kind: collectionKind(from: stringValue(entity, "kind", default: CollectionKind.bells.rawValue)),
            title: stringValue(entity, "title"),
            notes: stringValue(entity, "notes"),
            backgroundStyle: collectionBackgroundStyle(from: stringValue(entity, "backgroundStyle", default: CollectionBackgroundStyle.amber.rawValue))
        )
    }

    nonisolated private static func locationRow(from entity: NSManagedObject, sortOrderByItemID: [UUID: Int]) -> (UUID, Location)? {
        guard let home = entity.value(forKey: "home") as? NSManagedObject else { return nil }
        let homeID = uuidValue(home, "id")

        return (homeID, CoreDataDomainMapper.location(from: entity, sortOrder: sortOrderByItemID[uuidValue(entity, "id")]))
    }

    nonisolated private static func collectionLocationRow(from entity: NSManagedObject, sortOrderByItemID: [UUID: Int]) -> (UUID, Location)? {
        guard let collectionID = collectionLocationCollectionID(from: entity) else { return nil }
        return (collectionID, CoreDataDomainMapper.location(from: entity, sortOrder: sortOrderByItemID[uuidValue(entity, "id")]))
    }

    nonisolated private static func collectionLocationPathRow(from entity: NSManagedObject) -> (UUID, (UUID, String))? {
        guard let collectionID = collectionLocationCollectionID(from: entity) else { return nil }
        return (collectionID, (uuidValue(entity, "id"), collectionLocationPath(from: entity)))
    }

    private func collectionSummary(from collection: Collection) -> CollectionSummary {
        let itemCount = itemCountsByCollectionID[collection.id] ?? 0

        return CollectionSummary(
            id: collection.id,
            homeID: collection.homeID,
            kind: collection.kind,
            name: collection.title,
            subtitle: collection.notes,
            backgroundStyle: collection.backgroundStyle,
            itemCount: itemCount,
            status: itemCount > 0 ? .active : .planned,
            sharingSummary: "Invitation-only. Members join with Apple ID and receive a role inside the collection."
        )
    }

    nonisolated private static func collectionHomeID(from entity: NSManagedObject) -> UUID {
        (entity.value(forKey: "home") as? NSManagedObject).map { uuidValue($0, "id") }
            ?? entity.value(forKey: "homeID") as? UUID
            ?? UUID()
    }

    nonisolated private static func collectionLocationCollectionID(from entity: NSManagedObject) -> UUID? {
        (entity.value(forKey: "collection") as? NSManagedObject).map { uuidValue($0, "id") }
    }

    nonisolated private static func collectionItemCollectionID(from entity: NSManagedObject) -> UUID? {
        (entity.value(forKey: "collection") as? NSManagedObject).map { uuidValue($0, "id") }
    }

    nonisolated private static func storageLocationPath(from entity: NSManagedObject) -> String {
        locationPath(from: entity)
    }

    nonisolated private static func collectionLocationPath(from entity: NSManagedObject) -> String {
        locationPath(from: entity)
    }

    nonisolated private static func locationPath(from entity: NSManagedObject) -> String {
        var parts: [String] = []
        var current: NSManagedObject? = entity

        while let location = current {
            parts.insert(stringValue(location, "name"), at: 0)
            current = location.value(forKey: "parent") as? NSManagedObject
        }

        return parts.joined(separator: " / ")
    }

    nonisolated private static func uuidValue(_ entity: NSManagedObject, _ key: String) -> UUID {
        guard let value = entity.value(forKey: key) as? UUID else {
            fatalError("Missing UUID for \(entity.entity.name ?? "Unknown").\(key)")
        }
        return value
    }

    nonisolated private static func stringValue(_ entity: NSManagedObject, _ key: String, default defaultValue: String = "") -> String {
        entity.value(forKey: key) as? String ?? defaultValue
    }

    nonisolated private static func collectionKind(from rawValue: String) -> CollectionKind {
        CollectionKind(rawValue: rawValue) ?? .bells
    }

    nonisolated private static func collectionBackgroundStyle(from rawValue: String) -> CollectionBackgroundStyle {
        CollectionBackgroundStyle(rawValue: rawValue) ?? .amber
    }

    nonisolated private static func locationKind(from rawValue: String) -> LocationKind {
        LocationKind(rawValue: rawValue) ?? .room
    }
}
