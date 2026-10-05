import SwiftUI

/// Takes over from the system launch screen and leads into the app or the first launch flow.
///
/// The first frame repeats `LaunchScreen.storyboard` exactly — the wordmark at the top
/// of the safe area and the medallion at the center of the screen — so the handoff from
/// the system launch screen is invisible. After that:
///
/// - As soon as the splash takes over, on every launch, the arcs come in along the
///   bottom, the medallion rises under the wordmark and the product name appears.
/// - The glyph swings from the first frame, and the splash always stays for at least
///   two swings, so it reads as a deliberate moment instead of a flash. A greeting
///   appears after the first swing, in the space between the medallion and the arcs.
/// - A returning user goes to the app after those two swings, or after the swing
///   during which the data becomes ready, whichever is later.
/// - A new user gets the first launch flow on the same backdrop instead.
///
/// With Reduce Motion on, nothing moves; elements only fade, and the medallion
/// stays at the center.
struct LaunchSequenceView: View {
    /// Whether the app's data stack is ready to show the catalog.
    let isApplicationReady: Bool
    /// Whether the first launch flow is needed, or `nil` until that is decided.
    let needsOnboarding: Bool?
    /// Called once the user can move on to the app.
    let onFinished: @MainActor () -> Void

    private enum Phase {
        /// Matches the system launch screen.
        case launch
        /// The splash proper: the medallion has risen, the product name is shown.
        case intro
        /// The first launch flow is on screen.
        case onboarding
    }

    @State private var phase = Phase.launch
    /// Off for the first frame, which has to match the system launch screen.
    @State private var showsArcs = false
    @State private var showsOnboarding: Bool?
    @State private var isReady = false
    @State private var didFinish = false

    @State private var swingTrigger = 0
    @State private var completedSwings = 0
    @State private var isMedallionHidden = false
    @State private var showsGreeting = false
    @State private var greeting = LaunchBranding.randomGreeting()
    @State private var subtitleBottom: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// The splash never leaves before this many swings have played.
    /// They outlast the medallion's rise, so the splash never leaves mid-rise.
    private static let minimumSwings = 2
    private static let fadeDuration: Duration = .milliseconds(250)
    private static let introScale: CGFloat = 0.75
    private static let medallionSpacing: CGFloat = CatalogMetrics.Spacing.xl

    private var metrics: LaunchBranding.Metrics {
        LaunchBranding.Metrics(isRegular: horizontalSizeClass == .regular && verticalSizeClass == .regular)
    }

    var body: some View {
        GeometryReader { proxy in
            let screenHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            let screenCenterY = screenHeight / 2
            let rightArcHeight = ArcShape.height(of: .right, screenHeight: screenHeight)
            let leftArcHeight = ArcShape.height(of: .left, screenHeight: screenHeight)

            let diameter = metrics.medallionDiameter
            let isMedallionRaised = phase != .launch && !reduceMotion
            let medallionScale = isMedallionRaised ? Self.introScale : 1
            // Raised, the scaled medallion sits just under the product name.
            let medallionCenterY = isMedallionRaised
                ? subtitleBottom + Self.medallionSpacing + diameter * Self.introScale / 2
                : screenCenterY
            let medallionBottom = medallionCenterY + diameter * medallionScale / 2

            // The greeting rests on the left arc, as in the previous splash.
            let greetingBottomInset = leftArcHeight - CatalogMetrics.Spacing.xl
            let greetingHeight = screenHeight - greetingBottomInset - medallionBottom - Self.medallionSpacing

            ZStack {
                BrandBackdrop(showsArcs: showsArcs)

                content(bottomInset: max(0, rightArcHeight - proxy.safeAreaInsets.bottom))

                medallion(scale: medallionScale, offset: medallionCenterY - screenCenterY)

                greetingLabel(height: max(0, greetingHeight), bottomInset: greetingBottomInset)
            }
        }
        .task(id: needsOnboarding) {
            guard let needsOnboarding, showsOnboarding == nil else { return }
            showsOnboarding = needsOnboarding
        }
        .task {
            startIntro()
            await swing()
        }
        .task(id: isApplicationReady) {
            guard isApplicationReady, !isReady else { return }
            StartupSignposts.signposter.emitEvent("applicationReady")
            isReady = true
        }
    }

    // MARK: - Layers

