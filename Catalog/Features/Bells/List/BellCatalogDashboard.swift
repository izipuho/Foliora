import SwiftUI

/// Displays the bell catalog dashboard view interface.
struct BellCatalogDashboardView: View {
    let stats: BellCatalogStats
    let accentColor: Color
    let collection: CollectionSummary?
    let catalogSnapshot: CatalogSnapshot?
    let sharingState: CollectionSharingState
    let sharingService: (any CollectionSharingService)?
    let onSharingChanged: () -> Void
    let onBellSelected: ((UUID) -> Void)?
    let onFilterApply: (BellPresenceFilter) -> Void
    let onResetFilters: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            DashboardCardStrip(
                stats: stats,
                tint: accentColor,
                collection: collection,
                catalogSnapshot: catalogSnapshot,
                sharingState: sharingState,
                sharingService: sharingService,
                onSharingChanged: onSharingChanged,
                onBellSelected: onBellSelected,
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
    let stats: BellCatalogStats
    let tint: Color
    let collection: CollectionSummary?
    let catalogSnapshot: CatalogSnapshot?
    let sharingState: CollectionSharingState
    let sharingService: (any CollectionSharingService)?
    let onSharingChanged: () -> Void
    let onBellSelected: ((UUID) -> Void)?
    let onFilterApply: (BellPresenceFilter) -> Void

    var body: some View {
        CatalogDashboardCardStrip { isDataHealthExpanded in
            sharingCard

            if let collection {
                NavigationLink {
                    BellsOriginMapView(
                        collection: collection,
                        catalogSnapshot: catalogSnapshot,
                        onBellSelected: onBellSelected
                    )
                } label: {
                    DashboardTopGeographyCard(
                        countryName: topGeography?.name ?? String(localized: "common.unknown"),
                        flag: topGeography?.flag ?? "🌍",
                        countText: topGeographyCountText,
                        tint: tint
                    )
                }
                .buttonStyle(.plain)
            } else {
                DashboardTopGeographyCard(
                    countryName: topGeography?.name ?? String(localized: "common.unknown"),
                    flag: topGeography?.flag ?? "🌍",
                    countText: topGeographyCountText,
                    tint: tint
                )
            }

            CatalogDashboardDataHealthCard(
                progress: dataHealthProgress,
                tint: tint,
                entries: dataHealthEntries,
                isExpanded: isDataHealthExpanded,
                onSelect: { entry in
                    onFilterApply(entry.filter)
                }
            ) { entry in
                DashboardDataHealthRow(
                    title: entry.title,
                    countText: entry.countText,
                    missingProgress: entry.missingProgress,
                    showsDisclosureIndicator: true
                )
            }
        }
    }

    @ViewBuilder
    private var sharingCard: some View {
        if let collection, let sharingService {
            NavigationLink {
                CollectionSharingView(collection: collection, state: sharingState, sharingService: sharingService) {
                    onSharingChanged()
                }
            } label: {
                CatalogDashboardSharingCard(
                    state: sharingState,
                    tint: tint
                )
            }
            .buttonStyle(.plain)
        } else {
            CatalogDashboardSharingCard(
                state: sharingState,
                tint: tint
            )
        }
    }

    private var dataHealthProgress: Double {
        guard stats.totalCount > 0 else { return 0 }
        let completeFields = stats.filledOriginCount
            + stats.filledYearCount
            + stats.filledStorageCount
            + stats.filledNotesCount
            + stats.filledTagsCount
        let totalFields = stats.totalCount * 5
        return min(max(Double(completeFields) / Double(totalFields), 0), 1)
    }

    private var dataHealthEntries: [DataHealthEntry] {
        let total = stats.totalCount

        func missingCount(filled: Int) -> String {
            let missingCount = total - filled
            return "\(missingCount)/\(total)"
        }

        func missingProgress(filled: Int) -> Double {
            guard total > 0 else { return 0 }
            return min(max(Double(total - filled) / Double(total), 0), 1)
        }

        return [
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.missing_origin"),
                countText: missingCount(filled: stats.filledOriginCount),
                missingProgress: missingProgress(filled: stats.filledOriginCount),
                filter: .missingOrigin
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.missing_year"),
                countText: missingCount(filled: stats.filledYearCount),
                missingProgress: missingProgress(filled: stats.filledYearCount),
                filter: .missingYear
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.missing_storage"),
                countText: missingCount(filled: stats.filledStorageCount),
                missingProgress: missingProgress(filled: stats.filledStorageCount),
                filter: .missingStorage
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.missing_material"),
                countText: missingCount(filled: stats.filledMaterialCount),
                missingProgress: missingProgress(filled: stats.filledMaterialCount),
                filter: .missingMaterial
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.missing_notes"),
                countText: missingCount(filled: stats.filledNotesCount),
                missingProgress: missingProgress(filled: stats.filledNotesCount),
                filter: .missingNotes
            ),
            DataHealthEntry(
                title: String(localized: "bell_catalog.summary.missing_tags"),
                countText: missingCount(filled: stats.filledTagsCount),
                missingProgress: missingProgress(filled: stats.filledTagsCount),
                filter: .missingTags
            )
        ]
    }

