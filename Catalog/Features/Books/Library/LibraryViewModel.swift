import Foundation
import Combine

/// Defines the supported ordering modes for a book library.
enum LibraryOrderMode: String, CaseIterable {
    case title
    case author
    case publisher
    case publicationYearNewest
    case newestFirst
    case series
    case storage

    var title: String {
        switch self {
        case .title:
            return String(localized: "Title")
        case .author:
            return String(localized: "Author")
        case .publisher:
            return String(localized: "Publisher")
        case .publicationYearNewest:
            return String(localized: "Publication year")
        case .newestFirst:
            return String(localized: "sort.newest_first")
        case .series:
            return String(localized: "Series")
        case .storage:
            return String(localized: "common.storage")
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
    var filters: BookFilters
    @Published private(set) var displayModel: LibraryDisplayModel

    private var sourceBooks: [BookRecord]?
    private var sourceSeries: [BookSeries]?

    init(
        orderMode: LibraryOrderMode,
        filters: BookFilters = BookFilters()
    ) {
        self.orderMode = orderMode
        self.filters = filters
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

        let filteredBooks = filteredBooks(from: books, series: series)
        let layout: LibraryLayout
        if filteredBooks.isEmpty {
            layout = .empty
        } else {
            switch orderMode {
            case .title:
                layout = .grouped(titleSections(books: filteredBooks))
            case .author:
                layout = .grouped(authorSections(books: filteredBooks))
            case .publisher:
                layout = .grouped(publisherSections(books: filteredBooks))
            case .publicationYearNewest:
                layout = .grouped(publicationYearSections(books: filteredBooks))
            case .newestFirst:
                layout = .flat(sorted(filteredBooks))
            case .series:
                layout = .grouped(seriesSections(books: filteredBooks, series: series))
            case .storage:
                layout = .grouped(storageSections(books: filteredBooks))
            }
        }

        displayModel = LibraryDisplayModel(
            layout: layout,
            favoriteBooks: books.filter(\.isFavorite),
            stats: buildStats(books: books, series: series)
        )
    }

    func updateContext(orderMode: LibraryOrderMode) {
        guard self.orderMode != orderMode else { return }
        self.orderMode = orderMode
        refreshSource()
    }

    func updateContext(filters: BookFilters) {
        guard self.filters != filters else { return }
        self.filters = filters
        refreshSource()
    }

    private func refreshSource() {
        guard let sourceBooks, let sourceSeries else { return }
        updateSource(books: sourceBooks, series: sourceSeries)
    }

    private func filteredBooks(
        from books: [BookRecord],
        series: [BookSeries]
    ) -> [BookRecord] {
        guard !filters.isEmpty else { return books }

        let seriesByID = Dictionary(uniqueKeysWithValues: series.map { ($0.id, $0) })
        let ownedCountBySeriesID = Dictionary(
            books.compactMap { book -> (UUID, Int)? in
                guard let seriesID = book.details.series?.id else { return nil }
                return (seriesID, 1)
            },
            uniquingKeysWith: +
        )

        return books.filter { book in
            filters.presence.allSatisfy { filter in
                switch filter {
                case .missingCover:
                    return !hasCover(book)
                case .missingAuthor:
                    return !hasAuthor(book)
                case .missingPublicationYear:
                    return book.details.publicationYear == nil
                case .incompleteSeries:
                    guard
                        let seriesID = book.details.series?.id,
                        let bookSeries = seriesByID[seriesID] ?? book.details.series,
                        let totalBookCount = bookSeries.totalBookCount,
                        totalBookCount > 0
                    else {
                        return false
                    }

                    return (ownedCountBySeriesID[seriesID] ?? 0) < totalBookCount
                case .unknownSeriesSize:
                    guard
                        let seriesID = book.details.series?.id,
                        let bookSeries = seriesByID[seriesID] ?? book.details.series
                    else {
                        return false
                    }

                    guard let totalBookCount = bookSeries.totalBookCount else {
                        return true
                    }
                    return totalBookCount <= 0
                }
            }
        }
    }

    private func sorted(_ books: [BookRecord]) -> [BookRecord] {
        switch orderMode {
        case .title:
            return books.sorted(by: titleLessThan)
        case .author:
            return books.sorted(by: authorLessThan)
        case .publisher:
            return books.sorted(by: publisherLessThan)
        case .publicationYearNewest:
            return books.sorted(by: publicationYearLessThan)
        case .newestFirst:
            return books.sorted(using: newestFirstComparators)
        case .series:
            return books
        case .storage:
            return CatalogStorageGrouping.sorted(
                books,
                storagePath: { $0.storagePath },
                title: { $0.title }
            )
        }
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
                    title: String(localized: "No Title"),
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
                    title: String(localized: "No Author"),
                    detailText: nil,
                    indexTitle: nil,
                    books: sectionBooks.sorted(by: titleLessThan),
                    subgroups: []
                )
            }
        }
    }

    private func publisherSections(books: [BookRecord]) -> [LibraryGroupedSection] {
        let grouped = Dictionary(grouping: books, by: { $0.details.publisher?.id })
        let orderedKeys = grouped.keys.sorted { lhsID, rhsID in
            let lhsPublisher = grouped[lhsID]?.first?.details.publisher
            let rhsPublisher = grouped[rhsID]?.first?.details.publisher
            return comparePublishers(lhsPublisher, rhsPublisher) == .orderedAscending
        }

        return orderedKeys.map { publisherID in
            let sectionBooks = grouped[publisherID, default: []].sorted(by: titleLessThan)

            guard let publisher = sectionBooks.first?.details.publisher else {
                return LibraryGroupedSection(
                    id: "publisher-none",
                    title: String(localized: "No Publisher"),
                    detailText: nil,
                    indexTitle: nil,
                    books: sectionBooks,
                    subgroups: []
                )
            }

            return LibraryGroupedSection(
                id: "publisher-\(publisher.id.uuidString)",
                title: publisher.name,
                detailText: nil,
                indexTitle: nil,
                books: sectionBooks,
                subgroups: []
            )
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
                    title: String(localized: "No Series"),
                    detailText: CollectionKind.bookCountLabel(for: sectionBooks.count),
                    indexTitle: nil,
                    books: sectionBooks.sorted(by: titleLessThan),
                    subgroups: []
                )
            }

            let progressText: String
            if let totalBookCount = bookSeries.totalBookCount, totalBookCount > 0 {
                progressText = String(localized: "\(sectionBooks.count) of \(totalBookCount)")
            } else {
                progressText = String(localized: "\(sectionBooks.count) owned")
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

    private func storageSections(books: [BookRecord]) -> [LibraryGroupedSection] {
        let sortedBooks = CatalogStorageGrouping.sorted(
            books,
            storagePath: { $0.storagePath },
            title: { $0.title }
        )

        return CatalogStorageGrouping.sections(
            fromSorted: sortedBooks,
            storagePath: { $0.storagePath }
        ).map { section in
            let sectionID = storageSectionID(
                floor: section.floor,
                room: section.room
            )
            let title = section.pathComponents.isEmpty
                ? String(localized: "common.unknown")
                : section.pathComponents.joined(separator: " · ")
            let subgroups = section.subgroups.map { subgroup in
                LibraryBookSubgroup(
                    id: "\(sectionID)-\(subgroup.kind.rawValue):\(storageIDComponent(subgroup.title))",
                    title: subgroup.title,
                    books: subgroup.elements
                )
            }

            return LibraryGroupedSection(
                id: sectionID,
                title: title,
                detailText: nil,
                indexTitle: nil,
                books: section.elements,
                subgroups: subgroups
            )
        }
    }

    private func storageSectionID(floor: String?, room: String?) -> String {
        "storage-floor:\(storageIDComponent(floor))-room:\(storageIDComponent(room))"
    }

    private func storageIDComponent(_ value: String?) -> String {
        value.map { "value:\($0)" } ?? "nil"
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

    private func publisherLessThan(_ lhs: BookRecord, _ rhs: BookRecord) -> Bool {
        let result = comparePublishers(lhs.details.publisher, rhs.details.publisher)
        if result == .orderedSame {
            return titleLessThan(lhs, rhs)
        }
        return result == .orderedAscending
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

    private func comparePublishers(_ lhs: Publisher?, _ rhs: Publisher?) -> ComparisonResult {
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
