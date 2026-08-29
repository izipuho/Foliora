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

    /// Keeps existing preview fixtures source-compatible while the domain uses a singular logo.
    init(
        id: UUID,
        name: String,
        location: Place?,
        logos: [MediaAsset]
    ) {
        self.init(
            id: id,
            name: name,
            location: location,
            logo: logos.sorted { $0.sortOrder < $1.sortOrder }.first
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case location
        case logo
        case logos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        location = try container.decodeIfPresent(Place.self, forKey: .location)
        logo = try container.decodeIfPresent(MediaAsset.self, forKey: .logo)
            ?? container.decodeIfPresent([MediaAsset].self, forKey: .logos)?
                .sorted { $0.sortOrder < $1.sortOrder }
                .first
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(logo, forKey: .logo)
    }
}
