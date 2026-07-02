import SwiftUI

struct BellCatalogSelectionBottomPanel: View {
    let selectedCount: Int
    let accentColor: Color
    let bottomSafeAreaInset: CGFloat
    let onMove: () -> Void
    let onDelete: () -> Void

    private var selectedBellCountText: String {
        String.localizedStringWithFormat(
            String(localized: "bell_catalog.selection.selected_count"),
            selectedCount
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            panelBackground
                .padding(.bottom, -bottomSafeAreaInset)

            HStack(alignment: .center, spacing: CatalogMetrics.Spacing.lg) {
                Button(action: onMove) {
                    Image(systemName: "folder")
                        .font(CatalogTypography.cardTitle)
                        .foregroundStyle(accentColor)
                        .frame(width: 48, height: 48)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Circle()
                                        .fill(accentColor.opacity(0.12))
                                }
                        }
                }
                .buttonStyle(.plain)

                Text(selectedBellCountText)
                    .font(CatalogTypography.cardTitle)
                    .foregroundStyle(CatalogMediaContrast.onMediaPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minWidth: 150)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(CatalogTypography.cardTitle)
                        .foregroundStyle(CatalogSemanticColors.destructive)
                        .frame(width: 48, height: 48)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Circle()
                                        .fill(CatalogSemanticColors.destructive.opacity(0.10))
                                }
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, CatalogMetrics.Insets.screen)
            .padding(.vertical, CatalogMetrics.Spacing.lg)
        }
    }

    private var panelBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}
