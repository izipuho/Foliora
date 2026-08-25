import Foundation

/// Represents bell-specific transfer payload data and behavior.
struct BellCatalogTransferPayload: Codable {
    static let domain = "bells"
    static let version = 1

    var items: [BellCatalogTransferItem]
}

/// Represents bell-specific transfer details for one item.
struct BellCatalogTransferItem: Codable {
    var itemID: UUID
    var material: String
    var customMaterialName: String?
}
