import Foundation

private func IL(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

struct Item: Identifiable, Hashable, Codable {
    let id: UUID
    let collectionID: UUID
    let locationID: UUID?
    let createdAt: Date
    var title: String
    var notes: String
    var acquiredYear: Int?
    var condition: ItemCondition
    var acquisitionMethod: AcquisitionMethod

    private enum CodingKeys: String, CodingKey {
        case id
        case collectionID
        case locationID
        case createdAt
        case title
        case notes
        case acquiredYear
        case condition
        case acquisitionMethod
    }

    init(
        id: UUID,
        collectionID: UUID,
        locationID: UUID?,
        createdAt: Date,
        title: String,
        notes: String,
        acquiredYear: Int?,
        condition: ItemCondition,
        acquisitionMethod: AcquisitionMethod
    ) {
        self.id = id
        self.collectionID = collectionID
        self.locationID = locationID
        self.createdAt = createdAt
        self.title = title
        self.notes = notes
        self.acquiredYear = acquiredYear
        self.condition = condition
        self.acquisitionMethod = acquisitionMethod
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        collectionID = try container.decode(UUID.self, forKey: .collectionID)
        locationID = try container.decodeIfPresent(UUID.self, forKey: .locationID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decode(String.self, forKey: .notes)
        acquiredYear = try container.decodeIfPresent(Int.self, forKey: .acquiredYear)
        condition = try container.decode(ItemCondition.self, forKey: .condition)
        acquisitionMethod = try container.decode(AcquisitionMethod.self, forKey: .acquisitionMethod)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(collectionID, forKey: .collectionID)
        try container.encodeIfPresent(locationID, forKey: .locationID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(acquiredYear, forKey: .acquiredYear)
        try container.encode(condition, forKey: .condition)
        try container.encode(acquisitionMethod, forKey: .acquisitionMethod)
    }
}

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
            return IL("enum.item_condition.mint")
        case .good:
            return IL("enum.item_condition.good")
        case .worn:
            return IL("enum.item_condition.worn")
        case .damaged:
            return IL("enum.item_condition.damaged")
        case .needsRestoration:
            return IL("enum.item_condition.needs_restoration")
        }
    }
}

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
            return IL("enum.acquisition.bought")
        case .gifted:
            return IL("enum.acquisition.gifted")
        case .inherited:
            return IL("enum.acquisition.inherited")
        case .found:
            return IL("enum.acquisition.found")
        case .other:
            return IL("enum.acquisition.other")
        }
    }
}
