import Foundation

/// Represents a book publisher.
struct Publisher: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var location: Place?
    var logo: MediaAsset?

    init(
        id: UUID,
        name: String,
        location: Place?,
        logo: MediaAsset? = nil
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.logo = logo
    }
}
