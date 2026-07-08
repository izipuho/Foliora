import SwiftUI

struct BellCatalogDashboardView: View {
    let stats: BellCatalogStats
    let accentColor: Color
    let collection: CollectionSummary?
    let repository: any CatalogRepository
    let sharingState: CollectionSharingState
    let sharingService: (any CollectionSharingService)?
    let onSharingChanged: () -> Void
    let onFilterApply: (BellPresenceFilter) -> Void
    let onResetFilters: () -> Void

    @State private var isPresentingDataHealthPopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CatalogMetrics.Spacing.md) {
                    sharingCard

                    if let collection {
                        NavigationLink {
                            CollectionOriginMapView(
                                collection: collection,
                                repository: repository
                            )
                        } label: {
                            DashboardTopGeographyCard(
                                countryName: topGeography?.name ?? String(localized: "common.unknown"),
                                flag: topGeography?.flag ?? "🌍",
                                countText: topGeographyCountText,
                                tint: accentColor
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        DashboardTopGeographyCard(
                            countryName: topGeography?.name ?? String(localized: "common.unknown"),
                            flag: topGeography?.flag ?? "🌍",
                            countText: topGeographyCountText,
                            tint: accentColor
                        )
                    }

                    DashboardDataHealthCard(
                        progress: dataHealthProgress,
                        tint: accentColor
                    ) {
                        isPresentingDataHealthPopover = true
                    }
                    .popover(isPresented: $isPresentingDataHealthPopover) {
                        DataHealthPopover(
                            entries: dataHealthEntries,
                            onSelect: { filter in
                                isPresentingDataHealthPopover = false
                                onFilterApply(filter)
                            }
                        )
                    }
                }
            }
            .scrollClipDisabled()
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CatalogMetrics.Spacing.sm) {
                    MetricPill(
                        title: String(localized: "bell_catalog.dashboard.total"),
                        value: "\(stats.totalCount)",
                        systemImage: "bell.fill",
                        tint: accentColor,
                    )

                    MetricPill(
                        title: String(localized: "bell_catalog.dashboard.countries"),
                        value: "\(stats.countryCount)",
                        systemImage: "globe.europe.africa.fill",
                        tint: accentColor
                    )

                    MetricPill(
                        title: String(localized: "bell_catalog.dashboard.cities"),
                        value: "\(stats.cityCount)",
                        systemImage: "building.2.fill",
                        tint: accentColor
                    )

                    MetricPill(
                        title: String(localized: "bell_catalog.summary.materials"),
                        value: "\(stats.materialCount)",
                        systemImage: "cube.fill",
                        tint: accentColor
                    )

                    MetricPill(
                        title: String(localized: "bell_catalog.summary.tags"),
                        value: "\(stats.tagCount)",
                        systemImage: "tag.fill",
                        tint: accentColor
                    )
                }
            }
            .scrollClipDisabled()
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

    @ViewBuilder
    private var sharingCard: some View {
        if let collection, let sharingService {
            NavigationLink {
                CollectionSharingView(collection: collection, state: sharingState, sharingService: sharingService) {
                    onSharingChanged()
                }
            } label: {
                DashboardSharingCard(
                    state: sharingState,
                    tint: accentColor
                )
            }
            .buttonStyle(.plain)
        } else {
            DashboardSharingCard(
                state: sharingState,
                tint: accentColor
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

private struct MetricPill: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    var isInteractive = true
    var action: (() -> Void)?

    var body: some View {
        if isInteractive, let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: CatalogMetrics.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(CatalogTypography.cardSubtitle)

            Text(value)
                .font(CatalogTypography.cardSubtitle)
                .foregroundStyle(.secondary)
        }
        .catalogSurfaceCapsule()
    }
}

private struct DashboardSharingCard: View {
    let state: CollectionSharingState
    let tint: Color

    private enum Layout {
        static let textSpacing: CGFloat = 2
        static let iconFontSize: CGFloat = 24
    }

    @ViewBuilder
    var body: some View {
        if let content {
            DashboardCard {
                Image(systemName: content.systemImage)
                    .font(.system(size: Layout.iconFontSize, weight: .semibold))
                    .foregroundStyle(tint)
            } content: {
                VStack(alignment: .leading, spacing: Layout.textSpacing) {
                    Text(String(localized: "bell_catalog.dashboard.sharing"))
                        .font(CatalogTypography.sectionTitle)
                    Text(content.value)
                        .font(CatalogTypography.cardSubtitle)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if let detail = content.detail {
                        Text(detail)
                            .font(CatalogTypography.chipLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        } else {
            EmptyView()
        }
    }

    private var content: DashboardSharingCardContent? {
        switch state.currentUserRole {
        case .owner:
            return DashboardSharingCardContent(
                systemImage: "person.2.fill",
                value: state.isShared ? localizedParticipantsCount : String(localized: "collection.sharing.status.private"),
                detail: pendingInvitationsDetail
            )
        case .contributor:
            return DashboardSharingCardContent(
                systemImage: "person.crop.circle.badge.checkmark",
                value: String(localized: "collection.sharing.role.contributor"),
                detail: nil
            )
        case .viewer:
            return DashboardSharingCardContent(
                systemImage: "eye.fill",
                value: String(localized: "collection.sharing.role.viewer"),
                detail: nil
            )
        }
    }

    private var localizedParticipantsCount: String {
        String.localizedStringWithFormat(
            String(localized: "collection.sharing.participants_count"),
            acceptedParticipantCount
        )
    }

    private var pendingInvitationsDetail: String? {
        guard pendingInvitationCount > 0 else { return nil }

        return String.localizedStringWithFormat(
            String(localized: "bell_catalog.dashboard.sharing.pending_invitations_count"),
            pendingInvitationCount
        )
    }

    private var acceptedParticipantCount: Int {
        state.participants.filter {
            !$0.isCurrentUser && $0.acceptanceStatus == .accepted
        }.count
    }

    private var pendingInvitationCount: Int {
        state.participants.filter {
            !$0.isCurrentUser && $0.acceptanceStatus == .pending
        }.count
    }
}

private struct DashboardSharingCardContent {
    let systemImage: String
    let value: String
    let detail: String?
}

struct DashboardDataHealthCard: View {
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
                    Text(String(localized: "bell_catalog.dashboard.health"))
                        .font(CatalogTypography.sectionTitle)
                    Text(String(localized: "bell_catalog.dashboard.health.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

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

private struct DashboardPopoverContainer<Entry, Content: View>: View {
    let title: LocalizedStringKey
    let entries: [Entry]
    let onSelect: (Entry) -> Void
    let content: (Entry) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries.indices, id: \.self) { index in
                        let entry = entries[index]

                        Button {
                            onSelect(entry)
                        } label: {
                            content(entry)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < entries.count - 1 {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: CatalogShapes.thumbnail)
            }
        }
        .padding()
        .presentationDetents([.medium])
    }
}

struct DataHealthEntry: Identifiable {
    let title: String
    let countText: String
    let missingProgress: Double
    let filter: BellPresenceFilter

    var id: String { title }
}

struct DataHealthPopover: View {
    let entries: [DataHealthEntry]
    let onSelect: (BellPresenceFilter) -> Void

    var body: some View {
        DashboardPopoverContainer(
            title: "bell_catalog.dashboard.health",
            entries: entries,
            onSelect: { onSelect($0.filter) }
        ) { entry in
            HStack(spacing: CatalogMetrics.Spacing.md) {
                VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xxs) {
                    Text(entry.title)
                        .font(CatalogTypography.cardSubtitle)
                        .foregroundStyle(.primary)

                    GeometryReader { proxy in
                        HStack(spacing: CatalogMetrics.Spacing.sm) {
                            Text(entry.countText)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)

                            DataHealthMissingProgressBar(progress: entry.missingProgress)
                                .frame(width: proxy.size.width / 2)

                            Image(systemName: "chevron.right")
                                .font(CatalogTypography.chipLabel)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(height: 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(CatalogMetrics.Spacing.md)
        }
    }
}

private struct DataHealthMissingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.green.opacity(0.35))

                Capsule()
                    .fill(.red.opacity(0.8))
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 6, maxHeight: 6)
    }
}

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
