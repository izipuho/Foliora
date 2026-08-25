import Foundation

/// Represents book-specific transfer payload data and behavior.
struct BookCatalogTransferPayload: Codable {
    static let domain = "books"
    static let version = 1

    var items: [BookCatalogTransferItem]
}

/// Represents book-specific transfer details for one item.
struct BookCatalogTransferItem: Codable {
    var itemID: UUID
    var details: BookDetails
}
