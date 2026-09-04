import Foundation

/// Represents person data and behavior.
struct Person: Identifiable, Hashable, Codable {
    let id: UUID
    var givenName: String
    var familyName: String?
    var middleName: String?
    var birthYear: Int?
    var deathYear: Int?
    var biography: String?
    var birthPlace: Place?
    var deathPlace: Place?
    var photos: [MediaAsset] = []

    var displayName: String {
        [
            Self.normalizedNamePart(givenName),
            Self.normalizedNamePart(middleName),
            Self.normalizedNamePart(familyName)
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    var sortName: String {
        if let familyName = Self.normalizedNamePart(familyName) {
            return [
                familyName,
                Self.normalizedNamePart(givenName),
                Self.normalizedNamePart(middleName)
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        }

        return [
            Self.normalizedNamePart(givenName),
            Self.normalizedNamePart(middleName)
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    /// Compatibility surface for code that still expects one display name.
    var name: String {
        get { displayName }
        set {
            givenName = Self.normalizedNamePart(newValue) ?? ""
            familyName = nil
            middleName = nil
        }
    }

    init(
        id: UUID,
        givenName: String,
        familyName: String? = nil,
        middleName: String? = nil,
        birthYear: Int?,
        deathYear: Int?,
        biography: String?,
        birthPlace: Place?,
        deathPlace: Place?,
        photos: [MediaAsset] = []
    ) {
        self.id = id
        self.givenName = Self.normalizedNamePart(givenName) ?? ""
        self.familyName = Self.normalizedNamePart(familyName)
        self.middleName = Self.normalizedNamePart(middleName)
        self.birthYear = birthYear
        self.deathYear = deathYear
        self.biography = biography
        self.birthPlace = birthPlace
        self.deathPlace = deathPlace
        self.photos = photos
    }

    /// Preserves source compatibility while callers migrate to structured names.
    init(
        id: UUID,
        name: String,
        birthYear: Int?,
        deathYear: Int?,
        biography: String?,
        birthPlace: Place?,
        deathPlace: Place?,
        photos: [MediaAsset] = []
    ) {
        self.init(
            id: id,
            givenName: name,
            familyName: nil,
            middleName: nil,
            birthYear: birthYear,
            deathYear: deathYear,
            biography: biography,
            birthPlace: birthPlace,
            deathPlace: deathPlace,
            photos: photos
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case givenName
        case familyName
        case middleName
        case name
        case birthYear
        case deathYear
        case biography
        case birthPlace
        case deathPlace
        case photos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)

        let decodedGivenName = try container.decodeIfPresent(String.self, forKey: .givenName)
        let legacyName = try container.decodeIfPresent(String.self, forKey: .name)
        givenName = Self.normalizedNamePart(decodedGivenName)
            ?? Self.normalizedNamePart(legacyName)
            ?? ""
        familyName = Self.normalizedNamePart(
            try container.decodeIfPresent(String.self, forKey: .familyName)
        )
        middleName = Self.normalizedNamePart(
            try container.decodeIfPresent(String.self, forKey: .middleName)
        )
        birthYear = try container.decodeIfPresent(Int.self, forKey: .birthYear)
        deathYear = try container.decodeIfPresent(Int.self, forKey: .deathYear)
        biography = try container.decodeIfPresent(String.self, forKey: .biography)
        birthPlace = try container.decodeIfPresent(Place.self, forKey: .birthPlace)
        deathPlace = try container.decodeIfPresent(Place.self, forKey: .deathPlace)
        photos = try container.decodeIfPresent([MediaAsset].self, forKey: .photos) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(givenName, forKey: .givenName)
        try container.encodeIfPresent(familyName, forKey: .familyName)
        try container.encodeIfPresent(middleName, forKey: .middleName)
        try container.encode(displayName, forKey: .name)
        try container.encodeIfPresent(birthYear, forKey: .birthYear)
        try container.encodeIfPresent(deathYear, forKey: .deathYear)
        try container.encodeIfPresent(biography, forKey: .biography)
        try container.encodeIfPresent(birthPlace, forKey: .birthPlace)
        try container.encodeIfPresent(deathPlace, forKey: .deathPlace)
        try container.encode(photos, forKey: .photos)
    }

    private static func normalizedNamePart(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
