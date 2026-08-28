import Foundation

/// Represents a book publisher.
struct Publisher: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var location: Place?
    var logos: [MediaAsset] = []
}
