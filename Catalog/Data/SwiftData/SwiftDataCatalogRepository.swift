import Foundation
import SwiftData

@MainActor
final class SwiftDataCatalogRepository: CatalogRepository {
    private let container: ModelContainer
    private let context: ModelContext
    private let currentUserID = "me"

    init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
    }

    func fetchHomes() -> [Home] {
        fetchEntities(HomeEntity.self, sortBy: [SortDescriptor(\.name)]).map {
            Home(id: $0.id, name: $0.name, notes: $0.notes)
        }
    }

    func fetchLocations(in homeID: UUID) -> [Location] {
        fetchEntities(LocationEntity.self)
        .filter { $0.home?.id == homeID }
        .map(location(from:))
    }

    func fetchDomainCollections(in homeID: UUID) -> [Collection] {
        fetchEntities(CollectionEntity.self)
        .filter { $0.home?.id == homeID }
        .map(collection(from:))
    }

    func fetchMemberships(for collectionID: UUID) -> [Membership] {
        fetchEntities(MembershipEntity.self)
        .filter { $0.collection?.id == collectionID }
        .map(membership(from:))
    }

    func fetchCollections() -> [CollectionSummary] {
        fetchEntities(CollectionEntity.self, sortBy: [SortDescriptor(\.title)]).map { entity in
            let memberships = entity.memberships.filter { membershipStatus(from: $0.statusRaw) == .active }

            return CollectionSummary(
                id: entity.id,
                homeID: entity.home?.id ?? UUID(),
                kind: collectionKind(from: entity.kindRaw),
                name: entity.title,
                subtitle: entity.notes,
                backgroundStyle: collectionBackgroundStyle(from: entity.backgroundStyleRaw),
                itemCount: collectionKind(from: entity.kindRaw) == .bells ? entity.bells.count : 0,
                collaboratorCount: memberships.count,
                role: memberships.first(where: { $0.userID == currentUserID }).map { collectionRole(from: $0.roleRaw) } ?? .viewer,
                status: collectionKind(from: entity.kindRaw) == .bells ? .active : .planned,
                sharingSummary: "Invitation-only. Members join with Apple ID and receive a role inside the collection."
            )
        }
    }

    func fetchBellRecords(for collectionID: UUID) -> [BellRecord] {
        fetchEntities(BellEntity.self)
        .filter { $0.collection?.id == collectionID }
        .map(bellRecord(from:))
    }

    func fetchCollaborators(for collectionID: UUID) -> [Collaborator] {
        fetchMemberships(for: collectionID)
            .filter { $0.status == .active }
            .map { membership in
                Collaborator(
                    id: membership.id,
                    displayName: displayName(for: membership.userID),
                    role: membership.role,
                    isCurrentUser: membership.userID == currentUserID
                )
            }
    }

    func saveHome(_ home: Home) {
        let entity = fetchHomeEntity(by: home.id) ?? HomeEntity(id: home.id, name: home.name, notes: home.notes)
        entity.name = home.name
        entity.notes = home.notes

        if entity.modelContext == nil {
            context.insert(entity)
        }

        saveContext()
    }

    func saveLocations(_ locations: [Location], in homeID: UUID) {
        guard let home = fetchHomeEntity(by: homeID) else { return }

        let existingLocations = fetchEntities(LocationEntity.self)
            .filter { $0.home?.id == homeID }
        existingLocations.forEach(context.delete)

        var entitiesByID: [UUID: LocationEntity] = [:]

        for location in locations {
            let entity = LocationEntity(
                id: location.id,
                kindRaw: location.kind.rawValue,
                name: location.name,
                notes: location.notes,
                home: home
            )
            context.insert(entity)
            entitiesByID[location.id] = entity
        }

        for location in locations {
            guard let entity = entitiesByID[location.id] else { continue }
            entity.parent = location.parentLocationID.flatMap { entitiesByID[$0] }
        }

        saveContext()
    }

    func deleteHome(homeID: UUID) {
        guard let home = fetchHomeEntity(by: homeID) else { return }
        context.delete(home)
        saveContext()
    }

    func saveCollection(_ collection: Collection) {
        guard let home = fetchHomeEntity(by: collection.homeID) else { return }

        let isNew = fetchCollectionEntity(by: collection.id) == nil
        let entity = fetchCollectionEntity(by: collection.id) ?? CollectionEntity(
            id: collection.id,
            kindRaw: collection.kind.rawValue,
            title: collection.title,
            notes: collection.notes,
            backgroundStyleRaw: collection.backgroundStyle.rawValue,
            home: home
        )

        entity.kindRaw = collection.kind.rawValue
        entity.title = collection.title
        entity.notes = collection.notes
        entity.backgroundStyleRaw = collection.backgroundStyle.rawValue
        entity.home = home

        if entity.modelContext == nil {
            context.insert(entity)
        }

        if isNew && entity.memberships.isEmpty {
            let membership = MembershipEntity(
                id: UUID(),
                userID: currentUserID,
                roleRaw: CollectionRole.owner.rawValue,
                statusRaw: MembershipStatus.active.rawValue,
                collection: entity
            )
            context.insert(membership)
        }

        saveContext()
    }

    func deleteCollection(collectionID: UUID) {
        guard let entity = fetchCollectionEntity(by: collectionID) else { return }
        context.delete(entity)
        saveContext()
    }

    func saveBellRecord(_ bell: BellRecord) {
        guard let collection = fetchCollectionEntity(by: bell.item.collectionID) else { return }

        let entity = fetchBellEntity(by: bell.item.id) ?? BellEntity(
            id: bell.item.id,
            title: bell.item.title,
            notes: bell.item.notes,
            acquiredYear: bell.item.acquiredYear,
            createdAt: bell.item.createdAt,
            conditionRaw: bell.item.condition.rawValue,
            acquisitionMethodRaw: bell.item.acquisitionMethod.rawValue,
            materialRaw: bell.details.material.rawValue,
            customMaterialName: bell.details.customMaterialName,
            createdBy: bell.createdBy,
            collection: collection
        )

        entity.title = bell.item.title
        entity.notes = bell.item.notes
        entity.acquiredYear = bell.item.acquiredYear
        entity.createdAt = bell.item.createdAt
        entity.conditionRaw = bell.item.condition.rawValue
        entity.acquisitionMethodRaw = bell.item.acquisitionMethod.rawValue
        entity.materialRaw = bell.details.material.rawValue
        entity.customMaterialName = bell.details.customMaterialName
        entity.createdBy = bell.createdBy
        entity.collection = collection
        entity.location = bell.item.locationID.flatMap(fetchLocationEntity)
        entity.originPlace = bell.originPlace.map(upsertPlace)

        if entity.modelContext == nil {
            context.insert(entity)
        }

        entity.mediaAssets.forEach(context.delete)
        entity.tags.forEach(context.delete)

        let newMediaAssets = bell.mediaAssets.map { asset in
            MediaAssetEntity(
                id: asset.id,
                kindRaw: asset.kind.rawValue,
                localIdentifier: asset.localIdentifier,
                displayName: asset.displayName,
                sortOrder: asset.sortOrder,
                bell: entity
            )
        }
        newMediaAssets.forEach(context.insert)
        entity.mediaAssets = newMediaAssets

        let newTags = bell.tags.enumerated().map { index, tag in
            BellTagEntity(value: tag, sortOrder: index, bell: entity)
        }
        newTags.forEach(context.insert)
        entity.tags = newTags

        saveContext()
    }

    func deleteBellRecord(bellID: UUID) {
        guard let entity = fetchBellEntity(by: bellID) else { return }
        context.delete(entity)
        saveContext()
    }

    func replaceAllData(with bundle: CatalogTransferBundle) {
        fetchEntities(MediaAssetEntity.self).forEach(context.delete)
        fetchEntities(BellTagEntity.self).forEach(context.delete)
        fetchEntities(BellEntity.self).forEach(context.delete)
        fetchEntities(MembershipEntity.self).forEach(context.delete)
        fetchEntities(CollectionEntity.self).forEach(context.delete)
        fetchEntities(LocationEntity.self).forEach(context.delete)
        fetchEntities(PlaceEntity.self).forEach(context.delete)
        fetchEntities(HomeEntity.self).forEach(context.delete)
        saveContext()

        var homeEntities: [UUID: HomeEntity] = [:]
        var locationEntities: [UUID: LocationEntity] = [:]
        var collectionEntities: [UUID: CollectionEntity] = [:]
        var placeEntities: [UUID: PlaceEntity] = [:]

        for home in bundle.homes {
            let entity = HomeEntity(id: home.id, name: home.name, notes: home.notes)
            context.insert(entity)
            homeEntities[home.id] = entity
        }

        for location in bundle.locations {
            let entity = LocationEntity(
                id: location.id,
                kindRaw: location.kind.rawValue,
                name: location.name,
                notes: location.notes,
                home: homeEntities[location.homeID]
            )
            context.insert(entity)
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
                backgroundStyleRaw: collection.backgroundStyle.rawValue,
                home: homeEntities[collection.homeID]
            )
            context.insert(entity)
            collectionEntities[collection.id] = entity
        }

        for membership in bundle.memberships {
            let entity = MembershipEntity(
                id: membership.id,
                userID: membership.userID,
                roleRaw: membership.role.rawValue,
                statusRaw: membership.status.rawValue,
                collection: collectionEntities[membership.collectionID]
            )
            context.insert(entity)
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
            context.insert(entity)
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
                createdBy: bell.createdBy,
                collection: collectionEntities[bell.item.collectionID],
                location: bell.item.locationID.flatMap { locationEntities[$0] },
                originPlace: bell.details.originPlaceID.flatMap { placeEntities[$0] }
            )
            context.insert(entity)

            let mediaEntities = bell.mediaAssets.map { asset in
                MediaAssetEntity(
                    id: asset.id,
                    kindRaw: asset.kind.rawValue,
                    localIdentifier: asset.localIdentifier,
                    displayName: asset.displayName,
                    sortOrder: asset.sortOrder,
                    bell: entity
                )
            }
            mediaEntities.forEach(context.insert)
            entity.mediaAssets = mediaEntities

            let tagEntities = bell.tags.enumerated().map { index, tag in
                BellTagEntity(value: tag, sortOrder: index, bell: entity)
            }
            tagEntities.forEach(context.insert)
            entity.tags = tagEntities
        }

        saveContext()
    }

    private func upsertPlace(_ place: Place) -> PlaceEntity {
        if let entity = fetchPlaceEntity(by: place.id) {
            entity.displayName = place.displayName
            entity.countryCode = place.countryCode
            entity.countryName = place.countryName
            entity.regionName = place.regionName
            entity.cityName = place.cityName
            entity.latitude = place.latitude
            entity.longitude = place.longitude
            return entity
        }

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
        context.insert(entity)
        return entity
    }

    private func bellRecord(from entity: BellEntity) -> BellRecord {
        let location = entity.location.map(location(from:))

        return BellRecord(
            item: Item(
                id: entity.id,
                collectionID: entity.collection?.id ?? UUID(),
                locationID: entity.location?.id,
                createdAt: entity.createdAt,
                title: entity.title,
                notes: entity.notes,
                acquiredYear: entity.acquiredYear,
                condition: itemCondition(from: entity.conditionRaw),
                acquisitionMethod: acquisitionMethod(from: entity.acquisitionMethodRaw)
            ),
            details: BellDetails(
                itemID: entity.id,
                originPlaceID: entity.originPlace?.id,
                material: bellMaterial(from: entity.materialRaw),
                customMaterialName: entity.customMaterialName
            ),
            originPlace: entity.originPlace.map(place(from:)),
            storageLocation: location,
            storagePath: entity.location.map(locationPath(from:)) ?? "Unassigned",
            mediaAssets: entity.mediaAssets
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(mediaAsset(from:)),
            createdBy: entity.createdBy,
            tags: entity.tags
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.value)
        )
    }

    private func locationPath(from entity: LocationEntity) -> String {
        var parts = [entity.name]
        var current = entity.parent

        while let parent = current {
            parts.insert(parent.name, at: 0)
            current = parent.parent
        }

        return parts.joined(separator: " / ")
    }

    private func location(from entity: LocationEntity) -> Location {
        Location(
            id: entity.id,
            homeID: entity.home?.id ?? UUID(),
            parentLocationID: entity.parent?.id,
            kind: locationKind(from: entity.kindRaw),
            name: entity.name,
            notes: entity.notes
        )
    }

    private func collection(from entity: CollectionEntity) -> Collection {
        Collection(
            id: entity.id,
            homeID: entity.home?.id ?? UUID(),
            kind: collectionKind(from: entity.kindRaw),
            title: entity.title,
            notes: entity.notes,
            backgroundStyle: collectionBackgroundStyle(from: entity.backgroundStyleRaw)
        )
    }

    private func membership(from entity: MembershipEntity) -> Membership {
        Membership(
            id: entity.id,
            collectionID: entity.collection?.id ?? UUID(),
            userID: entity.userID,
            role: collectionRole(from: entity.roleRaw),
            status: membershipStatus(from: entity.statusRaw)
        )
    }

    private func place(from entity: PlaceEntity) -> Place {
        Place(
            id: entity.id,
            displayName: entity.displayName,
            countryCode: entity.countryCode,
            countryName: entity.countryName,
            regionName: entity.regionName,
            cityName: entity.cityName,
            latitude: entity.latitude,
            longitude: entity.longitude
        )
    }

    private func mediaAsset(from entity: MediaAssetEntity) -> MediaAsset {
        MediaAsset(
            id: entity.id,
            itemID: entity.bell?.id ?? UUID(),
            kind: mediaKind(from: entity.kindRaw),
            localIdentifier: entity.localIdentifier,
            displayName: entity.displayName,
            sortOrder: entity.sortOrder
        )
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

    private func collectionRole(from rawValue: String) -> CollectionRole {
        CollectionRole(rawValue: rawValue) ?? .viewer
    }

    private func membershipStatus(from rawValue: String) -> MembershipStatus {
        MembershipStatus(rawValue: rawValue) ?? .pending
    }

    private func itemCondition(from rawValue: String) -> ItemCondition {
        ItemCondition(rawValue: rawValue) ?? .good
    }

    private func acquisitionMethod(from rawValue: String) -> AcquisitionMethod {
        AcquisitionMethod(rawValue: rawValue) ?? .other
    }

    private func bellMaterial(from rawValue: String) -> BellMaterial {
        BellMaterial(rawValue: rawValue) ?? .other
    }

    private func mediaKind(from rawValue: String) -> MediaKind {
        MediaKind(rawValue: rawValue) ?? .photo
    }

    private func displayName(for userID: String) -> String {
        switch userID {
        case "me":
            return "Вы"
        case "marina":
            return "Марина"
        case "alexey":
            return "Алексей"
        case "nina":
            return "Нина"
        default:
            return userID
        }
    }

    private func fetchEntities<T: PersistentModel>(
        _ type: T.Type,
        sortBy: [SortDescriptor<T>] = []
    ) -> [T] {
        let descriptor = FetchDescriptor<T>(sortBy: sortBy)
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchHomeEntity(by id: UUID) -> HomeEntity? { fetchEntities(HomeEntity.self).first { $0.id == id } }
    private func fetchLocationEntity(by id: UUID) -> LocationEntity? { fetchEntities(LocationEntity.self).first { $0.id == id } }
    private func fetchCollectionEntity(by id: UUID) -> CollectionEntity? { fetchEntities(CollectionEntity.self).first { $0.id == id } }
    private func fetchBellEntity(by id: UUID) -> BellEntity? { fetchEntities(BellEntity.self).first { $0.id == id } }
    private func fetchPlaceEntity(by id: UUID) -> PlaceEntity? { fetchEntities(PlaceEntity.self).first { $0.id == id } }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save SwiftData catalog context: \(error)")
        }
    }
}
