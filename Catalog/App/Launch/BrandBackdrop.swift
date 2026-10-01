import SwiftUI

/// The branded background behind the splash and the first launch flow:
/// the launch background color and, once the splash takes over, the arcs along the bottom.
///
/// The arcs are drawn in code, filled with each app's `ArcLeft` and `ArcRight` colors,
/// with the soft light rim along their top edge from the Figma design.
struct BrandBackdrop: View {
    var showsArcs: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color("LaunchBackground")

            if showsArcs {
                ZStack {
                    arc(.right, color: Color("ArcRight"))
                    arc(.left, color: Color("ArcLeft"))
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
