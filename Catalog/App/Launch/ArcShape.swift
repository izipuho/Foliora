import SwiftUI

/// One of the two arcs along the bottom of the branded backdrop.
///
/// The curves come from the Figma launch screens, drawn on a 430 × 935 pt frame.
/// Horizontally an arc always spans the full width; vertically it follows the
/// screen height, so taller screens get taller arcs and the curves flatten less
/// on wide screens than with a fixed height.
struct ArcShape: Shape {
    enum Side {
        /// Rises at the leading edge and runs down to the trailing edge.
        case left
        /// Rises at the trailing edge, over a low band along the bottom.
        case right
    }

    let side: Side

    /// The Figma frame the curves were drawn on.
    private static let designSize = CGSize(width: 430, height: 935)

    /// How high the arc reaches on a screen of the given height.
    static func height(of side: Side, screenHeight: CGFloat) -> CGFloat {
        let top: CGFloat = switch side {
        case .left: 661
        case .right: 787.11
        }
        return (designSize.height - top) * screenHeight / designSize.height
    }

    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / Self.designSize.width
        let scaleY = rect.height / Self.designSize.height

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scaleX, y: rect.minY + y * scaleY)
        }

        var path = Path()
        switch side {
        case .left:
            path.move(to: point(0, 661))
            path.addCurve(to: point(430, 926.573), control1: point(95.031, 804.867), control2: point(250.369, 905.397))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .right:
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: point(0, 888.707))
            path.addCurve(to: point(46, 890.063), control1: point(15.218, 889.607), control2: point(30.556, 890.063))
            path.addCurve(to: point(430, 787.11), control1: point(185.919, 890.063), control2: point(317.083, 852.583))
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        ArcShape(side: .right).fill(Color("ArcRight"))
        ArcShape(side: .left).fill(Color("ArcLeft"))
    }
    .ignoresSafeArea()
}
