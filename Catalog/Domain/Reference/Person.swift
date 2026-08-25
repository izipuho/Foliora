import Foundation

/// Represents person data and behavior.
struct Person: Hashable, Codable {
    var name: String
    var birthYear: Int?
    var deathYear: Int?
    var biography: String?
    var birthPlace: Place?
    var deathPlace: Place?
}
