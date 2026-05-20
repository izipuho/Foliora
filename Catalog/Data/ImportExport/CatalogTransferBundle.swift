import CollectionDomain
import Foundation

struct CatalogTransferBundle: Codable {
    var homes: [Home]
    var locations: [Location]
    var collections: [Collection]
    var places: [Place]
    var bellItems: [BellTransferItem]

    static let empty = CatalogTransferBundle(
        homes: [],
        locations: [],
        collections: [],
        places: [],
        bellItems: []
    )
}

struct BellTransferItem: Codable {
    var item: Item
    var details: BellDetails
    var mediaAssets: [MediaAsset]
    var createdBy: String
    var tags: [String]
}
