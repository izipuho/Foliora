import SwiftUI

/// The app medallion, drawn from the same layers as the launch screen's `LaunchMedallion`.
///
/// `SplashMedallionBase` and `SplashMedallionGlyph` are generated together with
/// `LaunchMedallion` by `scripts/generate-launch-assets.py` and share its canvas, so
/// the stacked layers match the launch screen image exactly. Each change of
/// `swingTrigger` plays one swing of the glyph.
struct BrandMedallion: View {
    let side: CGFloat
    let swingTrigger: Int

    /// The length of one swing; the launch sequence waits for it to settle.
    static let swingDuration: Duration = .milliseconds(900)

    private let motion = LaunchBranding.glyphMotion

    var body: some View {
        let pivot = motion.pivot
        let amplitude = motion.amplitude

        ZStack {
            Image("SplashMedallionBase")
                .resizable()

            Image("SplashMedallionGlyph")
                .resizable()
                .keyframeAnimator(initialValue: 0.0, trigger: swingTrigger) { glyph, angle in
                    glyph.rotationEffect(.degrees(angle), anchor: pivot)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(10 * amplitude, duration: 0.18)
                        CubicKeyframe(-7 * amplitude, duration: 0.18)
                        CubicKeyframe(4 * amplitude, duration: 0.18)
                        CubicKeyframe(-2 * amplitude, duration: 0.18)
                        CubicKeyframe(0, duration: 0.18)
                    }
                }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

#Preview {
    BrandMedallion(side: 220, swingTrigger: 0)
}
