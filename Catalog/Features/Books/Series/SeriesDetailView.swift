import SwiftUI

/// Displays a single book series and the books that belong to it.
struct SeriesDetailView: View {
    @State private var series: BookSeries
    let books: [BookRecord]
    let publishers: [Publisher]
    let repository: any CatalogRepository
    let canEditCollection: Bool
    let accentColor: Color
    let onSeriesSaved: (BookSeries) -> Void
    let onBookSelected: ((UUID) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPresentingEditor = false

    init(
        series: BookSeries,
        books: [BookRecord],
        publishers: [Publisher],
        repository: any CatalogRepository,
        canEditCollection: Bool,
        accentColor: Color,
        onSeriesSaved: @escaping (BookSeries) -> Void,
        onBookSelected: ((UUID) -> Void)? = nil
    ) {
        _series = State(initialValue: series)
        self.books = books
        self.publishers = publishers
        self.repository = repository
        self.canEditCollection = canEditCollection
        self.accentColor = accentColor
        self.onSeriesSaved = onSeriesSaved
        self.onBookSelected = onBookSelected
    }

    private var sortedBooks: [BookRecord] {
        books.sorted { lhs, rhs in
            switch (lhs.details.volumeNumber, rhs.details.volumeNumber) {
            case let (lhsVolume?, rhsVolume?) where lhsVolume != rhsVolume:
                return lhsVolume < rhsVolume
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private var completionText: String {
        guard let totalBookCount = series.totalBookCount else {
            return "\(books.count) collected · total unknown"
        }

        if books.count >= totalBookCount {
            return "\(books.count) of \(totalBookCount) collected · complete"
        }

        return "\(books.count) of \(totalBookCount) collected"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.lg) {
                summaryCard

                if sortedBooks.isEmpty {
                    CatalogEmptyStateView(
                        systemImage: "book.closed",
                        title: "No Books",
                        message: "No books in this library currently belong to this series.",
                        primaryTint: accentColor
                    )
                    .frame(minHeight: 260)
                } else {
                    VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
                        Text("Books")
                            .font(CatalogTypography.sectionTitle)

                        VStack(spacing: CatalogMetrics.Spacing.md) {
                            ForEach(sortedBooks) { book in
                                Button {
                                    onBookSelected?(book.id)
                                } label: {
                                    CatalogContainerCard(
                                        title: book.title,
                                        subtitle: bookSubtitle(book),
                                        accessory: .icon("chevron.right"),
                                        systemImage: "book.closed.fill"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
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
        .navigationTitle(series.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEditCollection {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingEditor = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit Series")
                }
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            SeriesEditorView(
                collectionID: series.collectionID,
                series: series,
                publishers: publishers
            ) { updatedSeries in
                (repository as! any BookCatalogRepository).saveBookSeries(updatedSeries)
                series = updatedSeries
                onSeriesSaved(updatedSeries)
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.lg) {
            HStack(alignment: .center, spacing: CatalogMetrics.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.medium, style: .continuous)
                        .fill(accentColor.opacity(0.14))
                        .frame(width: 60, height: 60)

                    Image(systemName: "books.vertical.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                    Text(series.name)
                        .font(CatalogTypography.cardTitle)

                    Text(completionText)
                        .font(CatalogTypography.cardSubtitle)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(alignment: .top, spacing: CatalogMetrics.Spacing.lg) {
                metadataField(
                    title: "Total books",
                    value: series.totalBookCount.map(String.init) ?? "Unknown",
                    systemImage: "number"
                )

                if let publisher = series.publisher {
                    metadataField(
                        title: "Publisher",
                        value: publisher.name,
                        systemImage: "building.2"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CatalogMetrics.Spacing.lg)
        .background {
            CatalogShapes.section
                .fill(.ultraThinMaterial)
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
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func bookSubtitle(_ book: BookRecord) -> String? {
        if let volume = book.details.volumeNumber {
            if let total = series.totalBookCount {
                return "Volume \(volume) / \(total)"
            }
            return "Volume \(volume)"
        }

        return nil
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

    if let series = snapshot.bookSeries.first {
        NavigationStack {
            SeriesDetailView(
                series: series,
                books: snapshot.bookRecords.filter { $0.details.series?.id == series.id },
                publishers: snapshot.bookSeries.compactMap(\.publisher),
                repository: repository,
                canEditCollection: true,
                accentColor: .accentColor,
                onSeriesSaved: { _ in }
            )
        }
        .environment(\.managedObjectContext, container.viewContext)
    }
}
#endif