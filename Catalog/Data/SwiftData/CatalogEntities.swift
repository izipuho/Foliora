import CollectionDomain
import Foundation
import SwiftData

@Model
final class HomeEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var iconName: String?
    var notes: String

    @Relationship(deleteRule: .cascade, inverse: \LocationEntity.home)
    var locations: [LocationEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \CollectionEntity.home)
    var collections: [CollectionEntity] = []

    init(id: UUID, name: String, iconName: String?, notes: String) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.notes = notes
    }

    var homeSnapshot: Home {
        Home(id: id, name: name, iconName: iconName ?? "house.fill", notes: notes)
    }
}

@Model
final class LocationEntity {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var name: String
    var notes: String

    var home: HomeEntity?

    var parent: LocationEntity?

    var children: [LocationEntity] = []

    @Relationship(deleteRule: .nullify, inverse: \BellEntity.location)
    var bells: [BellEntity] = []

    init(
        id: UUID,
        kindRaw: String,
        name: String,
        notes: String
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.name = name
        self.notes = notes
    }

    var pathDisplayName: String {
        var parts = [name]
        var current = parent

        while let location = current {
            parts.insert(location.name, at: 0)
            current = location.parent
        }

        return parts.joined(separator: " / ")
    }

    var kind: LocationKind {
        LocationKind(rawValue: kindRaw) ?? .room
    }

    var storagePath: StoragePath {
        var componentsByKind: [LocationKind: StoragePath.Component] = [:]
        var current: LocationEntity? = self

        while let currentLocation = current {
            let trimmedName = currentLocation.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty, componentsByKind[currentLocation.kind] == nil {
                componentsByKind[currentLocation.kind] = StoragePath.Component(
                    kind: currentLocation.kind,
                    name: trimmedName
                )
            }

            if componentsByKind[.floor] != nil,
               componentsByKind[.room] != nil,
               componentsByKind[.cabinet] != nil,
               componentsByKind[.shelf] != nil {
                break
            }

            current = currentLocation.parent
        }

        let orderedKinds: [LocationKind] = [.floor, .room, .cabinet, .shelf]
        let components = orderedKinds.compactMap { componentsByKind[$0] }
        return StoragePath(components: components)
    }

    var locationSnapshot: Location {
        Location(
            id: id,
            homeID: home?.id ?? UUID(),
            parentLocationID: parent?.id,
            kind: kind,
            name: name,
            notes: notes
        )
    }
}

@Model
final class CollectionEntity {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var title: String
    var notes: String
    var backgroundStyleRaw: String

    var home: HomeEntity?

    @Relationship(deleteRule: .cascade, inverse: \BellEntity.collection)
    var bells: [BellEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \MembershipEntity.collection)
    var memberships: [MembershipEntity] = []

    init(
        id: UUID,
        kindRaw: String,
        title: String,
        notes: String,
        backgroundStyleRaw: String
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.title = title
        self.notes = notes
        self.backgroundStyleRaw = backgroundStyleRaw
    }

    var kind: CollectionKind {
        CollectionKind(rawValue: kindRaw) ?? .bells
    }

    var backgroundStyle: CollectionBackgroundStyle {
        CollectionBackgroundStyle(rawValue: backgroundStyleRaw) ?? .amber
    }

    var summarySnapshot: CollectionSummary {
        let activeMemberships = memberships.filter { $0.status == .active }
        let currentUserRole = activeMemberships.first(where: { $0.userID == "me" })?.role ?? .viewer

        return CollectionSummary(
            id: id,
            homeID: home?.id ?? UUID(),
            kind: kind,
            name: title,
            subtitle: notes,
            backgroundStyle: backgroundStyle,
            itemCount: kind == .bells ? bells.count : 0,
            collaboratorCount: activeMemberships.count,
            role: currentUserRole,
            status: kind == .bells ? .active : .planned,
            sharingSummary: "Invitation-only. Members join with Apple ID and receive a role inside the collection."
        )
    }

