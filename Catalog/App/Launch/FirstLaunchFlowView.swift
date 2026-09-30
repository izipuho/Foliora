import CloudKit
import SwiftUI
import Translation

/// Guides a new user through the first launch: introduction, translation setup,
/// a tour of the app's features, iCloud status, and the final confirmation.
///
/// Action steps only move forward through their buttons, so none of them can be
/// swiped past. The feature tour is the one place that pages by swiping.
struct FirstLaunchFlowView: View {
    private enum Step: Hashable {
        case profile
        case translation
        case tour
        case iCloud
        case ready
    }

    @State private var step: Step
    @State private var translationState: TranslationPreparationState?
    @State private var isPreparingTranslation = false
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var iCloudStatus: CKAccountStatus?
    @State private var userName: String
    @State private var tourPageID: String
    @FocusState private var isUserNameFocused: Bool

    private let tourPages: [OnboardingTourPage]
    private let translator = TextTranslator(sourceLanguage: Locale.Language(identifier: "en"))
    let onFinished: @MainActor () -> Void

    init(onFinished: @escaping @MainActor () -> Void) {
        let pages = OnboardingTourPage.pages(for: CollectionAppLink.currentAppKind)

        _step = State(initialValue: ProfileSettings.isIntroductionAnswered ? .translation : .profile)
        _userName = State(initialValue: ProfileSettings.displayName ?? "")
        _tourPageID = State(initialValue: pages.first?.id ?? "")
        tourPages = pages
        self.onFinished = onFinished
    }

