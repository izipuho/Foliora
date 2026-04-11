import Foundation

struct BellDetails: Identifiable, Hashable {
    let itemID: UUID
    let originPlaceID: UUID?
    var material: BellMaterial
    var customMaterialName: String?

    var id: UUID { itemID }
}

enum BellMaterial: String, CaseIterable, Hashable, Identifiable {
    case brass
    case bronze
    case ceramic
    case porcelain
    case glass
    case wood
    case silver
    case other

    var id: String { rawValue }
}

typealias BellCondition = ItemCondition

struct BellItem: Identifiable, Hashable {
    let id: UUID
    let collectionID: UUID
    var title: String
    var originCountry: String
    var originCity: String
    var material: String
    var year: Int?
    var condition: BellCondition
    var acquisition: AcquisitionMethod
    var notes: String
    var tags: [String]
    var createdBy: String
}