    var collectionSnapshot: Collection {
        Collection(
            id: id,
            homeID: home?.id ?? UUID(),
            kind: kind,
            title: title,
            notes: notes,
            backgroundStyle: backgroundStyle
        )
    }
}

@Model
final class MembershipEntity {
    var id: UUID
    var userID: String
    var roleRaw: String
    var statusRaw: String

    var collection: CollectionEntity?

    init(
        id: UUID,
        userID: String,
        roleRaw: String,
        statusRaw: String
    ) {
        self.id = id
        self.userID = userID
        self.roleRaw = roleRaw
        self.statusRaw = statusRaw
    }

    var role: CollectionRole {
        CollectionRole(rawValue: roleRaw) ?? .viewer
    }

    var status: MembershipStatus {
        MembershipStatus(rawValue: statusRaw) ?? .pending
    }

    var membershipSnapshot: Membership {
        Membership(
            id: id,
            collectionID: collection?.id ?? UUID(),
            userID: userID,
            role: role,
            status: status
        )
    }
}

@Model
final class PlaceEntity {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var countryCode: String
    var countryName: String
    var regionName: String?
    var cityName: String?
    var latitude: Double?
    var longitude: Double?

    @Relationship(deleteRule: .nullify, inverse: \BellEntity.originPlace)
    var bells: [BellEntity] = []

    init(
        id: UUID,
        displayName: String,
        countryCode: String,
        countryName: String,
        regionName: String?,
        cityName: String?,
        latitude: Double?,
        longitude: Double?
    ) {
        self.id = id
        self.displayName = displayName
        self.countryCode = countryCode
        self.countryName = countryName
        self.regionName = regionName
        self.cityName = cityName
        self.latitude = latitude
        self.longitude = longitude
    }

    var placeSnapshot: Place {
        Place(
            id: id,
            displayName: displayName,
            countryCode: countryCode,
            countryName: countryName,
            regionName: regionName,
            cityName: cityName,
            latitude: latitude,
            longitude: longitude
        )
    }
}

