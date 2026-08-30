import Foundation

/// Defines the supported stable value tokens for book search and filtering.
enum BookSearchToken: Identifiable, Hashable {
    case library(UUID)
    case person(UUID)
    case publisher(UUID)
    case series(UUID)
    case language(String)
    case genre(String)
    case tag(String)

    enum Category: Hashable {
        case library
        case person
        case publisher
        case series
        case language
        case genre
        case tag
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
        }
    }

    func matches(_ book: BookRecord) -> Bool {
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
        }
    }

    static func matches(_ tokens: [BookSearchToken], book: BookRecord) -> Bool {
        let groupedTokens = Dictionary(grouping: tokens, by: \.category)
        return groupedTokens.values.allSatisfy { group in
            group.contains { $0.matches(book) }
        }
    }

    static func matches(_ tokens: Set<BookSearchToken>, book: BookRecord) -> Bool {
        matches(Array(tokens), book: book)
    }
}

/// Defines the supported presence filters for a book library.
enum BookPresenceFilter: Hashable {
    case missingCover
    case missingAuthor
    case missingPublicationYear
    case incompleteSeries
    case unknownSeriesSize
}

/// Represents active filters applied to a book library.
struct BookFilters: Hashable {
    var tokens: Set<BookSearchToken> = []
    var publicationYears: Set<Int> = []
    var acquiredYears: Set<Int> = []
    var conditions: Set<ItemCondition> = []
    var acquisitionMethods: Set<AcquisitionMethod> = []
    var presence: Set<BookPresenceFilter> = []

    var isEmpty: Bool {
        tokens.isEmpty
            && publicationYears.isEmpty
            && acquiredYears.isEmpty
            && conditions.isEmpty
            && acquisitionMethods.isEmpty
            && presence.isEmpty
    }
}

private func normalized(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
}
