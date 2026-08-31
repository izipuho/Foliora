import Foundation

/// Defines the supported stable value tokens for book search.
enum BookSearchToken: Identifiable, Hashable {
    case library(UUID)
    case person(UUID)
    case publisher(UUID)
    case series(UUID)
    case language(String)
    case genre(String)
    case tag(String)
    case publicationYear(Int)
    case acquiredYear(Int)
    case condition(ItemCondition)
    case acquisitionMethod(AcquisitionMethod)
    case presence(BookPresenceFilter)

    enum Category: Hashable {
        case library
        case person
        case publisher
        case series
        case language
        case genre
        case tag
        case publicationYear
        case acquiredYear
        case condition
        case acquisitionMethod
        case presence
    }

    var id: String {
        switch self {
        case .library(let id):
            return "library:\(id.uuidString)"
        case .person(let id):
            return "person:\(id.uuidString)"
        case .publisher(let id):
            return "publisher:\(id.uuidString)"
        case .series(let id):
            return "series:\(id.uuidString)"
        case .language(let value):
            return "language:\(normalized(value))"
        case .genre(let value):
            return "genre:\(normalized(value))"
        case .tag(let value):
            return "tag:\(normalized(value))"
        case .publicationYear(let year):
            return "publication-year:\(year)"
        case .acquiredYear(let year):
            return "acquired-year:\(year)"
        case .condition(let condition):
            return "condition:\(condition.rawValue)"
        case .acquisitionMethod(let method):
            return "acquisition:\(method.rawValue)"
        case .presence(let filter):
            return "presence:\(filter.id)"
        }
    }

    var category: Category {
        switch self {
        case .library:
            return .library
        case .person:
            return .person
        case .publisher:
            return .publisher
        case .series:
            return .series
        case .language:
            return .language
        case .genre:
            return .genre
        case .tag:
            return .tag
        case .publicationYear:
            return .publicationYear
        case .acquiredYear:
            return .acquiredYear
        case .condition:
            return .condition
        case .acquisitionMethod:
            return .acquisitionMethod
        case .presence:
            return .presence
        }
    }

    func matches(_ book: BookRecord, allBooks: [BookRecord]) -> Bool {
        switch self {
        case .library(let libraryID):
            return book.collectionID == libraryID
        case .person(let personID):
            return book.details.contributors.contains { $0.person.id == personID }
        case .publisher(let publisherID):
            return book.details.publisher?.id == publisherID
        case .series(let seriesID):
            return book.details.series?.id == seriesID
        case .language(let language):
            guard let bookLanguage = book.details.languageCode else { return false }
            return normalized(bookLanguage) == normalized(language)
        case .genre(let genre):
            guard let bookGenre = book.details.genre else { return false }
            return normalized(bookGenre) == normalized(genre)
        case .tag(let tag):
            return book.tags.contains { normalized($0) == normalized(tag) }
        case .publicationYear(let year):
            return book.details.publicationYear == year
        case .acquiredYear(let year):
            return book.acquiredYear == year
        case .condition(let condition):
            return book.condition == condition
        case .acquisitionMethod(let method):
            return book.acquisitionMethod == method
        case .presence(let filter):
            return filter.matches(book, allBooks: allBooks)
        }
    }

    static func matches(_ tokens: [BookSearchToken], book: BookRecord, allBooks: [BookRecord]) -> Bool {
        let groupedTokens = Dictionary(grouping: tokens, by: \.category)
        return groupedTokens.values.allSatisfy { group in
            group.contains { $0.matches(book, allBooks: allBooks) }
        }
    }
}

/// Defines the supported data-health filters for a book library and search.
enum BookPresenceFilter: Hashable {
    case missingCover
    case missingAuthor
    case missingPublicationYear
    case incompleteSeries
    case unknownSeriesSize

    var id: String {
        switch self {
        case .missingCover: return "missing-cover"
        case .missingAuthor: return "missing-author"
        case .missingPublicationYear: return "missing-publication-year"
        case .incompleteSeries: return "incomplete-series"
        case .unknownSeriesSize: return "unknown-series-size"
        }
    }

    var searchTitle: String {
        switch self {
        case .missingCover: return String(localized: "library.health.missing_cover")
        case .missingAuthor: return String(localized: "library.health.missing_author")
        case .missingPublicationYear: return String(localized: "library.health.missing_publication_year")
        case .incompleteSeries: return String(localized: "library.health.incomplete_series")
        case .unknownSeriesSize: return String(localized: "library.health.series_size_unknown")
        }
    }

    func matches(_ book: BookRecord, allBooks: [BookRecord]) -> Bool {
        switch self {
        case .missingCover:
            return !book.mediaAssets.contains { $0.kind == .photo }
        case .missingAuthor:
            return !book.details.contributors.contains {
                $0.role == .author
                    && !$0.person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        case .missingPublicationYear:
            return book.details.publicationYear == nil
        case .incompleteSeries:
            guard
                let series = book.details.series,
                let totalBookCount = series.totalBookCount,
                totalBookCount > 0
            else {
                return false
            }

            let ownedCount = allBooks.filter {
                $0.collectionID == book.collectionID
                    && $0.details.series?.id == series.id
            }.count
            return ownedCount < totalBookCount
        case .unknownSeriesSize:
            guard let series = book.details.series else { return false }
            guard let totalBookCount = series.totalBookCount else { return true }
            return totalBookCount <= 0
        }
    }
}

/// Represents active quick filters applied directly to a book library.
struct BookFilters: Hashable {
    var presence: Set<BookPresenceFilter> = []

    var isEmpty: Bool {
        presence.isEmpty
    }
}

private func normalized(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
}
