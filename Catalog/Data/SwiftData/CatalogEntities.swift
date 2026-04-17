import Foundation
import SwiftData

@Model
final class HomeEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var notes: String

    @Relationship(deleteRule: .cascade, inverse: \LocationEntity.home)
    var locations: [LocationEntity] = []

    @Relationship(deleteRule: .cascade, inverse: \CollectionEntity.home)
    var collections: [CollectionEntity] = []

    init(id: UUID, name: String, notes: String) {
        self.id = id
        self.name = name
        self.notes = notes
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
        notes: String,
        home: HomeEntity? = nil,
        parent: LocationEntity? = nil
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.name = name
        self.notes = notes
        self.home = home
        self.parent = parent
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
        backgroundStyleRaw: String,
        home: HomeEntity? = nil
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.title = title
        self.notes = notes
        self.backgroundStyleRaw = backgroundStyleRaw
        self.home = home
    }
}

@Model
final class MembershipEntity {
    @Attribute(.unique) var id: UUID
    var userID: String
    var roleRaw: String
    var statusRaw: String

    var collection: CollectionEntity?

    init(
        id: UUID,
        userID: String,
        roleRaw: String,
        statusRaw: String,
        collection: CollectionEntity? = nil
    ) {
        self.id = id
        self.userID = userID
        self.roleRaw = roleRaw
        self.statusRaw = statusRaw
        self.collection = collection
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
        createdBy: String,
        collection: CollectionEntity? = nil,
        location: LocationEntity? = nil,
        originPlace: PlaceEntity? = nil
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
        self.collection = collection
        self.location = location
        self.originPlace = originPlace
    }
}

@Model
final class BellTagEntity {
    @Attribute(.unique) var id: UUID
    var value: String
    var sortOrder: Int

    var bell: BellEntity?

    init(id: UUID = UUID(), value: String, sortOrder: Int, bell: BellEntity? = nil) {
        self.id = id
        self.value = value
        self.sortOrder = sortOrder
        self.bell = bell
    }
}

@Model
final class MediaAssetEntity {
    @Attribute(.unique) var id: UUID
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
        sortOrder: Int,
        bell: BellEntity? = nil
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.localIdentifier = localIdentifier
        self.displayName = displayName
        self.sortOrder = sortOrder
        self.bell = bell
    }
}
