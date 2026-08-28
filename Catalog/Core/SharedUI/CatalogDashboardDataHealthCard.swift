import SwiftUI

/// Displays catalog data health status in a dashboard card.
struct CatalogDashboardDataHealthCard: View {
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
                    Text(String(localized: "catalog.dashboard.health"))
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

/// Displays catalog data health details in a shared dashboard popover.
struct CatalogDashboardDataHealthPopover<Entry, Content: View>: View {
    let entries: [Entry]
    let onSelect: ((Entry) -> Void)?
    let content: (Entry) -> Content

    init(
        entries: [Entry],
        onSelect: ((Entry) -> Void)? = nil,
        @ViewBuilder content: @escaping (Entry) -> Content
    ) {
        self.entries = entries
        self.onSelect = onSelect
        self.content = content
    }

    var body: some View {
        DashboardPopoverContainer(
            title: String(localized: "catalog.dashboard.health"),
            entries: entries,
            onSelect: onSelect,
            content: content
        )
    }
}
