import Foundation

/// Represents person data and behavior.
struct Person: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var birthYear: Int?
    var deathYear: Int?
    var biography: String?
    var birthPlace: Place?
    var deathPlace: Place?
    var photos: [MediaAsset] = []
}
