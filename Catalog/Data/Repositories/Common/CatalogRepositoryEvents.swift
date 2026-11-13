import Foundation

/// Describes a persisted favorite-state change for a catalog item.
struct CatalogItemFavoriteChange: Sendable {
    let itemID: UUID
    let collectionID: UUID?
    let isFavorite: Bool
}

extension Notification.Name {
    static let catalogItemFavoriteDidChange = Notification.Name("catalog.itemFavoriteDidChange")
}
