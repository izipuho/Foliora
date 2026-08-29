import SwiftUI

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

    private var sortedBooks: [BookRecord] {
        books.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    var body: some View {
        CatalogCardGrid(
            layoutMode: .compact,
            usesGridLayout: false
        ) { cardSize, gridMetrics, cardMetrics in
            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.lg) {
                summaryCard

                if sortedBooks.isEmpty {
                    CatalogEmptyStateView(
                        systemImage: "book.closed",
                        title: "No Books",
                        message: "No books in this library currently use this publisher.",
                        primaryTint: accentColor
                    )
                    .frame(minHeight: 260)
                } else {
                    VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
                        Text("Books")
                            .font(CatalogTypography.sectionTitle)

                        BookGridView(
                            books: sortedBooks,
                            layoutMode: .compact,
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
            if canEditCollection {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingEditor = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Edit Publisher")
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
                    title: "Books",
                    value: String(books.count),
                    systemImage: "book.closed"
                )

                metadataField(
                    title: "Series",
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
        if let logo = publisher.logos
            .filter({ $0.kind == .photo })
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .first {
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
