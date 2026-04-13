import Foundation

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
}

enum AcquisitionMethod: String, CaseIterable, Identifiable, Codable {
    case bought = "Bought"
    case gifted = "Gifted"
    case inherited = "Inherited"
    case found = "Found"
    case other = "Other"

    var id: String { rawValue }
}
