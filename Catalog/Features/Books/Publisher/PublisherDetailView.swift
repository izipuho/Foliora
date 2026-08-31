import SwiftUI

private enum PublisherBookOrderMode: String, CaseIterable, Hashable {
    case title
    case author
    case publicationYearNewest
    case newestFirst

    var title: String {
        switch self {
        case .title:
            return String(localized: "common.field_title")
        case .author:
            return String(localized: "book.field.author")
        case .publicationYearNewest:
            return String(localized: "book.field.publication_year")
        case .newestFirst:
            return String(localized: "sort.newest_first")
        }
    }
}

/// Displays a publisher and the books from the current library published by it.
struct PublisherDetailView: View {
    @State private var publisher: Publisher
    let books: [BookRecord]
    let series: [BookSeries]
    let allBookCount: Int
    let allSeriesCount: Int
    let places: [Place]
    let repository: any CatalogRepository
    let canEditCollection: Bool
    let accentColor: Color
    let onPublisherSaved: (Publisher) -> Void
    let onPublisherDeleted: (UUID) -> Void
    let onBookSelected: ((UUID) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @AppStorage("bookPublisher.orderMode") private var selectedOrderRawValue = PublisherBookOrderMode.title.rawValue
    @AppStorage("bellCatalog.layoutMode") private var layoutModeRawValue = CatalogCardLayoutMode.mini.rawValue
    @State private var isPresentingEditor = false

    init(
        publisher: Publisher,
        books: [BookRecord],
        series: [BookSeries],
        allBookCount: Int,
        allSeriesCount: Int,
        places: [Place],
        repository: any CatalogRepository,
        canEditCollection: Bool,
        accentColor: Color,
        onPublisherSaved: @escaping (Publisher) -> Void,
        onPublisherDeleted: @escaping (UUID) -> Void,
        onBookSelected: ((UUID) -> Void)? = nil
    ) {
        _publisher = State(initialValue: publisher)
        self.books = books
        self.series = series
        self.allBookCount = allBookCount
        self.allSeriesCount = allSeriesCount
        self.places = places
        self.repository = repository
        self.canEditCollection = canEditCollection
        self.accentColor = accentColor
        self.onPublisherSaved = onPublisherSaved
        self.onPublisherDeleted = onPublisherDeleted
        self.onBookSelected = onBookSelected
    }

    private var selectedOrder: PublisherBookOrderMode {
        get { PublisherBookOrderMode(rawValue: selectedOrderRawValue) ?? .title }
        nonmutating set { selectedOrderRawValue = newValue.rawValue }
    }

    private var selectedOrderBinding: Binding<PublisherBookOrderMode> {
        Binding(
            get: { selectedOrder },
            set: { selectedOrder = $0 }
        )
    }

    private var layoutMode: CatalogCardLayoutMode {
        get { CatalogCardLayoutMode(rawValue: layoutModeRawValue) ?? .mini }
        nonmutating set { layoutModeRawValue = newValue.rawValue }
    }

    private var layoutModeBinding: Binding<CatalogCardLayoutMode> {
        Binding(
            get: { layoutMode },
            set: { layoutMode = $0 }
        )
    }

    private var sortedBooks: [BookRecord] {
        switch selectedOrder {
        case .title:
            return books.sorted(by: titleLessThan)
        case .author:
            return books.sorted(by: authorLessThan)
        case .publicationYearNewest:
            return books.sorted(by: publicationYearLessThan)
        case .newestFirst:
            return books.sorted {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt > $1.createdAt
                }
                return titleLessThan($0, $1)
            }
        }
    }

