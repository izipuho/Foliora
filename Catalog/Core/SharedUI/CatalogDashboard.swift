import SwiftUI

/// Displays a horizontally scrolling dashboard card strip.
struct CatalogDashboardCardStrip<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: CatalogMetrics.Spacing.md) {
                content
            }
        }
        .scrollClipDisabled()
        .frame(height: 104)
    }
}

/// Displays the dashboard card interface.
struct DashboardCard<Leading: View, Content: View>: View {
    private let leading: Leading
    private let content: Content
    private let cardHeight: CGFloat = 72

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder content: () -> Content
    ) {
        self.leading = leading()
        self.content = content()
    }

    var body: some View {
        HStack(spacing: CatalogMetrics.Spacing.md) {
            leading

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: cardHeight)
        .catalogSurfaceCard()
    }
}

/// Displays collection sharing status in a catalog dashboard card.
struct CatalogDashboardSharingCard: View {
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
                    Text(String(localized: "catalog.dashboard.sharing"))
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

    private var content: Content? {
        switch state.currentUserRole {
        case .owner:
            return Content(
                systemImage: "person.2.fill",
                value: state.isShared
                    ? localizedParticipantsCount
                    : String(localized: "collection.sharing.status.private"),
                detail: pendingInvitationsDetail
            )
        case .contributor:
            return Content(
                systemImage: "person.crop.circle.badge.checkmark",
                value: String(localized: "collection.sharing.role.coowner"),
                detail: nil
            )
        case .viewer:
            return Content(
                systemImage: "eye.fill",
                value: String(localized: "collection.sharing.role.viewer"),
                detail: nil
            )
        }
    }

    private var localizedParticipantsCount: String {
        String.localizedStringWithFormat(
            String(localized: "collection.sharing.participants_count"),
            state.acceptedParticipantsCount
        )
    }

    private var pendingInvitationsDetail: String? {
        guard !state.invitedParticipants.isEmpty else { return nil }

        return String.localizedStringWithFormat(
            String(localized: "catalog.dashboard.sharing.pending_invitations_count"),
            state.invitedParticipants.count
        )
    }

    private struct Content {
        let systemImage: String
        let value: String
        let detail: String?
    }
}

/// Displays catalog data health status in a dashboard card that expands over surrounding content.
struct CatalogDashboardDataHealthCard<Entry, Content: View>: View {
    private let progress: Double
    private let tint: Color
    private let entries: [Entry]
    private let onSelect: (Entry) -> Void
    private let content: (Entry) -> Content

    @State private var isExpanded = false

    init(
        progress: Double,
        tint: Color,
        entries: [Entry],
        onSelect: @escaping (Entry) -> Void,
        @ViewBuilder content: @escaping (Entry) -> Content
    ) {
        self.progress = progress
        self.tint = tint
        self.entries = entries
        self.onSelect = onSelect
        self.content = content
    }

    var body: some View {
        Group {
            if isExpanded {
                compactCard
                    .opacity(0)
                    .overlay(alignment: .topLeading) {
                        expandedCard
                    }
            } else {
                compactCard
            }
        }
        .frame(width: 320)
    }

    private var compactCard: some View {
        header
            .catalogSurfaceCard()
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            VStack(spacing: 0) {
                ForEach(entries.indices, id: \.self) { index in
                    let entry = entries[index]

                    Button {
                        withAnimation(.snappy) {
                            isExpanded = false
                        }
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .catalogSurfaceCard()
    }

    private var header: some View {
        Button {
            withAnimation(.snappy) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: CatalogMetrics.Spacing.md) {
                progressIndicator

                VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                    Text(String(localized: "catalog.dashboard.health"))
                        .font(CatalogTypography.sectionTitle)
                    Text(String(localized: "catalog.dashboard.health.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var progressIndicator: some View {
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
    }
}

/// Displays a compact dashboard metric capsule.
struct MetricPill: View {
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

/// Displays a shared data-health entry row.
struct DashboardDataHealthRow: View {
    let title: String
    let countText: String
    let missingProgress: Double
    var showsDisclosureIndicator = false

    var body: some View {
        HStack(spacing: CatalogMetrics.Spacing.md) {
            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xxs) {
                Text(title)
                    .font(CatalogTypography.cardSubtitle)
                    .foregroundStyle(.primary)

                GeometryReader { proxy in
                    HStack(spacing: CatalogMetrics.Spacing.sm) {
                        Text(countText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        DashboardDataHealthMissingProgressBar(progress: missingProgress)
                            .frame(width: proxy.size.width / 2)

                        if showsDisclosureIndicator {
                            Image(systemName: "chevron.right")
                                .font(CatalogTypography.chipLabel)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(CatalogMetrics.Spacing.md)
    }
}

private struct DashboardDataHealthMissingProgressBar: View {
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
