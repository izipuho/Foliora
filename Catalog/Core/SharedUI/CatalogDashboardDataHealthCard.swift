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
