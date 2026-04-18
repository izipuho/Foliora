import Foundation

struct BellDetails: Identifiable, Hashable, Codable {
    let itemID: UUID
    let originPlaceID: UUID?
    var material: BellMaterial
    var customMaterialName: String?

    var id: UUID { itemID }
}

enum BellMaterial: String, CaseIterable, Hashable, Identifiable, Codable {
    case brass
    case bronze
    case ceramic
    case porcelain
    case glass
    case wood
    case silver
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .brass:
            return String(localized: "enum.bell_material.brass")
        case .bronze:
            return String(localized: "enum.bell_material.bronze")
        case .ceramic:
            return String(localized: "enum.bell_material.ceramic")
        case .porcelain:
            return String(localized: "enum.bell_material.porcelain")
        case .glass:
            return String(localized: "enum.bell_material.glass")
        case .wood:
            return String(localized: "enum.bell_material.wood")
        case .silver:
            return String(localized: "enum.bell_material.silver")
        case .other:
            return String(localized: "enum.bell_material.other")
        }
    }
}

struct BellRecord: Identifiable, Hashable {
    let item: Item
    let details: BellDetails
    let originPlace: Place?
    let storageLocation: Location?
    let storagePath: String
    let mediaAssets: [MediaAsset]
    let createdBy: String
    let tags: [String]

    var id: UUID { item.id }
    var title: String { item.title }
    var createdAt: Date { item.createdAt }
    var acquiredYear: Int? { item.acquiredYear }
    var condition: ItemCondition { item.condition }
    var acquisitionMethod: AcquisitionMethod { item.acquisitionMethod }
    var notes: String { item.notes }
    var placeDisplayName: String { originPlace?.displayName ?? String(localized: "common.unknown_origin") }
    var countryName: String { originPlace?.countryName ?? "" }
    var cityName: String { originPlace?.cityName ?? "" }
    var storageLocationName: String { storageLocation?.name ?? String(localized: "common.unassigned") }
    var storageDisplayPath: String { storagePath.isEmpty ? storageLocationName : storagePath }
    var photoCount: Int { mediaAssets.filter { $0.kind == .photo }.count }
    var model3DCount: Int { mediaAssets.filter { $0.kind == .model3D }.count }
    var documentCount: Int { mediaAssets.filter { $0.kind == .document }.count }

    var materialDisplayName: String {
        if details.material == .other, let customMaterialName = details.customMaterialName, !customMaterialName.isEmpty {
            return customMaterialName
        }

        return details.material.displayName
    }
}
