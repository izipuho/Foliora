import Foundation
import Combine

/// Defines the supported ordering modes for a book library.
enum LibraryOrderMode: String, CaseIterable {
    case title
    case author
    case publicationYearNewest
    case newestFirst = "recentlyAdded"
    case series

    var title: String {
        switch self {
        case .title:
            return "Title"
        case .author:
            return "Author"
        case .publicationYearNewest:
            return "Publication year"
        case .newestFirst:
            return "Newest first"
        case .series:
            return "Series"
        }
    }
}

/// Represents the layout rendered by a book library.
enum LibraryLayout {
    case empty
    case flat([BookRecord])
    case grouped([LibraryGroupedSection])

    var isGrouped: Bool {
        if case .grouped = self {
            return true
        }
        return false
    }
}

/// Represents a grouped book library section.
struct LibraryGroupedSection: Identifiable {
    let id: String
    let title: String
    let detailText: String?
    let indexTitle: String?
    let books: [BookRecord]
    let subgroups: [LibraryBookSubgroup]
}

/// Represents a nested group of books inside a library section.
struct LibraryBookSubgroup: Identifiable {
    let id: String
    let title: String
    let books: [BookRecord]
}

private enum AlphabetGroupKey: Hashable {
    case initial(String)
    case noValue
}

/// Represents the content rendered by a book library.
struct LibraryDisplayModel {
    let layout: LibraryLayout
    let favoriteBooks: [BookRecord]
    let stats: LibraryStats
}

/// Represents aggregate book library statistics used by the dashboard.
struct LibraryStats {
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
final class LibraryViewModel: ObservableObject {
    var orderMode: LibraryOrderMode
    @Published private(set) var displayModel: LibraryDisplayModel

    private var sourceBooks: [BookRecord]?
    private var sourceSeries: [BookSeries]?

