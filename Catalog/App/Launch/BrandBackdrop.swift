import SwiftUI

/// The branded background of the launch screen, the splash and the first launch flow:
/// the launch background color and the arcs along the bottom.
///
/// `behindArcs` is drawn between the background and the arcs, where the launch
/// screen draws the medallion.
struct BrandBackdrop<BehindArcs: View>: View {
    @ViewBuilder var behindArcs: BehindArcs

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            behindArcs

            ZStack(alignment: .bottom) {
                Image("ArcRight")
                    .resizable()
                    .frame(height: LaunchBranding.Layout.rightArcHeight)

                Image("ArcLeft")
                    .resizable()
                    .frame(height: LaunchBranding.Layout.leftArcHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}

extension BrandBackdrop where BehindArcs == EmptyView {
    init() {
        self.init { EmptyView() }
    }
}

#Preview {
    BrandBackdrop()
}
