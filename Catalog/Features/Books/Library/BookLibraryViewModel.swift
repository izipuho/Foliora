import Foundation
import Combine

/// Defines the supported ordering modes for a book library.
enum LibraryOrderMode: String, CaseIterable {
    case title
    case author
    case publicationYearNewest

    var title: String {
        switch self {
        case .title:
            return "Title"
        case .author:
            return "Author"
        case .publicationYearNewest:
            return "Publication year"
        }
    }
}

/// Represents the content rendered by a book library.
struct BookLibraryDisplayModel {
    let books: [BookRecord]
    let favoriteBooks: [BookRecord]
    let stats: BookLibraryStats
}

/// Represents aggregate book library statistics used by the dashboard.
struct BookLibraryStats {
    let totalCount: Int
    let authorCount: Int
    let seriesCount: Int
    let languageCount: Int
    let tagCount: Int
    let completeSeriesCount: Int
    let incompleteSeriesCount: Int
    let unknownSeriesCount: Int
    let missingCoverCount: Int
    let missingAuthorCount: Int
    let missingPublicationYearCount: Int
    let dataHealthProgress: Double

    var knownSeriesCount: Int {
        completeSeriesCount + incompleteSeriesCount
    }
}

/// Prepares ordered book library content and dashboard statistics for display.
@MainActor
final class BookLibraryViewModel: ObservableObject {
    var orderMode: LibraryOrderMode
    @Published private(set) var displayModel: BookLibraryDisplayModel

    private var sourceBooks: [BookRecord]?
    private var sourceSeries: [BookSeries]?

    init(orderMode: LibraryOrderMode) {
        self.orderMode = orderMode
        self.displayModel = BookLibraryDisplayModel(
            books: [],
            favoriteBooks: [],
            stats: BookLibraryStats(
                totalCount: 0,
                authorCount: 0,
                seriesCount: 0,
                languageCount: 0,
                tagCount: 0,
                completeSeriesCount: 0,
                incompleteSeriesCount: 0,
                unknownSeriesCount: 0,
                missingCoverCount: 0,
                missingAuthorCount: 0,
                missingPublicationYearCount: 0,
                dataHealthProgress: 0
            )
        )
    }

    func updateSource(
        books: [BookRecord],
        series: [BookSeries]
    ) {
        sourceBooks = books
        sourceSeries = series

        let sortedBooks = sorted(books)
        displayModel = BookLibraryDisplayModel(
            books: sortedBooks,
            favoriteBooks: sortedBooks.filter(\.isFavorite),
            stats: buildStats(books: books, series: series)
        )
    }

    func updateContext(orderMode: LibraryOrderMode) {
        guard self.orderMode != orderMode else { return }
        self.orderMode = orderMode
        refreshSource()
    }

    private func refreshSource() {
        guard let sourceBooks, let sourceSeries else { return }
        updateSource(books: sourceBooks, series: sourceSeries)
    }

    private func sorted(_ books: [BookRecord]) -> [BookRecord] {
        switch orderMode {
        case .title:
            return books.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .author:
            return books.sorted { lhs, rhs in
                let lhsAuthor = primaryAuthorName(for: lhs)
                let rhsAuthor = primaryAuthorName(for: rhs)

                if lhsAuthor == rhsAuthor {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }

                if lhsAuthor.isEmpty { return false }
                if rhsAuthor.isEmpty { return true }
                return lhsAuthor.localizedStandardCompare(rhsAuthor) == .orderedAscending
            }
        case .publicationYearNewest:
            return books.sorted { lhs, rhs in
                let lhsYear = lhs.details.publicationYear
                let rhsYear = rhs.details.publicationYear

                switch (lhsYear, rhsYear) {
                case let (.some(lhsYear), .some(rhsYear)) where lhsYear != rhsYear:
                    return lhsYear > rhsYear
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
        }
    }

    private func buildStats(
        books: [BookRecord],
        series: [BookSeries]
    ) -> BookLibraryStats {
        let completeSeriesCount = series.filter { series in
            guard let totalBookCount = series.totalBookCount, totalBookCount > 0 else { return false }
            return ownedBookCount(for: series, in: books) >= totalBookCount
        }.count
        let incompleteSeriesCount = series.filter { series in
            guard let totalBookCount = series.totalBookCount, totalBookCount > 0 else { return false }
            return ownedBookCount(for: series, in: books) < totalBookCount
        }.count
        let unknownSeriesCount = series.filter { series in
            guard let totalBookCount = series.totalBookCount else { return true }
            return totalBookCount <= 0
        }.count
        let knownSeriesCount = completeSeriesCount + incompleteSeriesCount
        let missingCoverCount = books.filter { !hasCover($0) }.count
        let missingAuthorCount = books.filter { !hasAuthor($0) }.count
        let missingPublicationYearCount = books.filter { $0.details.publicationYear == nil }.count
        let filledBookFields = books.count * 3
            - missingCoverCount
            - missingAuthorCount
            - missingPublicationYearCount
        let totalHealthFields = books.count * 3 + series.count
        let dataHealthProgress = totalHealthFields > 0
            ? Double(filledBookFields + knownSeriesCount) / Double(totalHealthFields)
            : 0

        return BookLibraryStats(
            totalCount: books.count,
            authorCount: authorCount(in: books),
            seriesCount: series.count,
            languageCount: languageCount(in: books),
            tagCount: tagCount(in: books),
            completeSeriesCount: completeSeriesCount,
            incompleteSeriesCount: incompleteSeriesCount,
            unknownSeriesCount: unknownSeriesCount,
            missingCoverCount: missingCoverCount,
            missingAuthorCount: missingAuthorCount,
            missingPublicationYearCount: missingPublicationYearCount,
            dataHealthProgress: dataHealthProgress
        )
    }

    private func primaryAuthorName(for book: BookRecord) -> String {
        book.details.contributors
            .filter { $0.role == .author }
            .sorted { $0.order < $1.order }
            .first?
            .person.name ?? ""
    }

    private func ownedBookCount(
        for series: BookSeries,
        in books: [BookRecord]
    ) -> Int {
        books.filter { $0.details.series?.id == series.id }.count
    }

    private func hasCover(_ book: BookRecord) -> Bool {
        book.mediaAssets.contains { $0.kind == .photo }
    }

    private func hasAuthor(_ book: BookRecord) -> Bool {
        book.details.contributors.contains { contributor in
            contributor.role == .author
                && !contributor.person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func authorCount(in books: [BookRecord]) -> Int {
        Set(
            books.flatMap { book in
                book.details.contributors
                    .filter { $0.role == .author }
                    .map(\.person.id)
            }
        ).count
    }

    private func languageCount(in books: [BookRecord]) -> Int {
        Set(
            books.compactMap { $0.details.languageCode.map(normalizedMetricValue) }
                .filter { !$0.isEmpty }
        ).count
    }

    private func tagCount(in books: [BookRecord]) -> Int {
        Set(
            books.flatMap(\.tags)
                .map(normalizedMetricValue)
                .filter { !$0.isEmpty }
        ).count
    }

    private func normalizedMetricValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}
