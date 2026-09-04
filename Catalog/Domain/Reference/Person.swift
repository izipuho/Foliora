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

    private static func normalizedNamePart(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
