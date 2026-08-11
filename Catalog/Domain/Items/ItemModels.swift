import Foundation

/// Represents item record data and behavior.
struct ItemRecord: Identifiable, Hashable, Codable {
    let id: UUID
    let collectionID: UUID
    let locationID: UUID?
    let originPlaceID: UUID?
    let createdAt: Date
    let createdBy: String
    var title: String
    var notes: String
    var acquiredYear: Int?
    var condition: ItemCondition
    var acquisitionMethod: AcquisitionMethod
    var isFavorite: Bool
    var tags: [String]
    var originPlace: Place?
    var storageLocation: Location?
    var storagePath: String
    var mediaAssets: [MediaAsset]

    private enum CodingKeys: String, CodingKey {
        case id
        case collectionID
        case locationID
        case originPlaceID
        case createdAt
        case createdBy
        case title
        case notes
        case acquiredYear
        case condition
        case acquisitionMethod
        case isFavorite
        case tags
    }

    init(
        id: UUID,
        collectionID: UUID,
        locationID: UUID?,
        originPlaceID: UUID?,
        createdAt: Date,
        createdBy: String,
        title: String,
        notes: String,
        acquiredYear: Int?,
        condition: ItemCondition,
        acquisitionMethod: AcquisitionMethod,
        isFavorite: Bool,
        tags: [String],
        originPlace: Place?,
        storageLocation: Location?,
        storagePath: String,
        mediaAssets: [MediaAsset]
    ) {
        self.id = id
        self.collectionID = collectionID
        self.locationID = locationID
        self.originPlaceID = originPlaceID
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.title = title
        self.notes = notes
        self.acquiredYear = acquiredYear
        self.condition = condition
        self.acquisitionMethod = acquisitionMethod
        self.isFavorite = isFavorite
        self.tags = tags
        self.originPlace = originPlace
        self.storageLocation = storageLocation
        self.storagePath = storagePath
        self.mediaAssets = mediaAssets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        collectionID = try container.decode(UUID.self, forKey: .collectionID)
        locationID = try container.decodeIfPresent(UUID.self, forKey: .locationID)
        originPlaceID = try container.decodeIfPresent(UUID.self, forKey: .originPlaceID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        createdBy = try container.decode(String.self, forKey: .createdBy)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decode(String.self, forKey: .notes)
        acquiredYear = try container.decodeIfPresent(Int.self, forKey: .acquiredYear)
        condition = try container.decode(ItemCondition.self, forKey: .condition)
        acquisitionMethod = try container.decode(AcquisitionMethod.self, forKey: .acquisitionMethod)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        tags = try container.decode([String].self, forKey: .tags)
        originPlace = nil
        storageLocation = nil
        storagePath = ""
        mediaAssets = []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(collectionID, forKey: .collectionID)
        try container.encodeIfPresent(locationID, forKey: .locationID)
        try container.encodeIfPresent(originPlaceID, forKey: .originPlaceID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(acquiredYear, forKey: .acquiredYear)
        try container.encode(condition, forKey: .condition)
        try container.encode(acquisitionMethod, forKey: .acquisitionMethod)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(tags, forKey: .tags)
    }
}

/// Groups item condition values and behavior.
enum ItemCondition: String, CaseIterable, Identifiable, Codable {
    case mint = "Mint"
    case good = "Good"
    case worn = "Worn"
    case damaged = "Damaged"
    case needsRestoration = "Needs Restoration"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mint:
            return String(localized: "enum.item_condition.mint")
        case .good:
            return String(localized: "enum.item_condition.good")
        case .worn:
            return String(localized: "enum.item_condition.worn")
        case .damaged:
            return String(localized: "enum.item_condition.damaged")
        case .needsRestoration:
            return String(localized: "enum.item_condition.needs_restoration")
        }
    }
}

/// Groups acquisition method values and behavior.
enum AcquisitionMethod: String, CaseIterable, Identifiable, Codable {
    case bought = "Bought"
    case gifted = "Gifted"
    case inherited = "Inherited"
    case found = "Found"
    case other = "Other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bought:
            return String(localized: "enum.acquisition.bought")
        case .gifted:
            return String(localized: "enum.acquisition.gifted")
        case .inherited:
            return String(localized: "enum.acquisition.inherited")
        case .found:
            return String(localized: "enum.acquisition.found")
        case .other:
            return String(localized: "enum.acquisition.other")
        }
    }
}
