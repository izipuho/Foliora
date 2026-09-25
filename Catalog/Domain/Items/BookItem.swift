import Foundation

/// Defines a person's contribution to a book.
struct BookContributor: Hashable, Codable {
    var role: BookContributorRole
    var order: Int
    var person: Person
}

/// Defines the supported book contributor roles.
enum BookContributorRole: String, CaseIterable, Hashable, Identifiable, Codable {
    case author
    case translator
    case editor
    case illustrator

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .author:
            return String(localized: "book_contributor.role.author")
        case .translator:
            return String(localized: "book_contributor.role.translator")
        case .editor:
            return String(localized: "book_contributor.role.editor")
        case .illustrator:
            return String(localized: "book_contributor.role.illustrator")
        }
    }
}

/// Describes a forced replacement or clear for one contributor role in a batch edit.
struct BookContributorBatchEdit: Hashable {
    var role: BookContributorRole
    var person: Person?

    func applying(to contributors: [BookContributor]) -> [BookContributor] {
        let ordered = contributors.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.person.sortName.localizedCaseInsensitiveCompare(rhs.person.sortName) == .orderedAscending
        }
        let existingRoleIndex = ordered.firstIndex { $0.role == role }
        var result = ordered.filter { $0.role != role }

        if let person {
            let insertionIndex = min(existingRoleIndex ?? result.count, result.count)
            result.insert(
                BookContributor(
                    role: role,
                    order: insertionIndex,
                    person: person
                ),
                at: insertionIndex
            )
        }

        return result.enumerated().map { index, contributor in
            var updated = contributor
            updated.order = index
            return updated
        }
    }
}

/// Represents a typed external or catalog identifier assigned to a book.
struct BookIdentifier: Hashable, Codable, Sendable {
    var type: BookIdentifierType
    var value: String
}

/// Defines the supported book identifier types.
enum BookIdentifierType: String, CaseIterable, Hashable, Identifiable, Codable, Sendable {
    case isbn10
    case isbn13
    case sbn
    case asin
    case inventory
    case other

    var id: String { rawValue }
}

/// Represents book-specific details attached to a catalog item.
struct BookDetails: Identifiable, Hashable, Codable {
    let itemID: UUID
    // Subtitle is bibliographic metadata; free-form user notes remain on the shared ItemRecord.
    var subtitle: String? = nil
    var languageCode: String?
    var genre: String? = nil
    var pageCount: Int?
    var publicationYear: Int?
    var volumeNumber: Int?
    var coverImage: MediaAsset? = nil
    var publisher: Publisher? = nil
    var contributors: [BookContributor]
    var series: BookSeries? = nil
    var identifiers: [BookIdentifier] = []

    var id: UUID { itemID }
}

/// Describes a deterministic cover generated from book metadata.
struct BookGeneratedCover: Hashable {
    let bookID: UUID
    let title: String
    let authorNames: [String]
}

/// Resolves the visual cover content used throughout the Books UI.
enum BookCoverContent: Hashable {
    case image(MediaAsset)
    case generated(BookGeneratedCover)

    var mediaAsset: MediaAsset? {
        guard case let .image(asset) = self else { return nil }
        return asset
    }
}

/// Describes book-specific fields that should be changed for a group of books.
struct BookBatchEdit {
    var languageCode: BatchEditValue<String> = .unchanged
    var genre: BatchEditValue<String> = .unchanged
    var pageCount: BatchEditValue<Int> = .unchanged
    var publicationYear: BatchEditValue<Int> = .unchanged
    var contributors: [BookContributorBatchEdit] = []
    var series: BatchEditValue<BookSeries> = .unchanged
    var publisher: BatchEditValue<Publisher> = .unchanged

    var isEmpty: Bool {
        languageCode.isUnchanged
            && genre.isUnchanged
            && pageCount.isUnchanged
            && publicationYear.isUnchanged
            && contributors.isEmpty
            && series.isUnchanged
            && publisher.isUnchanged
    }

    func applying(to details: BookDetails) -> BookDetails {
        var updated = details

        if case .set(let value) = languageCode {
            updated.languageCode = normalized(value)?.lowercased()
        }
        if case .set(let value) = genre {
            updated.genre = normalized(value)
        }
        if case .set(let value) = pageCount {
            updated.pageCount = value
        }
        if case .set(let value) = publicationYear {
            updated.publicationYear = value
        }
        for contributorEdit in contributors {
            updated.contributors = contributorEdit.applying(to: updated.contributors)
        }
        if case .set(let value) = series {
            updated.series = value
        }
        if case .set(let value) = publisher {
            updated.publisher = value
        }

        return updated
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Represents a complete book catalog record.
struct BookRecord: Identifiable, Hashable {
    let item: ItemRecord
    let details: BookDetails

    var id: UUID { item.id }
    var title: String { item.title }
    var collectionID: UUID { item.collectionID }
    var locationID: UUID? { item.locationID }
    var originPlaceID: UUID? { item.originPlaceID }
    var createdAt: Date { item.createdAt }
    var createdBy: String { item.createdBy }
    var notes: String { item.notes }
    var acquiredYear: Int? { item.acquiredYear }
    var condition: ItemCondition { item.condition }
    var acquisitionMethod: AcquisitionMethod { item.acquisitionMethod }
    var isFavorite: Bool { item.isFavorite }
    var tags: [String] { item.tags }
    var originPlace: Place? { item.originPlace }
    var storageLocation: Location? { item.storageLocation }
    var storagePath: StoragePath? { item.storagePath }
    var mediaAssets: [MediaAsset] { item.mediaAssets }

    var authorNames: [String] {
        details.contributors
            .filter { $0.role == .author }
            .sorted { $0.order < $1.order }
            .map(\.person.displayName)
    }

    var cover: BookCoverContent {
        if let coverImage = details.coverImage {
            return .image(coverImage, source: .dedicated)
        }

        if let legacyCover = mediaAssets
            .filter({ $0.kind == .photo })
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .first {
            return .image(legacyCover, source: .legacyMedia)
        }

        return .generated(
            BookGeneratedCover(
                bookID: id,
                title: title,
                authorNames: authorNames
            )
        )
    }

    var photoCount: Int { mediaAssets.filter { $0.kind == .photo }.count }
    var documentCount: Int { mediaAssets.filter { $0.kind == .document }.count }
}

extension BookRecord {
    func moving(
        to location: Location?,
        storagePath: StoragePath?
    ) -> BookRecord {
        var updatedItem = item
        updatedItem.setStorageLocation(location, path: storagePath)
        return BookRecord(item: updatedItem, details: details)
    }
}