    /// The wordmark, the product name and, on first launch, the first launch flow.
    private func content(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: LaunchBranding.wordmark)
                .font(.system(size: metrics.wordmarkSize))
                .foregroundStyle(Color("AccentColor"))
                .lineLimit(1)

            Text(verbatim: LaunchBranding.productName)
                .font(.system(size: metrics.subtitleSize))
                .foregroundStyle(Color("LightAccent"))
                .lineLimit(1)
                // Localized names can be much longer than "Bells".
                .minimumScaleFactor(0.5)
                .padding(.horizontal, CatalogMetrics.Insets.screen)
                .opacity(phase == .launch ? 0 : 1)
                .accessibilityHidden(phase == .launch)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.frame(in: .global).maxY
                } action: { maxY in
                    subtitleBottom = maxY
                }

            if phase == .onboarding {
                FirstLaunchFlowView {
                    finish()
                }
                .transition(.opacity)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The medallion, laid out at the center of the screen like the launch screen's
    /// image view, then scaled and moved from there.
    private func medallion(scale: CGFloat, offset: CGFloat) -> some View {
        BrandMedallion(side: metrics.medallionSide, swingTrigger: swingTrigger)
            .scaleEffect(scale)
            .offset(y: offset)
            .opacity(isMedallionHidden ? 0 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
    }

    /// The greeting, kept within `height` above `bottomInset` so it never reaches the medallion.
    ///
    /// It is set in the largest text style whose lines all fit in that height. When
    /// even the smallest one does not fit, that one is scaled down.
    private func greetingLabel(height: CGFloat, bottomInset: CGFloat) -> some View {
        ViewThatFits(in: .vertical) {
            greetingText(.largeTitle)
            greetingText(.title)
            greetingText(.title2)
            greetingText(.title3)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: height, alignment: .bottom)
        .padding(.horizontal, CatalogMetrics.Spacing.xl)
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .opacity(showsGreeting ? 1 : 0)
        .accessibilityHidden(!showsGreeting)
    }

    private func greetingText(_ style: Font.TextStyle) -> some View {
        Text(greeting)
            .font(.system(style))
            .foregroundStyle(Color("LightAccent"))
            .multilineTextAlignment(.center)
    }

    // MARK: - Sequence

    private var fade: Animation {
        .easeInOut(duration: 0.25)
    }

    /// The movement of the arcs and the medallion; a fade with Reduce Motion on.
    private var slide: Animation {
        reduceMotion ? fade : .easeInOut(duration: 0.6)
    }

    /// Brings in the arcs and raises the medallion right after the handoff from the
    /// system launch screen.
    private func startIntro() {
        withAnimation(slide) {
            showsArcs = true
            phase = .intro
        }
    }

    /// Swings the glyph until the splash can move on, and greets the user after the first swing.
    ///
    /// The sequence moves on only between swings, so the glyph always comes to rest
    /// first. With Reduce Motion on, the glyph stays still but the timing is the same.
    private func swing() async {
        while !Task.isCancelled, phase != .onboarding, !didFinish {
            if !reduceMotion {
                swingTrigger += 1
            }
            try? await Task.sleep(for: BrandMedallion.swingDuration)
            guard !Task.isCancelled else { return }
            completedSwings += 1

            if !showsGreeting {
                withAnimation(fade) {
                    showsGreeting = true
                }
            }

            if completedSwings >= Self.minimumSwings, isReady, showsOnboarding != nil {
                continueIfPossible()
                return
            }
        }
    }

    /// Moves on once the data is ready and the first launch flow is decided.
    private func continueIfPossible() {
        guard isReady, completedSwings >= Self.minimumSwings,
              let showsOnboarding, phase != .onboarding, !didFinish
        else { return }

        guard showsOnboarding else {
            finish()
            return
        }

        withAnimation(fade) {
            isMedallionHidden = true
            showsGreeting = false
        }
        Task {
            try? await Task.sleep(for: Self.fadeDuration)
            withAnimation(fade) {
                phase = .onboarding
            }
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true

        StartupSignposts.signposter.emitEvent("launchScreenFinished")
        onFinished()
    }
}

#Preview("Returning user") {
    LaunchSequenceView(isApplicationReady: false, needsOnboarding: false) {}
}

#Preview("First launch") {
    LaunchSequenceView(isApplicationReady: true, needsOnboarding: true) {}
}
