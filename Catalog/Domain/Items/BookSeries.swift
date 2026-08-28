import Foundation

/// Represents a book series scoped to a single collection.
struct BookSeries: Identifiable, Hashable, Codable {
    let id: UUID
    let collectionID: UUID
    var name: String
    var totalBookCount: Int?
    var publisher: Publisher? = nil
}