    init(orderMode: LibraryOrderMode) {
        self.orderMode = orderMode
        self.displayModel = LibraryDisplayModel(
            layout: .empty,
            favoriteBooks: [],
            stats: LibraryStats(
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

        let layout: LibraryLayout
        if books.isEmpty {
            layout = .empty
        } else {
            switch orderMode {
            case .title:
                layout = .grouped(titleSections(books: books))
            case .author:
                layout = .grouped(authorSections(books: books))
            case .publicationYearNewest:
                layout = .grouped(publicationYearSections(books: books))
            case .newestFirst:
                layout = .flat(sorted(books))
            case .series:
                layout = .grouped(seriesSections(books: books, series: series))
            }
        }

        displayModel = LibraryDisplayModel(
            layout: layout,
            favoriteBooks: sortedFavorites(books.filter(\.isFavorite), series: series),
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
            return books.sorted(by: titleLessThan)
        case .author:
            return books.sorted(by: authorLessThan)
        case .publicationYearNewest:
            return books.sorted(by: publicationYearLessThan)
        case .newestFirst:
            return books.sorted(using: newestFirstComparators)
        case .series:
            return books
        }
    }

    private func sortedFavorites(
        _ books: [BookRecord],
        series: [BookSeries]
    ) -> [BookRecord] {
        guard orderMode == .series else {
            return sorted(books)
        }

        let seriesByID = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
        return books.sorted(by: { lhs, rhs in
            let lhsSeries = (lhs.details.series?.id).flatMap { seriesByID[$0] } ?? lhs.details.series
            let rhsSeries = (rhs.details.series?.id).flatMap { seriesByID[$0] } ?? rhs.details.series
            let seriesComparison = compareSeries(lhsSeries, rhsSeries)

            if seriesComparison != .orderedSame {
                return seriesComparison == .orderedAscending
            }

            return volumeLessThan(lhs, rhs)
        })
    }

    private func titleSections(books: [BookRecord]) -> [LibraryGroupedSection] {
        let sortedBooks = books.sorted(by: titleLessThan)
        let grouped = Dictionary(grouping: sortedBooks, by: titleGroupKey)
        let orderedKeys = grouped.keys.sorted(by: alphabetGroupLessThan)

        return orderedKeys.map { key in
            let sectionBooks = grouped[key, default: []]

            switch key {
            case .initial(let initial):
                return LibraryGroupedSection(
                    id: "title-\(initial)",
                    title: initial,
                    detailText: nil,
                    indexTitle: initial,
                    books: sectionBooks,
                    subgroups: []
                )
            case .noValue:
                return LibraryGroupedSection(
                    id: "title-none",
                    title: "No Title",
                    detailText: nil,
                    indexTitle: nil,
                    books: sectionBooks,
                    subgroups: []
                )
            }
        }
    }

    private func authorSections(books: [BookRecord]) -> [LibraryGroupedSection] {
        let sortedBooks = books.sorted(by: authorLessThan)
        let grouped = Dictionary(grouping: sortedBooks, by: authorGroupKey)
        let orderedKeys = grouped.keys.sorted(by: alphabetGroupLessThan)

        return orderedKeys.map { key in
            let sectionBooks = grouped[key, default: []]

            switch key {
            case .initial(let initial):
                let booksByAuthor = Dictionary(grouping: sectionBooks, by: authorDisplayName)
                let authorNames = booksByAuthor.keys.sorted {
                    $0.localizedStandardCompare($1) == .orderedAscending
                }
                let subgroups = authorNames.map { authorName in
                    LibraryBookSubgroup(
                        id: "author-\(initial)-\(authorName)",
                        title: authorName,
                        books: booksByAuthor[authorName, default: []].sorted(by: titleLessThan)
                    )
                }

                return LibraryGroupedSection(
                    id: "author-\(initial)",
                    title: initial,
                    detailText: nil,
                    indexTitle: initial,
                    books: [],
                    subgroups: subgroups
                )
            case .noValue:
                return LibraryGroupedSection(
                    id: "author-none",
                    title: "No Author",
                    detailText: nil,
                    indexTitle: nil,
                    books: sectionBooks.sorted(by: titleLessThan),
                    subgroups: []
                )
            }
        }
    }

    private func publicationYearSections(books: [BookRecord]) -> [LibraryGroupedSection] {
        CatalogYearGrouping.descending(
            books,
            year: { $0.details.publicationYear },
            sortedBy: titleLessThan
        ).map { group in
            LibraryGroupedSection(
                id: group.year.map { "year-\($0)" } ?? "year-unknown",
                title: group.year.map(String.init) ?? String(localized: "common.unknown"),
                detailText: nil,
                indexTitle: nil,
                books: group.elements,
                subgroups: []
            )
        }
    }

    private func titleGroupKey(for book: BookRecord) -> AlphabetGroupKey {
        let title = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstCharacter = title.first else {
            return .noValue
        }

        return .initial(String(firstCharacter).uppercased())
    }

    private func authorGroupKey(for book: BookRecord) -> AlphabetGroupKey {
        let author = authorDisplayName(for: book)
        guard let firstCharacter = author.first else {
            return .noValue
        }

        return .initial(String(firstCharacter).uppercased())
    }

    private func alphabetGroupLessThan(_ lhs: AlphabetGroupKey, _ rhs: AlphabetGroupKey) -> Bool {
        switch (lhs, rhs) {
        case let (.initial(lhsInitial), .initial(rhsInitial)):
            return lhsInitial.localizedStandardCompare(rhsInitial) == .orderedAscending
        case (.initial, .noValue):
            return true
        case (.noValue, .initial):
            return false
        case (.noValue, .noValue):
            return false
        }
    }

    private func seriesSections(
        books: [BookRecord],
        series: [BookSeries]
    ) -> [LibraryGroupedSection] {
        let seriesByID = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
        let grouped = Dictionary(grouping: books, by: { $0.details.series?.id })
        let orderedKeys = grouped.keys.sorted { lhsID, rhsID in
            let lhsSeries = lhsID.flatMap { seriesByID[$0] }
                ?? grouped[lhsID]?.first?.details.series
            let rhsSeries = rhsID.flatMap { seriesByID[$0] }
                ?? grouped[rhsID]?.first?.details.series
            return compareSeries(lhsSeries, rhsSeries) == .orderedAscending
        }

        return orderedKeys.map { seriesID in
            let sectionBooks = grouped[seriesID, default: []].sorted(by: volumeLessThan)

            guard let bookSeries = seriesID.flatMap({ seriesByID[$0] })
                ?? sectionBooks.first?.details.series else {
                return LibraryGroupedSection(
                    id: "series-none",
                    title: "No Series",
                    detailText: "\(sectionBooks.count) books",
                    indexTitle: nil,
                    books: sectionBooks.sorted(by: titleLessThan),
                    subgroups: []
                )
            }

            let progressText: String
            if let totalBookCount = bookSeries.totalBookCount, totalBookCount > 0 {
                progressText = "\(sectionBooks.count) of \(totalBookCount)"
            } else {
                progressText = "\(sectionBooks.count) owned"
            }

            return LibraryGroupedSection(
                id: "series-\(bookSeries.id.uuidString)",
                title: bookSeries.name,
                detailText: progressText,
                indexTitle: nil,
                books: sectionBooks,
                subgroups: []
            )
        }
    }

    private func titleLessThan(_ lhs: BookRecord, _ rhs: BookRecord) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func authorLessThan(_ lhs: BookRecord, _ rhs: BookRecord) -> Bool {
        let lhsAuthor = authorDisplayName(for: lhs)
        let rhsAuthor = authorDisplayName(for: rhs)

        if lhsAuthor == rhsAuthor {
            return titleLessThan(lhs, rhs)
        }

        if lhsAuthor.isEmpty { return false }
        if rhsAuthor.isEmpty { return true }
        return lhsAuthor.localizedStandardCompare(rhsAuthor) == .orderedAscending
    }

    private func publicationYearLessThan(_ lhs: BookRecord, _ rhs: BookRecord) -> Bool {
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
            return titleLessThan(lhs, rhs)
        }
    }

    private func volumeLessThan(_ lhs: BookRecord, _ rhs: BookRecord) -> Bool {
        switch (lhs.details.volumeNumber, rhs.details.volumeNumber) {
        case let (.some(lhsVolume), .some(rhsVolume)) where lhsVolume != rhsVolume:
            return lhsVolume < rhsVolume
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return titleLessThan(lhs, rhs)
        }
    }

    private func compareSeries(_ lhs: BookSeries?, _ rhs: BookSeries?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
            if nameComparison != .orderedSame {
                return nameComparison
            }
            return lhs.id.uuidString.compare(rhs.id.uuidString)
        case (.some, .none):
            return .orderedAscending
        case (.none, .some):
            return .orderedDescending
        case (.none, .none):
            return .orderedSame
        }
    }

    private var newestFirstComparators: [KeyPathComparator<BookRecord>] {
        [
            KeyPathComparator(\.createdAt, order: .reverse),
            titleComparator
        ]
    }

    private var titleComparator: KeyPathComparator<BookRecord> {
        KeyPathComparator(\.title, comparator: .localizedStandard)
    }

    private func buildStats(
        books: [BookRecord],
        series: [BookSeries]
    ) -> LibraryStats {
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

        return LibraryStats(
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

    private func authorDisplayName(for book: BookRecord) -> String {
        book.details.contributors
            .filter { $0.role == .author }
            .sorted { lhs, rhs in
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return lhs.person.name.localizedStandardCompare(rhs.person.name) == .orderedAscending
            }
            .map { $0.person.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
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
        !authorDisplayName(for: book).isEmpty
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
