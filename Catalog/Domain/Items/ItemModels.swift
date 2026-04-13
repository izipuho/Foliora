import Foundation

private func IL(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

struct Item: Identifiable, Hashable, Codable {
    let id: UUID
    let collectionID: UUID
    let locationID: UUID?
    var title: String
    var notes: String
    var year: Int?
    var condition: ItemCondition
    var acquisitionMethod: AcquisitionMethod
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
