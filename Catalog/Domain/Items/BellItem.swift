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
            return "Brass"
        case .bronze:
            return "Bronze"
        case .ceramic:
            return "Ceramic"
        case .porcelain:
            return "Porcelain"
        case .glass:
            return "Glass"
        case .wood:
            return "Wood"
        case .silver:
            return "Silver"
        case .other:
            return "Other"
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
    var year: Int? { item.year }
    var condition: ItemCondition { item.condition }
    var acquisitionMethod: AcquisitionMethod { item.acquisitionMethod }
    var notes: String { item.notes }
    var placeDisplayName: String { originPlace?.displayName ?? "Unknown origin" }
    var countryName: String { originPlace?.countryName ?? "" }
    var cityName: String { originPlace?.cityName ?? "" }
    var storageLocationName: String { storageLocation?.name ?? "Unassigned" }
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
