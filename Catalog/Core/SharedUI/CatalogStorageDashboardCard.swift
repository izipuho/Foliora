import SwiftUI

/// Displays a dashboard card summarizing a collection's storage locations.
struct CatalogStorageDashboardCard: View {
    let tree: CatalogStorageTree
    let tint: Color

    var body: some View {
        DashboardCard {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
        } content: {
            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                Text("storage.title")
                    .font(CatalogTypography.sectionTitle)

                Text(summaryText)
                    .font(CatalogTypography.cardSubtitle)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if tree.unassignedCount > 0 {
                    Text(String.localizedStringWithFormat(
                        String(localized: "storage.card.unassigned_count"),
                        tree.unassignedCount
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
    }

    private var summaryText: String {
        guard !tree.nodes.isEmpty else {
            return String(localized: "storage.card.no_locations")
        }

        return [
            String.localizedStringWithFormat(
                String(localized: "home.storage.count.cabinets"),
                tree.cabinetCount
            ),
            String.localizedStringWithFormat(
                String(localized: "home.storage.count.shelves"),
                tree.shelfCount
            )
        ].joined(separator: " · ")
    }
}
