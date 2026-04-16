import Foundation

struct CatalogTransferBundle: Codable {
    var homes: [Home]
    var locations: [Location]
    var collections: [Collection]
    var memberships: [Membership]
    var places: [Place]
    var bellItems: [BellTransferItem]
    var userDirectory: [String: String]

    static let empty = CatalogTransferBundle(
        homes: [],
        locations: [],
        collections: [],
        memberships: [],
        places: [],
        bellItems: [],
        userDirectory: [:]
    )
}

struct BellTransferItem: Codable {
    var item: Item
    var details: BellDetails
    var mediaAssets: [MediaAsset]
    var createdBy: String
    var tags: [String]
}
