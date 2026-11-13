import SwiftUI

/// Displays a catalog section header with an optional jump action.
struct CatalogSectionHeader: View {
    let title: String
    let showsJumpIndicator: Bool
    let action: () -> Void

    init(
        title: String,
        showsJumpIndicator: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.title = title
        self.showsJumpIndicator = showsJumpIndicator
        self.action = action
    }

    var body: some View {
        Group {
            if showsJumpIndicator {
                Button(action: action) {
                    headerContent
                }
                .buttonStyle(.plain)
            } else {
                headerContent
            }
        }
    }

    private var headerContent: some View {
        HStack(spacing: CatalogMetrics.Spacing.sm) {
            Text(title)
                .font(CatalogTypography.sectionTitle)
                .foregroundStyle(.primary)

            if showsJumpIndicator {
                Image(systemName: "chevron.up.chevron.down")
                    .font(CatalogTypography.chipLabel)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, CatalogMetrics.Spacing.sm)
        .padding(.horizontal, CatalogMetrics.Spacing.md)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 0.5)
        }
    }
}