    var body: some View {
        CatalogCardGrid(
            layoutMode: layoutMode,
            usesGridLayout: false
        ) { cardSize, gridMetrics, cardMetrics in
            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.lg) {
                summaryCard

                if sortedBooks.isEmpty {
                    CatalogEmptyStateView(
                        systemImage: "book.closed",
                        title: "library.empty.books.title",
                        message: "publisher.detail.empty_books.message",
                        primaryTint: accentColor
                    )
                    .frame(minHeight: 260)
                } else {
                    VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
                        Text("common.books")
                            .font(CatalogTypography.sectionTitle)

                        BookGridView(
                            books: sortedBooks,
                            layoutMode: layoutMode,
                            layoutMetrics: (cardSize, gridMetrics, cardMetrics),
                            onBookSelected: onBookSelected
                        )
                    }
                }
            }
            .padding(.horizontal, CatalogMetrics.Insets.screen)
            .padding(.vertical, CatalogMetrics.Spacing.lg)
        }
        .background {
            CatalogBackgrounds.collection(accentColor, scheme: colorScheme)
                .ignoresSafeArea()
        }
        .navigationTitle(publisher.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            CatalogSortLayoutToolbar(
                selectedSort: selectedOrderBinding,
                selectedLayoutMode: layoutModeBinding,
                sortOptions: PublisherBookOrderMode.allCases,
                sortSectionTitle: String(localized: "common.sort"),
                sortTitle: { $0.title }
            )
            
            if canEditCollection {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingEditor = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("publisher.action.edit")
                }
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            PublisherEditorView(
                publisher: publisher,
                places: places,
                bookCount: allBookCount,
                seriesCount: allSeriesCount,
                onDelete: {
                    (repository as! any BookCatalogRepository).deletePublisher(publisherID: publisher.id)
                    onPublisherDeleted(publisher.id)
                    isPresentingEditor = false
                    dismiss()
                }
            ) { updatedPublisher in
                (repository as! any BookCatalogRepository).savePublisher(updatedPublisher)
                publisher = updatedPublisher
                onPublisherSaved(updatedPublisher)
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.lg) {
            HStack(alignment: .center, spacing: CatalogMetrics.Spacing.md) {
                publisherMark

                VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                    Text(publisher.name)
                        .font(CatalogTypography.cardTitle)

                    if let location = publisher.location {
                        Text(location.displayName)
                            .font(CatalogTypography.cardSubtitle)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack(alignment: .top, spacing: CatalogMetrics.Spacing.lg) {
                metadataField(
                    title: String(localized: "common.books"),
                    value: String(books.count),
                    systemImage: "book.closed"
                )

                metadataField(
                    title: String(localized: "series.title"),
                    value: String(series.count),
                    systemImage: "rectangle.stack"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CatalogMetrics.Spacing.lg)
        .background {
            CatalogShapes.section
                .fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var publisherMark: some View {
        if let logo = publisher.logo, logo.kind == .photo {
            MediaPreviewImage(
                identifier: logo.localIdentifier,
                originalData: logo.originalData,
                size: CGSize(width: 60, height: 60)
            )
            .frame(width: 60, height: 60)
            .clipShape(CatalogShapes.tile)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.medium, style: .continuous)
                    .fill(accentColor.opacity(0.14))
                    .frame(width: 60, height: 60)

                Image(systemName: "building.2.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(accentColor)
            }
        }
    }

    private func metadataField(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
            Label(title, systemImage: systemImage)
                .font(CatalogTypography.cardSubtitle)
                .foregroundStyle(.secondary)

            Text(value)
                .font(CatalogTypography.cardLabel)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        switch (lhs.details.publicationYear, rhs.details.publicationYear) {
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
}

#if DEBUG
#Preview {
    let container = PreviewContainer.makeBooksMinimal()
    let repository = CoreDataCatalogRepository(
        context: container.viewContext,
        persistentContainer: nil
    )
    let snapshot = CatalogSnapshot.load(from: container.viewContext)

    if let publisher = snapshot.publishers.first,
       let collection = snapshot.collections
        .compactMap({ snapshot.collectionSummary(id: $0.id) })
        .first(where: { $0.kind == .books }) {
        NavigationStack {
            PublisherDetailView(
                publisher: publisher,
                books: snapshot.bookRecords.filter {
                    $0.collectionID == collection.id && $0.details.publisher?.id == publisher.id
                },
                series: snapshot.bookSeries.filter {
                    $0.collectionID == collection.id && $0.publisher?.id == publisher.id
                },
                allBookCount: snapshot.bookRecords.filter { $0.details.publisher?.id == publisher.id }.count,
                allSeriesCount: snapshot.bookSeries.filter { $0.publisher?.id == publisher.id }.count,
                places: snapshot.places,
                repository: repository,
                canEditCollection: true,
                accentColor: collection.backgroundStyle.accentColor,
                onPublisherSaved: { _ in },
                onPublisherDeleted: { _ in }
            )
        }
        .environment(\.managedObjectContext, container.viewContext)
    }
}
#endif