    var body: some View {
        ZStack {
            currentStep
                .id(step)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    )
                )
        }
        .clipped()
        // Attached to the root so that leaving the translation step never cancels a download.
        .translationTask(translationConfiguration) { session in
            nonisolated(unsafe) let translationSession = session
            await prepareTranslation(using: translationSession)
        }
        .task {
            await refreshTranslationState()
        }
        .task {
            await refreshICloudStatus()
        }
    }

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case .profile:
            profileStep
        case .translation:
            translationStep
        case .tour:
            tourStep
        case .iCloud:
            iCloudStep
        case .ready:
            readyStep
        }
    }

    // MARK: - Steps

    private var profileStep: some View {
        onboardingPage(
            title: "onboarding.introduce.title",
            description: "onboarding.introduce.description",
            primaryTitle: "onboarding.introduce.save_name",
            primaryAction: saveName,
            secondaryAction: {
                ProfileSettings.skipIntroduction()
                isUserNameFocused = false
                advance(from: .profile)
            }
        ) {
            TextField("common.name", text: $userName)
                .textContentType(.name)
                .submitLabel(.next)
                .onSubmit(saveName)
                .catalogSurfaceTile()
                .frame(maxWidth: 250)
                .focused($isUserNameFocused)
        }
    }

    private var translationStep: some View {
        onboardingPage(
            title: "onboarding.download_model.title",
            description: "onboarding.download_model.description",
            primaryTitle: "common.download",
            primaryDisabled: translationState != .needsDownload || isPreparingTranslation,
            primaryAction: startTranslationDownload,
            secondaryAction: {
                advance(from: .translation)
            }
        ) {
            if translationState == nil || isPreparingTranslation {
                ProgressView()
            }
        }
    }

    private var tourStep: some View {
        VStack(spacing: CatalogMetrics.Spacing.xl) {
            TabView(selection: $tourPageID) {
                ForEach(tourPages) { page in
                    tourSlide(page)
                        .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            actionButtons(
                primaryTitle: isOnLastTourPage ? "common.continue" : "common.next",
                primaryAction: showNextTourPage,
                secondaryAction: isOnLastTourPage ? nil : {
                    advance(from: .tour)
                }
            )
            .frame(maxWidth: 420)
            .padding(.horizontal, CatalogMetrics.Insets.screen)
        }
    }

    private var iCloudStep: some View {
        onboardingPage(
            title: iCloudTitle,
            description: iCloudDescription,
            primaryTitle: "common.continue",
            primaryAction: {
                advance(from: .iCloud)
            }
        ) {
            if let iCloudStatus {
                Image(systemName: iCloudSymbol(for: iCloudStatus))
                    .font(.system(size: 44))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color("LightAccent"))
                    .accessibilityHidden(true)
            } else {
                ProgressView()
            }
        }
    }

    private var readyStep: some View {
        onboardingPage(
            title: "onboarding.ready.title",
            description: "onboarding.ready.description",
            primaryTitle: "onboarding.ready.start",
            primaryAction: {
                OnboardingProgress.markCompleted()
                onFinished()
            }
        ) {
            EmptyView()
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private func onboardingPage<Content: View>(
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        primaryTitle: LocalizedStringKey,
        primaryDisabled: Bool = false,
        primaryAction: @escaping () -> Void,
        secondaryAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: CatalogMetrics.Spacing.xl) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color("LightAccent"))
                .multilineTextAlignment(.center)

            Text(description)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            content()

            actionButtons(
                primaryTitle: primaryTitle,
                primaryDisabled: primaryDisabled,
                primaryAction: primaryAction,
                secondaryAction: secondaryAction
            )
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, CatalogMetrics.Insets.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tourSlide(_ page: OnboardingTourPage) -> some View {
        VStack(spacing: CatalogMetrics.Spacing.lg) {
            Image(systemName: page.systemImage)
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color("LightAccent"))
                .accessibilityHidden(true)

            Text(page.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color("LightAccent"))
                .multilineTextAlignment(.center)

            Text(page.description)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, CatalogMetrics.Insets.screen)
        // Leaves room for the page indicator below the text.
        .padding(.bottom, CatalogMetrics.Spacing.xl)
        .accessibilityElement(children: .combine)
    }

    private func actionButtons(
        primaryTitle: LocalizedStringKey,
        primaryDisabled: Bool = false,
        primaryAction: @escaping () -> Void,
        secondaryAction: (() -> Void)?
    ) -> some View {
        HStack(spacing: CatalogMetrics.Spacing.md) {
            Button(primaryTitle, action: primaryAction)
                .font(.title3)
                .foregroundStyle(.primary)
                .buttonStyle(.glassProminent)
                .tint(Color("LightAccent"))
                .disabled(primaryDisabled)
                .frame(maxWidth: .infinity)

            if let secondaryAction {
                Button("common.skip", action: secondaryAction)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .buttonStyle(.glass)
                    .tint(Color("LightAccent"))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Navigation

    @MainActor
    private func advance(from current: Step) {
        guard current == step else { return }

        let next: Step
        switch current {
        case .profile:
            next = shouldShowTranslationStep ? .translation : .tour
        case .translation:
            next = .tour
        case .tour:
            next = .iCloud
        case .iCloud:
            next = .ready
        case .ready:
            return
        }

        withAnimation(.smooth) {
            step = next
        }
    }

    /// The translation step stays while the check is still running, and shows
    /// a progress indicator until the result arrives.
    private var shouldShowTranslationStep: Bool {
        translationState == nil || translationState == .needsDownload
    }

    private var isOnLastTourPage: Bool {
        tourPageID == tourPages.last?.id
    }

    @MainActor
    private func showNextTourPage() {
        guard let index = tourPages.firstIndex(where: { $0.id == tourPageID }),
              index + 1 < tourPages.count
        else {
            advance(from: .tour)
            return
        }

        withAnimation {
            tourPageID = tourPages[index + 1].id
        }
    }

    @MainActor
    private func saveName() {
        ProfileSettings.setDisplayName(userName)
        isUserNameFocused = false
        advance(from: .profile)
    }

    // MARK: - Translation

    @MainActor
    private func refreshTranslationState() async {
        let state = await translator.preparationState()
        TranslationPreparationCache.record(state)
        translationState = state

        if state != .needsDownload {
            advance(from: .translation)
        }
    }

    @MainActor
    private func startTranslationDownload() {
        isPreparingTranslation = true
        translationConfiguration = TranslationSession.Configuration(
            source: translator.sourceLanguage,
            target: translator.targetLanguage()
        )
    }

    nonisolated private func prepareTranslation(using session: TranslationSession) async {
        do {
            try await session.prepareTranslation()
        } catch {
            StartupSignposts.logger.error(
                "Translation model preparation failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        await MainActor.run {
            translationConfiguration = nil
            isPreparingTranslation = false
        }
        await refreshTranslationState()
    }

    // MARK: - iCloud

    @MainActor
    private func refreshICloudStatus() async {
        let container = FolioraAppDelegate.coreDataContainer
            .flatMap(FolioraCoreDataStack.cloudKitContainerIdentifier(from:))
            .map(CKContainer.init(identifier:))
            ?? CKContainer.default()

        do {
            iCloudStatus = try await container.accountStatus()
        } catch {
            StartupSignposts.logger.error(
                "iCloud account status check failed: \(error.localizedDescription, privacy: .public)"
            )
            iCloudStatus = .couldNotDetermine
        }
    }

    private var iCloudTitle: LocalizedStringKey {
        switch iCloudStatus {
        case nil:
            "onboarding.icloud.checking.title"
        case .available:
            "onboarding.icloud.available.title"
        case .noAccount:
            "onboarding.icloud.no_account.title"
        default:
            "onboarding.icloud.unavailable.title"
        }
    }

    private var iCloudDescription: LocalizedStringKey {
        switch iCloudStatus {
        case nil:
            "onboarding.icloud.checking.description"
        case .available:
            "onboarding.icloud.available.description"
        case .noAccount:
            "onboarding.icloud.no_account.description"
        default:
            "onboarding.icloud.unavailable.description"
        }
    }

    private func iCloudSymbol(for status: CKAccountStatus) -> String {
        switch status {
        case .available:
            "checkmark.icloud"
        case .noAccount:
            "xmark.icloud"
        default:
            "exclamationmark.icloud"
        }
    }
}

#Preview {
    FirstLaunchFlowView {}
}
