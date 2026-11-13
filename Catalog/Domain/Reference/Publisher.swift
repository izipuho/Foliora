import Foundation

/// Represents a book publisher.
struct Publisher: Identifiable, Hashable, Codable {
    let id: UUID
    let canonicalID: UUID
    let collectionID: UUID
    var name: String
    var logo: MediaAsset?

    init(
        id: UUID,
        canonicalID: UUID? = nil,
        collectionID: UUID,
        name: String,
        logo: MediaAsset? = nil
    ) {
        self.id = id
        self.canonicalID = canonicalID ?? id
        self.collectionID = collectionID
        self.name = name
        self.logo = logo
    }
}
