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

                BookSeriesHealthCard(
                    completeCount: completeSeriesCount,
                    incompleteCount: incompleteSeriesCount,
                    unknownCount: unknownSeriesCount,
                    tint: tint
                )

                BookDataHealthCard(
                    progress: dataHealthProgress,
                    tint: tint
                ) {
                    isPresentingDataHealthPopover = true
                }
                .popover(isPresented: $isPresentingDataHealthPopover) {
                    BookDataHealthPopover(entries: dataHealthEntries)
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
        guard !books.isEmpty else { return 0 }

        let filledFields = books.reduce(into: 0) { count, book in
            if hasCover(book) { count += 1 }
            if hasAuthor(book) { count += 1 }
            if book.details.publicationYear != nil { count += 1 }
        }

        return Double(filledFields) / Double(books.count * 3)
    }

    private var dataHealthEntries: [BookDataHealthEntry] {
        [
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
            return unknownCount > 0 ? "No completion data" : "No series"
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

private struct BookDataHealthCard: View {
    let progress: Double
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DashboardCard {
                ZStack {
                    Circle()
                        .stroke(Color(uiColor: .separator), lineWidth: 8)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(CatalogTypography.cardSubtitle)
                }
                .frame(width: 56, height: 56)
            } content: {
                VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                    Text("Data Health")
                        .font(CatalogTypography.sectionTitle)
                    Text("Cover · Author · Year")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .buttonStyle(.plain)
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

private struct BookDataHealthPopover: View {
    let entries: [BookDataHealthEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            Text("Data Health")
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                ForEach(entries.indices, id: \.self) { index in
                    let entry = entries[index]

                    VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xxs) {
                        Text(entry.title)
                            .font(CatalogTypography.cardSubtitle)
                            .foregroundStyle(.primary)

                        HStack(spacing: CatalogMetrics.Spacing.sm) {
                            Text("\(entry.missingCount)/\(entry.totalCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(.green.opacity(0.35))

                                    Capsule()
                                        .fill(.red.opacity(0.8))
                                        .frame(width: proxy.size.width * min(max(entry.progress, 0), 1))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                    .padding(CatalogMetrics.Spacing.md)

                    if index < entries.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .presentationDetents([.medium])
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
