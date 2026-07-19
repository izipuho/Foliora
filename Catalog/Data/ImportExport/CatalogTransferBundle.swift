import Foundation

struct CatalogTransferBundle: Codable {
    var homes: [Home]
    var locations: [LocationTransferRecord]
    var collections: [CollectionTransferRecord]
    var bellItems: [BellTransferItem]

    static let empty = CatalogTransferBundle(
        homes: [],
        locations: [],
        collections: [],
        places: [],
        bellItems: []
    )

    init(
        homes: [Home],
        locations: [Location],
        collections: [Collection],
        places: [Place],
        bellItems: [BellTransferItem]
    ) {
        let homesByID = Dictionary(uniqueKeysWithValues: homes.map { ($0.id, $0) })
        let locationsByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })

        self.homes = homes
        self.locations = locations.map { location in
            LocationTransferRecord(
                location: location,
                homeName: homesByID[location.homeID]?.name,
                fullPath: Self.locationPath(for: location, locationsByID: locationsByID)
            )
        }
        self.collections = collections.map { collection in
            CollectionTransferRecord(
                collection: collection,
                homeName: homesByID[collection.homeID]?.name
            )
        }
        self.bellItems = bellItems
    }

    private static func locationPath(
        for location: Location,
        locationsByID: [UUID: Location]
    ) -> [StoragePath.Component] {
        var path: [StoragePath.Component] = []
        var current: Location? = location
        var visitedIDs = Set<UUID>()

        while let location = current, visitedIDs.insert(location.id).inserted {
            path.insert(StoragePath.Component(kind: location.kind, name: location.name), at: 0)
            current = location.parentLocationID.flatMap { locationsByID[$0] }
        }

        return path
    }
}

struct CollectionTransferRecord: Identifiable, Hashable, Codable {
    let id: UUID
    let homeID: UUID
    var kind: CollectionKind
    var title: String
    var notes: String
    var backgroundStyle: CollectionBackgroundStyle
    var homeName: String?

    init(
        collection: Collection,
        homeName: String?
    ) {
        id = collection.id
        homeID = collection.homeID
        kind = collection.kind
        title = collection.title
        notes = collection.notes
        backgroundStyle = collection.backgroundStyle
        self.homeName = homeName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case homeID
        case kind
        case title
        case notes
        case backgroundStyle
        case homeName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        homeID = try container.decode(UUID.self, forKey: .homeID)
        kind = try container.decode(CollectionKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decode(String.self, forKey: .notes)
        backgroundStyle = try container.decodeIfPresent(CollectionBackgroundStyle.self, forKey: .backgroundStyle) ?? .amber
        homeName = try container.decodeIfPresent(String.self, forKey: .homeName)
    }
}

struct LocationTransferRecord: Identifiable, Hashable, Codable {
    let id: UUID
    let homeID: UUID
    var parentLocationID: UUID?
    var kind: LocationKind
    var name: String
    var notes: String
    var homeName: String?
    var fullPath: [StoragePath.Component]?

    init(
        location: Location,
        homeName: String?,
        fullPath: [StoragePath.Component]
    ) {
        id = location.id
        homeID = location.homeID
        parentLocationID = location.parentLocationID
        kind = location.kind
        name = location.name
        notes = location.notes
        self.homeName = homeName
        self.fullPath = fullPath
    }
}

struct OriginPlaceTransferValue: Hashable, Codable {
    var displayName: String
    var latitude: Double
    var longitude: Double

    init?(_ place: Place) {
        guard let latitude = place.latitude, let longitude = place.longitude else {
            return nil
        }

        displayName = place.displayName
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct BellTransferItem: Codable {
    var item: Item
    var details: BellDetails
    var originPlace: OriginPlaceTransferValue?
    var mediaAssets: [MediaAsset]
    var createdBy: String
    var tags: [String]

    init(
        item: Item,
        details: BellDetails,
        originPlace: OriginPlaceTransferValue?,
        mediaAssets: [MediaAsset],
        createdBy: String,
        tags: [String]
    ) {
        self.item = item
        self.details = details
        self.originPlace = originPlace
        self.mediaAssets = mediaAssets
        self.createdBy = createdBy
        self.tags = tags
    }
}
