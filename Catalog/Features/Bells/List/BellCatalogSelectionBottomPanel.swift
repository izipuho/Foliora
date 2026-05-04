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
                Button(action: onMove) {
                    Image(systemName: "folder")
                        .font(.title3.weight(.semibold))
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
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(minWidth: 150)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(width: 48, height: 48)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Circle()
                                        .fill(Color.red.opacity(0.10))
                                }
                        }
                }
                .buttonStyle(.plain)
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
