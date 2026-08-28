import Foundation

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
    var presence: Set<BookPresenceFilter> = []

    var isEmpty: Bool {
        presence.isEmpty
    }
}
