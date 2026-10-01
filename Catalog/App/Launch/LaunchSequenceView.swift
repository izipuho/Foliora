import SwiftUI

/// Takes over from the system launch screen and leads into the app or the first launch flow.
///
/// The first frame repeats `LaunchScreen.storyboard` exactly — the wordmark at the top
/// of the safe area and the medallion at the center of the screen — so the handoff from
/// the system launch screen is invisible. After that:
///
/// - The glyph swings from the first frame, and the splash always stays for at least
///   two swings, so it reads as a deliberate moment instead of a flash. A greeting
///   appears after the first swing.
/// - A returning user goes to the app after those two swings, or after the swing
///   during which the data becomes ready, whichever is later.
/// - A new user sees the intro: the medallion rises under the wordmark, the product
///   name and the arcs appear, and the first launch flow opens on the same backdrop.
///
/// With Reduce Motion on, nothing moves; elements only fade.
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
        /// The first launch intro: the medallion has risen, the arcs are shown.
        case intro
        /// The first launch flow is on screen.
        case onboarding
    }

    @State private var phase = Phase.launch
    @State private var showsOnboarding: Bool?
    @State private var isIntroFinished = false
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
    private static let minimumSwings = 2
    private static let introDuration: Duration = .milliseconds(600)
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

            ZStack {
                BrandBackdrop(showsArcs: phase != .launch)

                content(bottomInset: max(0, rightArcHeight - proxy.safeAreaInsets.bottom))

                medallion(screenCenterY: screenCenterY)

                greetingLabel(leftArcHeight: leftArcHeight)
            }
        }
        .task(id: needsOnboarding) {
            await startIntroIfNeeded()
        }
        .task {
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

    /// The medallion, centered on the screen like the launch screen's image view.
    private func medallion(screenCenterY: CGFloat) -> some View {
        let side = metrics.medallionSide
        let risesInIntro = phase != .launch && !reduceMotion
        // Places the scaled medallion just under the product name.
        let introOffset = subtitleBottom + Self.medallionSpacing + side * Self.introScale / 2 - screenCenterY

        return BrandMedallion(side: side, swingTrigger: swingTrigger)
            .scaleEffect(risesInIntro ? Self.introScale : 1)
            .offset(y: risesInIntro ? introOffset : 0)
            .opacity(isMedallionHidden ? 0 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
    }

    private func greetingLabel(leftArcHeight: CGFloat) -> some View {
        Text(greeting)
            .font(.largeTitle)
            .foregroundStyle(Color("LightAccent"))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, CatalogMetrics.Spacing.xl)
            // Rests on the left arc, as in the previous splash.
            .padding(.bottom, leftArcHeight - CatalogMetrics.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()
            .opacity(showsGreeting ? 1 : 0)
            .accessibilityHidden(!showsGreeting)
    }

    // MARK: - Sequence

    private var fade: Animation {
        .easeInOut(duration: 0.25)
    }

    /// Plays the intro for a new user; a returning user skips it.
    private func startIntroIfNeeded() async {
        guard let needsOnboarding, showsOnboarding == nil else { return }
        showsOnboarding = needsOnboarding

        if needsOnboarding {
            withAnimation(reduceMotion ? fade : .easeInOut(duration: 0.6)) {
                phase = .intro
                showsGreeting = true
            }
            try? await Task.sleep(for: reduceMotion ? Self.fadeDuration : Self.introDuration)
        }

        isIntroFinished = true
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

            if completedSwings >= Self.minimumSwings, isReady, isIntroFinished {
                continueIfPossible()
                return
            }
        }
    }

    /// Moves on once both the data and the intro are ready.
    private func continueIfPossible() {
        guard isReady, isIntroFinished, completedSwings >= Self.minimumSwings,
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
