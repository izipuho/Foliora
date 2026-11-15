import SwiftUI

/// One of the two arcs along the bottom of the branded backdrop.
///
/// The curves come from the Figma launch screens, drawn on a 430 × 935 pt frame.
/// Horizontally an arc always spans the full width; vertically it follows the
/// screen height, so taller screens get taller arcs and the curves flatten less
/// on wide screens than with a fixed height.
///
/// Only the top curve is meant to show: the path runs past the leading, trailing
/// and bottom edges of its rect, so effects such as the inner rim stay off screen
/// along those edges.
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
    /// How far the path runs past the screen edges other than the top curve.
    private static let overshoot: CGFloat = 60

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

        let outside = Self.overshoot
        let bottom = rect.maxY + outside

        var path = Path()
        switch side {
        case .left:
            let start = point(0, 661)
            let end = point(430, 926.573)
            path.move(to: CGPoint(x: start.x - outside, y: start.y))
            path.addLine(to: start)
            path.addCurve(to: end, control1: point(95.031, 804.867), control2: point(250.369, 905.397))
            path.addLine(to: CGPoint(x: end.x + outside, y: end.y))
            path.addLine(to: CGPoint(x: end.x + outside, y: bottom))
            path.addLine(to: CGPoint(x: start.x - outside, y: bottom))
        case .right:
            let start = point(0, 888.707)
            let end = point(430, 787.11)
            path.move(to: CGPoint(x: start.x - outside, y: bottom))
            path.addLine(to: CGPoint(x: start.x - outside, y: start.y))
            path.addLine(to: start)
            path.addCurve(to: point(46, 890.063), control1: point(15.218, 889.607), control2: point(30.556, 890.063))
            path.addCurve(to: end, control1: point(185.919, 890.063), control2: point(317.083, 852.583))
            path.addLine(to: CGPoint(x: end.x + outside, y: end.y))
            path.addLine(to: CGPoint(x: end.x + outside, y: bottom))
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        ArcShape(side: .right).fill(BrandBackdrop.rightArcColor)
        ArcShape(side: .left).fill(BrandBackdrop.leftArcColor)
    }
    .ignoresSafeArea()
}