@Model
final class BellEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var acquiredYear: Int?
    var createdAt: Date
    var conditionRaw: String
    var acquisitionMethodRaw: String
    var materialRaw: String
    var customMaterialName: String?
    var createdBy: String

    var collection: CollectionEntity?
    var location: LocationEntity?
    var originPlace: PlaceEntity?

    @Relationship(deleteRule: .cascade, inverse: \MediaAssetEntity.bell)
    var mediaAssets: [MediaAssetEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \BellTagEntity.bell)
    var tags: [BellTagEntity] = []

    init(
        id: UUID,
        title: String,
        notes: String,
        acquiredYear: Int?,
        createdAt: Date,
        conditionRaw: String,
        acquisitionMethodRaw: String,
        materialRaw: String,
        customMaterialName: String?,
        createdBy: String
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.acquiredYear = acquiredYear
        self.createdAt = createdAt
        self.conditionRaw = conditionRaw
        self.acquisitionMethodRaw = acquisitionMethodRaw
        self.materialRaw = materialRaw
        self.customMaterialName = customMaterialName
        self.createdBy = createdBy
    }

    var placeDisplayName: String {
        originPlace?.displayName ?? String(localized: "common.unknown_origin")
    }

    var storageLocationName: String {
        location?.name ?? String(localized: "common.unassigned")
    }

    var storagePath: String {
        location?.pathDisplayName ?? storageLocationName
    }

    var storageDisplayPath: String {
        storagePath.isEmpty ? storageLocationName : storagePath
    }

    var countryName: String {
        originPlace?.countryName ?? ""
    }

    var cityName: String {
        originPlace?.cityName ?? ""
    }

    var condition: ItemCondition {
        ItemCondition(rawValue: conditionRaw) ?? .good
    }

    var acquisitionMethod: AcquisitionMethod {
        AcquisitionMethod(rawValue: acquisitionMethodRaw) ?? .bought
    }

    var material: BellMaterial {
        BellMaterial(rawValue: materialRaw) ?? .brass
    }

    var materialDisplayName: String {
        if material == .other,
           let customMaterialName,
           !customMaterialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customMaterialName
        }

        return material.displayName
    }

    var sortedMediaAssets: [MediaAssetEntity] {
        mediaAssets.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }

            return lhs.localIdentifier < rhs.localIdentifier
        }
    }

    var sortedTags: [BellTagEntity] {
        tags.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }

            return lhs.value.localizedCaseInsensitiveCompare(rhs.value) == .orderedAscending
        }
    }

    var tagValues: [String] {
        sortedTags.map(\.value)
    }

    var photoCount: Int {
        sortedMediaAssets.filter { $0.kind == .photo }.count
    }

    var model3DCount: Int {
        sortedMediaAssets.filter { $0.kind == .model3D }.count
    }

    var documentCount: Int {
        sortedMediaAssets.filter { $0.kind == .document }.count
    }

    var coverPhotoAsset: MediaAssetEntity? {
        sortedMediaAssets.first { $0.kind == .photo }
    }

    static func allDescriptor() -> FetchDescriptor<BellEntity> {
        FetchDescriptor(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    }

    static func descriptor(collectionID: UUID) -> FetchDescriptor<BellEntity> {
        let optionalCollectionID = Optional(collectionID)
        return FetchDescriptor(
            predicate: #Predicate<BellEntity> { bell in
                bell.collection?.id == optionalCollectionID
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    var recordSnapshot: BellRecord {
        BellRecord(
            item: Item(
                id: id,
                collectionID: collection?.id ?? UUID(),
                locationID: location?.id,
                createdAt: createdAt,
                title: title,
                notes: notes,
                acquiredYear: acquiredYear,
                condition: condition,
                acquisitionMethod: acquisitionMethod
            ),
            details: BellDetails(
                itemID: id,
                originPlaceID: originPlace?.id,
                material: material,
                customMaterialName: customMaterialName
            ),
            originPlace: originPlace.map {
                Place(
                    id: $0.id,
                    displayName: $0.displayName,
                    countryCode: $0.countryCode,
                    countryName: $0.countryName,
                    regionName: $0.regionName,
                    cityName: $0.cityName,
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            },
            storageLocation: location.map {
                Location(
                    id: $0.id,
                    homeID: $0.home?.id ?? UUID(),
                    parentLocationID: $0.parent?.id,
                    kind: $0.kind,
                    name: $0.name,
                    notes: $0.notes
                )
            },
            storagePath: storagePath,
            mediaAssets: sortedMediaAssets.map {
                MediaAsset(
                    id: $0.id,
                    itemID: id,
                    kind: $0.kind,
                    localIdentifier: $0.localIdentifier,
                    displayName: $0.displayName,
                    sortOrder: $0.sortOrder
                )
            },
            createdBy: createdBy,
            tags: tagValues
        )
    }
}

@Model
final class BellTagEntity {
    var id: UUID = UUID()
    var value: String
    var sortOrder: Int

    var bell: BellEntity?

    init(id: UUID = UUID(), value: String, sortOrder: Int) {
        self.id = id
        self.value = value
        self.sortOrder = sortOrder
    }
}

@Model
final class MediaAssetEntity {
    var id: UUID
    var kindRaw: String
    var localIdentifier: String
    var displayName: String?
    var sortOrder: Int

    var bell: BellEntity?

    init(
        id: UUID,
        kindRaw: String,
        localIdentifier: String,
        displayName: String?,
        sortOrder: Int
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.localIdentifier = localIdentifier
        self.displayName = displayName
        self.sortOrder = sortOrder
    }

    var kind: MediaKind {
        MediaKind(rawValue: kindRaw) ?? .photo
    }
}
