import DesignSystem
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

            HStack(alignment: .center, spacing: 18) {
                CatalogIconActionButton(
                    systemImage: "folder",
                    tint: accentColor,
                    backgroundTint: accentColor.opacity(0.12),
                    action: onMove
                )

                Text(selectedBellCountText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minWidth: 150)

                CatalogIconActionButton(
                    systemImage: "trash",
                    tint: .red,
                    backgroundTint: Color.red.opacity(0.10),
                    role: .destructive,
                    action: onDelete
                )
            }
            .padding(.horizontal, CatalogLayoutInsets.screen)
            .padding(.top, 24)
            .padding(.bottom, 8)
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
