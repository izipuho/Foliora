import SwiftUI

/// The branded background behind the splash and the first launch flow:
/// the launch background color and, once the splash takes over, the arcs along the bottom.
///
/// The arcs are drawn in code, with the soft light rim along their top edge from the
/// Figma design. Their colors follow the medallion, which is the app's `AccentColor`:
/// the left arc is slightly darker, the right arc a light tint.
///
/// Every app gets its arcs from its accent color alone, with no extra assets.
struct BrandBackdrop: View {
    var showsArcs: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let medallion = Color("AccentColor")
    static let leftArcColor = medallion.mix(with: .black, by: 0.15, in: .device)
    static let rightArcColor = medallion.mix(with: .white, by: 0.75, in: .device)

    var body: some View {
        ZStack {
            Color("LaunchBackground")

            if showsArcs {
                ZStack {
                    arc(.right, color: Self.rightArcColor)
                    arc(.left, color: Self.leftArcColor)
                }
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func arc(_ side: ArcShape.Side, color: Color) -> some View {
        ArcShape(side: side)
            .fill(color.shadow(.inner(color: .white.opacity(0.6), radius: 10, y: 20 / 3)))
    }
}

#Preview {
    BrandBackdrop(showsArcs: true)
}
