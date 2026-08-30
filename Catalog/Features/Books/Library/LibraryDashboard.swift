import SwiftUI

/// Displays the book library dashboard view interface.
struct LibraryDashboardView: View {
    let stats: LibraryStats
    let accentColor: Color
    let collection: CollectionSummary
    let catalogSnapshot: CatalogSnapshot?
    let repository: any CatalogRepository
    let canEditCollection: Bool
    let onBookSelected: ((UUID) -> Void)?
    let sharingState: CollectionSharingState?
    let sharingService: any CollectionSharingService
    let onSharingChanged: () -> Void
    let onFilterApply: (BookPresenceFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            DashboardCardStrip(
                stats: stats,
                collection: collection,
                catalogSnapshot: catalogSnapshot,
                repository: repository,
                canEditCollection: canEditCollection,
                onBookSelected: onBookSelected,
                sharingState: sharingState,
                sharingService: sharingService,
                tint: accentColor,
                onSharingChanged: onSharingChanged,
                onFilterApply: onFilterApply
            )
            .zIndex(1)

            MetricStrip(
                stats: stats,
                tint: accentColor
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CatalogMetrics.Insets.screen)
        .padding(.top, CatalogMetrics.Spacing.xs)
        .padding(.vertical, CatalogMetrics.Spacing.xs)
        .scrollTransition(axis: .vertical) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.94, anchor: .top)
                .opacity(phase.isIdentity ? 1 : 0.82)
        }
        .zIndex(1)
    }
}

private struct DashboardCardStrip: View {
    let stats: LibraryStats
    let collection: CollectionSummary
    let catalogSnapshot: CatalogSnapshot?
    let repository: any CatalogRepository
    let canEditCollection: Bool
    let onBookSelected: ((UUID) -> Void)?
    let sharingState: CollectionSharingState?
    let sharingService: any CollectionSharingService
    let tint: Color
    let onSharingChanged: () -> Void
    let onFilterApply: (BookPresenceFilter) -> Void

