import SwiftUI

/// Displays the book library dashboard view interface.
struct BookLibraryDashboardView: View {
    let books: [BookRecord]
    let accentColor: Color
    let collection: CollectionSummary
    let sharingState: CollectionSharingState?
    let sharingService: any CollectionSharingService
    let onSharingChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            if let sharingState {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: CatalogMetrics.Spacing.md) {
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
                                tint: accentColor
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollClipDisabled()
            }

            BookLibraryMetricStrip(
                books: books,
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

private struct BookLibraryMetricStrip: View {
    let books: [BookRecord]
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
                    value: "\(seriesCount)",
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
                    title: "Publication Places",
                    value: "\(publicationPlaceCount)",
                    systemImage: "mappin.and.ellipse",
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
                    .map { normalizedMetricValue($0.person.name) }
                    .filter { !$0.isEmpty }
            }
        ).count
    }

    private var seriesCount: Int {
        Set(books.compactMap { $0.details.series?.id }).count
    }

    private var languageCount: Int {
        Set(
            books.compactMap { $0.details.languageCode.map(normalizedMetricValue) }
                .filter { !$0.isEmpty }
        ).count
    }

    private var publicationPlaceCount: Int {
        Set(
            books.compactMap { book -> String? in
                if let place = book.details.publicationPlace {
                    return "id:\(place.id.uuidString)"
                }

                guard let name = book.details.publicationPlaceName else { return nil }
                let normalizedName = normalizedMetricValue(name)
                return normalizedName.isEmpty ? nil : "name:\(normalizedName)"
            }
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