    private var topGeography: (name: String, flag: String, count: Int)? {
        guard let topCountry = stats.topCountries.first else { return nil }
        return (
            name: topCountry.country,
            flag: flagEmoji(for: topCountry.countryCode),
            count: topCountry.count
        )
    }

    private var topGeographyCountText: String {
        guard let topGeography else { return String(localized: "bell_catalog.summary.no_origin_data") }
        return localizedCount(topGeography.count, kind: .bells)
    }

    private func localizedCount(_ count: Int, kind: SummaryCountKind) -> String {
        String.localizedStringWithFormat(
            String(localized: kind.resource),
            count
        )
    }

    private func flagEmoji(for countryCode: String) -> String {
        let normalizedCode = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCode.count == 2 else { return "🌍" }

        let base: UInt32 = 127397
        let scalars = normalizedCode.unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }
        return scalars.count == 2 ? String(String.UnicodeScalarView(scalars)) : "🌍"
    }
}

private struct MetricStrip: View {
    let stats: BellCatalogStats
    let tint: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CatalogMetrics.Spacing.sm) {
                MetricPill(
                    title: String(localized: "catalog.dashboard.total"),
                    value: "\(stats.totalCount)",
                    systemImage: "bell.fill",
                    tint: tint
                )

                MetricPill(
                    title: String(localized: "catalog.dashboard.countries"),
                    value: "\(stats.countryCount)",
                    systemImage: "globe.europe.africa.fill",
                    tint: tint
                )

                MetricPill(
                    title: String(localized: "catalog.dashboard.cities"),
                    value: "\(stats.cityCount)",
                    systemImage: "building.2.fill",
                    tint: tint
                )

                MetricPill(
                    title: String(localized: "bell_catalog.summary.materials"),
                    value: "\(stats.materialCount)",
                    systemImage: "cube.fill",
                    tint: tint
                )

                MetricPill(
                    title: String(localized: "bell_catalog.summary.tags"),
                    value: "\(stats.tagCount)",
                    systemImage: "tag.fill",
                    tint: tint
                )
            }
        }
        .scrollClipDisabled()
    }
}

/// Displays the dashboard top geography card interface.
struct DashboardTopGeographyCard: View {
    let countryName: String
    let flag: String
    let countText: String
    let tint: Color

    var body: some View {
        DashboardCard {
            Text(flag)
                .font(.system(size: 34))
        } content: {
            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                Text(String(localized: "common.ui.geography"))
                    .font(CatalogTypography.sectionTitle)
                Text(countryName)
                    .font(CatalogTypography.cardSubtitle)
                    .lineLimit(1)
                Text(countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Represents data health entry data and behavior.
struct DataHealthEntry: Identifiable {
    let title: String
    let countText: String
    let missingProgress: Double
    let filter: BellPresenceFilter

    var id: String { title }
}

/// Displays the summary coverage row interface.
struct SummaryCoverageRow: View {
    let title: String
    let value: Int
    let total: Int
    let tint: Color
    let action: () -> Void

    private var progress: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(value) / CGFloat(total)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
                HStack {
                    Text(title)
                        .font(CatalogTypography.cardSubtitle)

                    Spacer()

                    Text("\(value)/\(total)")
                        .font(CatalogTypography.chipLabel)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(uiColor: .separator))

                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 8)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Displays the summary breakdown row interface.
struct SummaryBreakdownRow: View {
    let title: String
    let value: Int
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: CatalogMetrics.Spacing.md) {
                Text(title)
                    .font(CatalogTypography.cardSubtitle)
                    .lineLimit(1)

                Spacer()

                Text("\(value)")
                    .font(CatalogTypography.cardSubtitle)
                    .padding(.horizontal, CatalogMetrics.Spacing.sm)
                    .padding(.vertical, CatalogMetrics.Spacing.xs)
                    .catalogSurfaceCapsule()
            }
        }
        .buttonStyle(.plain)
    }
}

/// Displays the stat chip interface.
struct StatChip: View {
    let value: String
    let title: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, CatalogMetrics.Spacing.sm)
        .padding(.horizontal, CatalogMetrics.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: CatalogShapes.tile)
    }
}
