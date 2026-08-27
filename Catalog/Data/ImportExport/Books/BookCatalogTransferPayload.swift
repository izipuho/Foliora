import Foundation

/// Represents book-specific transfer payload data and behavior.
struct BookCatalogTransferPayload: Codable {
    static let domain = "books"
    static let version = 1

    var items: [BookCatalogTransferItem]
    var series: [BookSeries]

    init(items: [BookCatalogTransferItem], series: [BookSeries] = []) {
        self.items = items
        self.series = series
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case series
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([BookCatalogTransferItem].self, forKey: .items)
        series = try container.decodeIfPresent([BookSeries].self, forKey: .series) ?? []
    }
}

/// Represents book-specific transfer details for one item.
struct BookCatalogTransferItem: Codable {
    var itemID: UUID
    var details: BookDetails
}
