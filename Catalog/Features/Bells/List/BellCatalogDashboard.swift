import SwiftUI

struct BellCatalogDashboardView: View {
    let stats: BellCatalogStats
    let accentColor: Color
    let collection: CollectionSummary?
    let sharingState: CollectionSharingState
    let sharingService: (any CollectionSharingService)?
    let onSharingChanged: () -> Void
    let onFilterApply: (BellPresenceFilter) -> Void
    let onGeographyFocus: (String) -> Void
    let onResetFilters: () -> Void

    @State private var isPresentingTopGeographyPopover = false
    @State private var isPresentingDataHealthPopover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    sharingCard

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

                    DashboardTopGeographyCard(
                        countryName: topGeography?.name ?? String(localized: "common.unknown"),
                        flag: topGeography?.flag ?? "🌍",
                        countText: topGeographyCountText,
                        tint: accentColor,
                        action: {
                            guard !topGeographyEntries.isEmpty else { return }
                            isPresentingTopGeographyPopover = true
                        }
                    )
                    .popover(isPresented: $isPresentingTopGeographyPopover) {
                        TopGeographyPopover(
                            entries: topGeographyEntries,
                            onSelect: { country in
                                isPresentingTopGeographyPopover = false
                                onGeographyFocus(country)
                            }
                        )
                    }
                }
            }
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CatalogLayoutInsets.screen)
        .padding(.top, CatalogSpacing.compact)
        .padding(.vertical, 4)
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

    private var topGeographyEntries: [TopGeographyEntry] {
        Array(stats.topCountries.prefix(5)).map { row in
            TopGeographyEntry(
                country: row.country,
                flag: flagEmoji(for: row.countryCode),
                countText: localizedCount(row.count, kind: .bells)
            )
        }
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
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
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
                        .font(.headline)
                    Text(content.value)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if let detail = content.detail {
                        Text(detail)
                            .font(.caption.weight(.semibold))
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
                        .stroke(CatalogSemanticColors.separator, lineWidth: 8)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.subheadline.weight(.bold))
                }
                .frame(width: 56, height: 56)
            } content: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "bell_catalog.dashboard.health"))
                        .font(.headline)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DashboardCard {
                Text(flag)
                    .font(.system(size: 34))
            } content: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "bell_catalog.dashboard.top_geography"))
                        .font(.headline)
                    Text(countryName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(countText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct TopGeographyEntry: Identifiable {
    let country: String
    let flag: String
    let countText: String

    var id: String { country }
}

struct TopGeographyPopover: View {
    let entries: [TopGeographyEntry]
    let onSelect: (String) -> Void

    var body: some View {
        DashboardPopoverContainer(
            title: "bell_catalog.dashboard.top_geography",
            entries: entries,
            onSelect: { onSelect($0.country) }
        ) { entry in
            DashboardPopoverButtonRow(
                title: entry.country,
                subtitle: entry.countText
            )
        }
    }
}

private struct DashboardPopoverButtonRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct DashboardPopoverContainer<Entry, Content: View>: View {
    let title: LocalizedStringKey
    let entries: [Entry]
    let onSelect: (Entry) -> Void
    let content: (Entry) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                                //.padding(.vertical, 5)
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
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    GeometryReader { proxy in
                        HStack(spacing: 8) {
                            Text(entry.countText)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)

                            DataHealthMissingProgressBar(progress: entry.missingProgress)
                                .frame(width: proxy.size.width / 2)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(height: 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text("\(value)/\(total)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(CatalogSemanticColors.separator)

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
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer()

                Text("\(value)")
                    .font(.subheadline.weight(.bold))
                    .catalogPillPadding(.compact)
                    .background(tint.opacity(0.14), in: Capsule())
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
        VStack(alignment: .leading, spacing: CatalogSpacing.micro) {
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, CatalogSpacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous))
    }
}
