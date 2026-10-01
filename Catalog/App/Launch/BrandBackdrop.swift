import SwiftUI

/// The branded background behind the splash and the first launch flow:
/// the launch background color and, once the splash takes over, the arcs along the bottom.
struct BrandBackdrop: View {
    var showsArcs: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The height of the lower arc band; content above the arcs keeps clear of it.
    static let arcBandHeight: CGFloat = 146
    /// The height of the left arc, which rises higher than the band at the leading edge.
    static let leftArcHeight: CGFloat = 271

    var body: some View {
        ZStack(alignment: .bottom) {
            Color("LaunchBackground")

            if showsArcs {
                ZStack(alignment: .bottom) {
                    Image("ArcRight")
                        .resizable()
                        .frame(height: Self.arcBandHeight)

                    Image("ArcLeft")
                        .resizable()
                        .frame(height: Self.leftArcHeight)
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
}

#Preview {
    BrandBackdrop(showsArcs: true)
}
