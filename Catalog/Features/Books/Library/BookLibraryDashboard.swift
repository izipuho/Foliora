import SwiftUI

/// Displays the book library dashboard view interface.
struct BookLibraryDashboardView: View {
    let books: [BookRecord]
    let series: [BookSeries]
    let accentColor: Color
    let collection: CollectionSummary
    let sharingState: CollectionSharingState?
    let sharingService: any CollectionSharingService
    let onSharingChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            DashboardCardStrip(
                books: books,
                series: series,
                collection: collection,
                sharingState: sharingState,
                sharingService: sharingService,
                tint: accentColor,
                onSharingChanged: onSharingChanged
            )

            MetricStrip(
                books: books,
                series: series,
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
    }
}

private struct DashboardCardStrip: View {
    let books: [BookRecord]
    let series: [BookSeries]
    let collection: CollectionSummary
    let sharingState: CollectionSharingState?
    let sharingService: any CollectionSharingService
    let tint: Color
    let onSharingChanged: () -> Void

    @State private var isPresentingDataHealthPopover = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CatalogMetrics.Spacing.md) {
                sharingCard

                if !series.isEmpty {
                    BookSeriesHealthCard(
                        completeCount: completeSeriesCount,
                        incompleteCount: incompleteSeriesCount,
                        unknownCount: unknownSeriesCount,
                        tint: tint
                    )
                }

                CatalogDashboardDataHealthCard(
                    progress: dataHealthProgress,
                    tint: tint
                ) {
                    isPresentingDataHealthPopover = true
                }
                .popover(isPresented: $isPresentingDataHealthPopover) {
                    CatalogDashboardDataHealthPopover(entries: dataHealthEntries) { entry in
                        DashboardDataHealthRow(
                            title: entry.title,
                            countText: "\(entry.missingCount)/\(entry.totalCount)",
                            missingProgress: entry.progress
                        )
                    }
                }
            }
        }
        .scrollClipDisabled()
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

    private var completeSeriesCount: Int {
        series.filter { series in
            guard let totalBookCount = series.totalBookCount, totalBookCount > 0 else { return false }
            return ownedBookCount(for: series) >= totalBookCount
        }.count
    }

    private var incompleteSeriesCount: Int {
        series.filter { series in
            guard let totalBookCount = series.totalBookCount, totalBookCount > 0 else { return false }
            return ownedBookCount(for: series) < totalBookCount
        }.count
    }

    private var knownSeriesCount: Int {
        completeSeriesCount + incompleteSeriesCount
    }

    private var unknownSeriesCount: Int {
        series.filter { series in
            guard let totalBookCount = series.totalBookCount else { return true }
            return totalBookCount <= 0
        }.count
    }

    private func ownedBookCount(for series: BookSeries) -> Int {
        books.filter { $0.details.series?.id == series.id }.count
    }

    private var dataHealthProgress: Double {
        let filledBookFields = books.reduce(into: 0) { count, book in
            if hasCover(book) { count += 1 }
            if hasAuthor(book) { count += 1 }
            if book.details.publicationYear != nil { count += 1 }
        }
        let filledSeriesFields = knownSeriesCount
        let totalFields = books.count * 3 + series.count

        guard totalFields > 0 else { return 0 }
        return Double(filledBookFields + filledSeriesFields) / Double(totalFields)
    }

    private var dataHealthEntries: [BookDataHealthEntry] {
        var entries = [
            BookDataHealthEntry(
                title: "Missing Cover",
                missingCount: books.filter { !hasCover($0) }.count,
                totalCount: books.count
            ),
            BookDataHealthEntry(
                title: "Missing Author",
                missingCount: books.filter { !hasAuthor($0) }.count,
                totalCount: books.count
            ),
            BookDataHealthEntry(
                title: "Missing Publication Year",
                missingCount: books.filter { $0.details.publicationYear == nil }.count,
                totalCount: books.count
            )
        ]

        if unknownSeriesCount > 0 {
            entries.append(
                BookDataHealthEntry(
                    title: "Series Size Unknown",
                    missingCount: unknownSeriesCount,
                    totalCount: series.count
                )
            )
        }

        if incompleteSeriesCount > 0 {
            entries.append(
                BookDataHealthEntry(
                    title: "Incomplete Series",
                    missingCount: incompleteSeriesCount,
                    totalCount: knownSeriesCount
                )
            )
        }

        return entries
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

private struct BookDataHealthEntry: Identifiable {
    let title: String
    let missingCount: Int
    let totalCount: Int

    var id: String { title }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(missingCount) / Double(totalCount)
    }
}

private struct MetricStrip: View {
    let books: [BookRecord]
    let series: [BookSeries]
    let tint: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CatalogMetrics.Spacing.sm) {
                MetricPill(
                    title: "Total",
                    value: "\(books.count)",
                    systemImage: "books.vertical.fill",
                    tint: tint
                )

                MetricPill(
                    title: "Authors",
                    value: "\(authorCount)",
                    systemImage: "person.fill",
                    tint: tint
                )

                MetricPill(
                    title: "Series",
                    value: "\(series.count)",
                    systemImage: "books.vertical",
                    tint: tint
                )

                MetricPill(
                    title: "Languages",
                    value: "\(languageCount)",
                    systemImage: "character.book.closed.fill",
                    tint: tint
                )

                MetricPill(
                    title: "Tags",
                    value: "\(tagCount)",
                    systemImage: "tag.fill",
                    tint: tint
                )
            }
        }
        .scrollClipDisabled()
    }

    private var authorCount: Int {
        Set(
            books.flatMap { book in
                book.details.contributors
                    .filter { $0.role == .author }
                    .map(\.person.id)
            }
        ).count
    }

    private var languageCount: Int {
        Set(
            books.compactMap { $0.details.languageCode.map(normalizedMetricValue) }
                .filter { !$0.isEmpty }
        ).count
    }

    private var tagCount: Int {
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
