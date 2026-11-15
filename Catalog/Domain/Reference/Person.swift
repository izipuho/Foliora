import Foundation

/// Represents person data and behavior.
struct Person: Identifiable, Hashable, Codable {
    let id: UUID
    let canonicalID: UUID
    let collectionID: UUID
    var givenName: String
    var familyName: String?
    var middleName: String?
    var birthYear: Int?
    var deathYear: Int?
    var biography: String?
    var birthPlace: String?
    var deathPlace: String?
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

    init(
        id: UUID,
        canonicalID: UUID? = nil,
        collectionID: UUID,
        givenName: String,
        familyName: String? = nil,
        middleName: String? = nil,
        birthYear: Int?,
        deathYear: Int?,
        biography: String?,
        birthPlace: String?,
        deathPlace: String?,
        photos: [MediaAsset] = []
    ) {
        self.id = id
        self.canonicalID = canonicalID ?? id
        self.collectionID = collectionID
        self.givenName = Self.normalizedNamePart(givenName) ?? ""
        self.familyName = Self.normalizedNamePart(familyName)
        self.middleName = Self.normalizedNamePart(middleName)
        self.birthYear = birthYear
        self.deathYear = deathYear
        self.biography = biography
        self.birthPlace = Self.normalizedOptionalText(birthPlace)
        self.deathPlace = Self.normalizedOptionalText(deathPlace)
        self.photos = photos
    }

    private static func normalizedNamePart(_ value: String?) -> String? {
        normalizedOptionalText(value)
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