    var body: some View {
        CatalogDashboardCardStrip { isDataHealthExpanded in
            sharingCard

            NavigationLink {
                SeriesView(
                    collection: collection,
                    catalogSnapshot: catalogSnapshot,
                    repository: repository,
                    canEditCollection: canEditCollection,
                    onBookSelected: onBookSelected
                )
            } label: {
                BookSeriesHealthCard(
                    completeCount: stats.completeSeriesCount,
                    incompleteCount: stats.incompleteSeriesCount,
                    unknownCount: stats.unknownSeriesCount,
                    tint: tint
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                PublishersView(
                    collection: collection,
                    catalogSnapshot: catalogSnapshot,
                    repository: repository,
                    canEditCollection: canEditCollection,
                    onBookSelected: onBookSelected
                )
            } label: {
                BookPublisherDashboardCard(
                    libraryCount: libraryPublisherCount,
                    tint: tint
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                PeopleView(
                    collection: collection,
                    catalogSnapshot: catalogSnapshot,
                    repository: repository,
                    canEditCollection: canEditCollection,
                    onBookSelected: onBookSelected
                )
            } label: {
                BookPeopleDashboardCard(
                    libraryCount: libraryPeopleCount,
                    tint: tint
                )
            }
            .buttonStyle(.plain)

            CatalogDashboardDataHealthCard(
                progress: stats.dataHealthProgress,
                tint: tint,
                entries: dataHealthEntries,
                isExpanded: isDataHealthExpanded,
                onSelect: { entry in
                    onFilterApply(entry.filter)
                }
            ) { entry in
                DashboardDataHealthRow(
                    title: entry.title,
                    countText: "\(entry.missingCount)/\(entry.totalCount)",
                    missingProgress: entry.progress,
                    showsDisclosureIndicator: true
                )
            }
        }
    }

    @ViewBuilder
    private var sharingCard: some View {
        if let sharingState {
            NavigationLink {
                CollectionSharingView(
                    collection: collection,
                    state: sharingState,
                    sharingService: sharingService,
                    onSharingChanged: onSharingChanged
                )
            } label: {
                CatalogDashboardSharingCard(
                    state: sharingState,
                    tint: tint
                )
            }
            .buttonStyle(.plain)
        } else {
            CatalogDashboardSharingCard(
                state: placeholderSharingState,
                tint: tint
            )
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var libraryPublisherCount: Int {
        guard let catalogSnapshot else { return 0 }
        let books = catalogSnapshot.bookRecords.filter { $0.collectionID == collection.id }
        let series = catalogSnapshot.bookSeries.filter { $0.collectionID == collection.id }
        return Set(
            books.compactMap { $0.details.publisher?.id }
                + series.compactMap { $0.publisher?.id }
        ).count
    }

    private var libraryPeopleCount: Int {
        guard let catalogSnapshot else { return 0 }
        let books = catalogSnapshot.bookRecords.filter { $0.collectionID == collection.id }
        return Set(
            books.flatMap { $0.details.contributors.map(\.person.id) }
        ).count
    }

    private var dataHealthEntries: [BookDataHealthEntry] {
        var entries = [
            BookDataHealthEntry(
                title: "Missing Cover",
                missingCount: stats.missingCoverCount,
                totalCount: stats.totalCount,
                filter: .missingCover
            ),
            BookDataHealthEntry(
                title: "Missing Author",
                missingCount: stats.missingAuthorCount,
                totalCount: stats.totalCount,
                filter: .missingAuthor
            ),
            BookDataHealthEntry(
                title: "Missing Publication Year",
                missingCount: stats.missingPublicationYearCount,
                totalCount: stats.totalCount,
                filter: .missingPublicationYear
            )
        ]

        if stats.unknownSeriesCount > 0 {
            entries.append(
                BookDataHealthEntry(
                    title: "Series Size Unknown",
                    missingCount: stats.unknownSeriesCount,
                    totalCount: stats.seriesCount,
                    filter: .unknownSeriesSize
                )
            )
        }

        if stats.incompleteSeriesCount > 0 {
            entries.append(
                BookDataHealthEntry(
                    title: "Incomplete Series",
                    missingCount: stats.incompleteSeriesCount,
                    totalCount: stats.knownSeriesCount,
                    filter: .incompleteSeries
                )
            )
        }

        return entries
    }

    private var placeholderSharingState: CollectionSharingState {
        CollectionSharingState(
            currentUserRole: .owner,
            participants: []
        )
    }
}

private struct BookSeriesHealthCard: View {
    let completeCount: Int
    let incompleteCount: Int
    let unknownCount: Int
    let tint: Color

    var body: some View {
        DashboardCard {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
        } content: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Series")
                    .font(CatalogTypography.sectionTitle)

                Text(primaryText)
                    .font(CatalogTypography.cardSubtitle)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if let detailText {
                    Text(detailText)
                        .font(CatalogTypography.chipLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    private var primaryText: String {
        let knownCount = completeCount + incompleteCount
        guard knownCount > 0 else {
            return "No completion data"
        }

        return "\(completeCount) of \(knownCount) complete"
    }

    private var detailText: String? {
        var parts: [String] = []

        if incompleteCount > 0 {
            parts.append("\(incompleteCount) incomplete")
        }

        if unknownCount > 0 {
            parts.append("\(unknownCount) unknown")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct BookPublisherDashboardCard: View {
    let libraryCount: Int
    let tint: Color

    var body: some View {
        DashboardCard {
            Image(systemName: "building.2.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
        } content: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Publishers")
                    .font(CatalogTypography.sectionTitle)

                Text("\(libraryCount) in this library")
                    .font(CatalogTypography.cardSubtitle)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

private struct BookPeopleDashboardCard: View {
    let libraryCount: Int
    let tint: Color

    var body: some View {
        DashboardCard {
            Image(systemName: "person.text.rectangle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
        } content: {
            VStack(alignment: .leading, spacing: 2) {
                Text("People")
                    .font(CatalogTypography.sectionTitle)

                Text("\(libraryCount) in this library")
                    .font(CatalogTypography.cardSubtitle)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

private struct BookDataHealthEntry: Identifiable {
    let title: String
    let missingCount: Int
    let totalCount: Int
    let filter: BookPresenceFilter

    var id: String { title }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(missingCount) / Double(totalCount)
    }
}

private struct MetricStrip: View {
    let stats: LibraryStats
    let tint: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CatalogMetrics.Spacing.sm) {
                MetricPill(
                    title: "Total",
                    value: "\(stats.totalCount)",
                    systemImage: "books.vertical.fill",
                    tint: tint
                )

                MetricPill(
                    title: "Authors",
                    value: "\(stats.authorCount)",
                    systemImage: "person.fill",
                    tint: tint
                )

                MetricPill(
                    title: "Series",
                    value: "\(stats.seriesCount)",
                    systemImage: "books.vertical",
                    tint: tint
                )

                MetricPill(
                    title: "Languages",
                    value: "\(stats.languageCount)",
                    systemImage: "character.book.closed.fill",
                    tint: tint
                )

                MetricPill(
                    title: "Tags",
                    value: "\(stats.tagCount)",
                    systemImage: "tag.fill",
                    tint: tint
                )
            }
        }
        .scrollClipDisabled()
    }
}
