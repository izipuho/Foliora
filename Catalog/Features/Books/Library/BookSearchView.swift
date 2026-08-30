import SwiftUI
import CoreData

struct BookSearchView: View {
    let catalogSnapshot: CatalogSnapshot?
    let onBookSelected: ((UUID) -> Void)?
    @Binding var layoutMode: CatalogCardLayoutMode
    @State private var query = ""
    @State private var tokens: [BookSearchToken] = []

    private let initialQuery: String?

    init(
        layoutMode: Binding<CatalogCardLayoutMode>,
        catalogSnapshot: CatalogSnapshot?,
        initialQuery: String? = nil,
        onBookSelected: ((UUID) -> Void)? = nil
    ) {
        self._layoutMode = layoutMode
        self.catalogSnapshot = catalogSnapshot
        self.initialQuery = initialQuery
        self.onBookSelected = onBookSelected
    }

    private var books: [BookRecord] {
        catalogSnapshot?.bookRecords ?? []
    }

    private var libraries: [Collection] {
        (catalogSnapshot?.collections ?? [])
            .filter { $0.kind == .books }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var libraryTitlesByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: libraries.map { ($0.id, $0.title) })
    }

    private var peopleByID: [UUID: Person] {
        Dictionary(
            books
                .flatMap { $0.details.contributors.map(\.person) }
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var publishersByID: [UUID: Publisher] {
        Dictionary(
            books.compactMap(\.details.publisher).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var seriesByID: [UUID: BookSeries] {
        Dictionary(
            books.compactMap(\.details.series).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var suggestedTokenGroups: [SearchTokenGroup<BookSearchToken>] {
        let selectedTokens = Set(tokens)

        return [
            SearchTokenGroup(
                title: "Libraries",
                systemImage: "rectangle.stack",
                tokens: libraries.map { .library($0.id) }
            ),
            SearchTokenGroup(
                title: "People",
                systemImage: "person.text.rectangle",
                tokens: peopleByID.values
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    .map { .person($0.id) }
            ),
            SearchTokenGroup(
                title: "Publishers",
                systemImage: "building.2",
                tokens: publishersByID.values
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    .map { .publisher($0.id) }
            ),
            SearchTokenGroup(
                title: "Series",
                systemImage: "books.vertical",
                tokens: seriesByID.values
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    .map { .series($0.id) }
            ),
            SearchTokenGroup(
                title: "Languages",
                systemImage: "character.book.closed",
                tokens: uniqueValues(books.compactMap(\.details.languageCode)).map(BookSearchToken.language)
            ),
            SearchTokenGroup(
                title: "Genres",
                systemImage: "text.book.closed",
                tokens: uniqueValues(books.compactMap(\.details.genre)).map(BookSearchToken.genre)
            ),
            SearchTokenGroup(
                title: "Tags",
                systemImage: "tag",
                tokens: uniqueValues(books.flatMap(\.tags)).map(BookSearchToken.tag)
            )
        ]
        .map { group in
            SearchTokenGroup(
                title: group.title,
                systemImage: group.systemImage,
                tokens: group.tokens.filter { !selectedTokens.contains($0) }
            )
        }
        .filter { !$0.tokens.isEmpty }
    }

    private var filteredBooks: [BookRecord] {
        books
            .filter { book in
                matchesQuery(query, book: book)
                    && BookSearchToken.matches(tokens, book: book)
            }
            .sorted {
                let titleComparison = $0.title.localizedStandardCompare($1.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    var body: some View {
        SearchShellView(
            layoutMode: $layoutMode,
            query: $query,
            tokens: $tokens,
            suggestedTokenGroups: suggestedTokenGroups,
            initialQuery: initialQuery,
            tokenTitle: tokenTitle,
            tokenSystemImage: tokenSystemImage
        ) { layoutMetrics in
            searchResults(layoutMetrics: layoutMetrics)
        }
    }

    @ViewBuilder
    private func searchResults(layoutMetrics: CatalogCardGrid<AnyView>.LayoutMetrics) -> some View {
        if filteredBooks.isEmpty {
            CatalogEmptyStateView(
                systemImage: "magnifyingglass",
                title: "No Books",
                message: "No books match the current search."
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            BookGridView(
                books: filteredBooks,
                layoutMode: layoutMode,
                layoutMetrics: layoutMetrics,
                onBookSelected: onBookSelected
            )
        }
    }

    private func tokenTitle(_ token: BookSearchToken) -> String {
        switch token {
        case .library(let libraryID):
            return libraryTitlesByID[libraryID] ?? "Library"
        case .person(let personID):
            return peopleByID[personID]?.name ?? "Person"
        case .publisher(let publisherID):
            return publishersByID[publisherID]?.name ?? "Publisher"
        case .series(let seriesID):
            return seriesByID[seriesID]?.name ?? "Series"
        case .language(let languageCode):
            return languageDisplayName(languageCode)
        case .genre(let genre), .tag(let genre):
            return genre
        }
    }

    private func tokenSystemImage(_ token: BookSearchToken) -> String {
        switch token {
        case .library:
            return "rectangle.stack"
        case .person:
            return "person.text.rectangle"
        case .publisher:
            return "building.2"
        case .series:
            return "books.vertical"
        case .language:
            return "character.book.closed"
        case .genre:
            return "text.book.closed"
        case .tag:
            return "tag"
        }
    }

    private func matchesQuery(_ query: String, book: BookRecord) -> Bool {
        let query = normalized(query)
        guard !query.isEmpty else { return true }

        return searchableValues(for: book).contains {
            normalized($0).contains(query)
        }
    }

    private func searchableValues(for book: BookRecord) -> [String] {
        var values = [book.title]

        values += book.details.contributors.map { $0.person.name }
        values += book.tags
        values += book.details.identifiers.flatMap { [$0.value, $0.type.rawValue] }

        if let libraryTitle = libraryTitlesByID[book.collectionID] {
            values.append(libraryTitle)
        }
        if let publisher = book.details.publisher {
            values.append(publisher.name)
        }
        if let series = book.details.series {
            values.append(series.name)
        }
        if let genre = book.details.genre {
            values.append(genre)
        }
        if let languageCode = book.details.languageCode {
            values.append(languageCode)
            values.append(languageDisplayName(languageCode))
        }

        return values
    }

    private func uniqueValues(_ values: [String]) -> [String] {
        var seen: Set<String> = []

        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert(normalized($0)).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func languageDisplayName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

@MainActor
func makeSearchTabContent(
    repository: any CatalogRepository,
    layoutMode: Binding<CatalogCardLayoutMode>,
    catalogSnapshot: CatalogSnapshot?,
    initialQuery: String?,
    onItemSelected: ((UUID) -> Void)?
) -> AnyView {
    AnyView(
        BookSearchView(
            layoutMode: layoutMode,
            catalogSnapshot: catalogSnapshot,
            initialQuery: initialQuery,
            onBookSelected: onItemSelected
        )
    )
}

@MainActor
func makeCollectionDestinationContent(
    collection: CollectionSummary,
    catalogSnapshot: CatalogSnapshot?,
    repository: any CatalogRepository,
    coreDataContainer: NSPersistentCloudKitContainer,
    layoutMode: Binding<CatalogCardLayoutMode>,
    onItemSelected: ((UUID) -> Void)?,
    onBatchAddComplete: @escaping (Any) -> Void
) -> AnyView {
    AnyView(
        LibraryView(
            collection: collection,
            catalogSnapshot: catalogSnapshot,
            repository: repository,
            coreDataContainer: coreDataContainer,
            layoutMode: layoutMode,
            onBookSelected: onItemSelected
        )
    )
}

@MainActor
func makeItemDetailContent(
    itemID: UUID,
    repository: any CatalogRepository,
    catalogSnapshot: CatalogSnapshot?,
    onClose: (() -> Void)?
) -> AnyView {
    AnyView(
        BookDetailContainer(
            bookID: itemID,
            repository: repository,
            catalogSnapshot: catalogSnapshot,
            onClose: onClose
        )
    )
}

#if DEBUG
#Preview {
    let container = PreviewContainer.makeBooksMinimal()
    let snapshot = CatalogSnapshot.load(from: container.viewContext)

    NavigationStack {
        BookSearchView(
            layoutMode: .constant(.compact),
            catalogSnapshot: snapshot
        )
    }
    .environment(\.managedObjectContext, container.viewContext)
}
#endif
