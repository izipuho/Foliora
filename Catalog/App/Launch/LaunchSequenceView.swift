import SwiftUI

/// Takes over from the system launch screen and leads into the app or the first launch flow.
///
/// The first frame repeats `LaunchScreen.storyboard` exactly — the wordmark at the top
/// of the safe area and the medallion at the center of the screen — so the handoff from
/// the system launch screen is invisible. After that:
///
/// - A returning user goes straight to the app once its data is ready. The splash has
///   no minimum duration; the glyph starts swinging only when loading takes a moment,
///   and a greeting appears only when it takes longer than that.
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
    @State private var swingSettlesAt = ContinuousClock.now
    @State private var isMedallionHidden = false
    @State private var showsGreeting = false
    @State private var greeting = LaunchBranding.randomGreeting()
    @State private var subtitleBottom: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Waiting this long before swinging keeps fast launches completely still.
    private static let swingDelay: Duration = .milliseconds(300)
    private static let greetingDelay: Duration = .milliseconds(800)
    private static let introDuration: Duration = .milliseconds(600)
    private static let fadeDuration: Duration = .milliseconds(250)
    private static let introScale: CGFloat = 0.75
    private static let medallionSpacing: CGFloat = CatalogMetrics.Spacing.xl

    private var metrics: LaunchBranding.Metrics {
        LaunchBranding.Metrics(isRegular: horizontalSizeClass == .regular && verticalSizeClass == .regular)
    }

    var body: some View {
        GeometryReader { proxy in
            let screenCenterY = (proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom) / 2

            ZStack {
                BrandBackdrop(showsArcs: phase != .launch)

                content(bottomInset: max(0, BrandBackdrop.arcBandHeight - proxy.safeAreaInsets.bottom))

                medallion(screenCenterY: screenCenterY)

                greetingLabel
            }
        }
        .task(id: needsOnboarding) {
            await startIntroIfNeeded()
        }
        .task(id: isApplicationReady) {
            if isApplicationReady {
                await settleAndContinue()
            } else {
                await swingWhileLoading()
            }
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

    private var greetingLabel: some View {
        Text(greeting)
            .font(.largeTitle)
            .foregroundStyle(Color("LightAccent"))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, CatalogMetrics.Spacing.xl)
            // Rests on the left arc, as in the previous splash.
            .padding(.bottom, BrandBackdrop.leftArcHeight - CatalogMetrics.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea()
            .opacity(showsGreeting ? 1 : 0)
            .accessibilityHidden(!showsGreeting)
    }

    // MARK: - Sequence

    private var fade: Animation {
        .easeInOut(duration: 0.25)
    }

    /// Plays the intro for a new user, or lets a returning user through as soon as data is ready.
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
        continueIfPossible()
    }

    /// Swings the glyph while data loads, and greets the user if loading takes a while.
    private func swingWhileLoading() async {
        let greetingTime = ContinuousClock.now + Self.greetingDelay
        try? await Task.sleep(for: Self.swingDelay)

        while !Task.isCancelled {
            if !reduceMotion {
                swingTrigger += 1
                swingSettlesAt = .now + BrandMedallion.swingDuration
            }
            try? await Task.sleep(for: BrandMedallion.swingDuration)

            if !showsGreeting, ContinuousClock.now >= greetingTime {
                withAnimation(fade) {
                    showsGreeting = true
                }
            }
        }
    }

    /// Lets the current swing come to rest before moving on.
    private func settleAndContinue() async {
        let remaining = swingSettlesAt - .now
        if remaining > .zero {
            try? await Task.sleep(for: remaining)
        }
        guard !Task.isCancelled else { return }

        StartupSignposts.signposter.emitEvent("applicationReady")
        isReady = true
        continueIfPossible()
    }

    /// Moves on once both the data and the intro are ready.
    private func continueIfPossible() {
        guard isReady, isIntroFinished, let showsOnboarding, phase != .onboarding, !didFinish else { return }

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
