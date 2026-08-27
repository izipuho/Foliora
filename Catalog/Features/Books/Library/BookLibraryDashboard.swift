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
    let collection: CollectionSummary
    let sharingState: CollectionSharingState?
    let sharingService: any CollectionSharingService
    let tint: Color
    let onSharingChanged: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CatalogMetrics.Spacing.md) {
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
        }
        .scrollClipDisabled()
    }

    private var placeholderSharingState: CollectionSharingState {
        CollectionSharingState(
            currentUserRole: .owner,
            participants: []
        )
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
