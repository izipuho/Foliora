import SwiftUI
import Translation

struct FirstLaunchFlowView: View {
    private enum Step: Hashable {
        case profile
        case translation
        case ready
    }

    @State private var step: Step = .profile
    @State private var didCheckPreparationState = false
    @State private var needsTranslationModelDownload = false
    @State private var isPreparingTranslation = false
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var userName = ""

    private let translator = TextTranslator(sourceLanguage: Locale.Language(identifier: "en"))
    let onFinished: @MainActor () -> Void
    
    @ViewBuilder
    private func onboardingPage<Content: View>(
        title: LocalizedStringKey,
        description: LocalizedStringKey,
        primaryTitle: LocalizedStringKey,
        primaryDisabled: Bool = false,
        primaryAction: @escaping () -> Void,
        skipDisabled: Bool = false,
        skipAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: CatalogMetrics.Spacing.xl) {
            Text(title)
                .font(CatalogTypography.cardTitle)
                .foregroundStyle(Color("LightAccent"))
                .multilineTextAlignment(.center)

            Text(description)
                .font(CatalogTypography.cardSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            content()

            HStack(spacing: CatalogMetrics.Spacing.md) {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(primaryDisabled)
                    .frame(maxWidth: .infinity)

                if let skipAction {
                    Button("common.skip", action: skipAction)
                        .buttonStyle(.bordered)
                        .disabled(skipDisabled)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, CatalogMetrics.Insets.screen)
    }

    var body: some View {
        TabView(selection: $step) {
            onboardingPage(
                title: "onboarding.introduce.title",
                description: "onboarding.introduce.description",
                primaryTitle: "common.continue",
                primaryAction: {
                    let displayName = userName.trimmingCharacters(in: .whitespacesAndNewlines)

                    if displayName.isEmpty {
                        NSUbiquitousKeyValueStore.default.removeObject(
                            forKey: "foliora.profile.displayName"
                        )
                    } else {
                        NSUbiquitousKeyValueStore.default.set(
                            displayName,
                            forKey: "foliora.profile.displayName"
                        )
                    }

                    NSUbiquitousKeyValueStore.default.removeObject(
                        forKey: "foliora.profile.didSkipIntroduction"
                    )

                    continueAfterProfile()
                },
                skipAction: {
                    NSUbiquitousKeyValueStore.default.set(
                        true,
                        forKey: "foliora.profile.didSkipIntroduction"
                    )
                    continueAfterProfile()
                }
            ) {
                TextField("common.name", text: $userName)
                    .textContentType(.name)
                    .catalogSurfaceTile()
            }
            .tag(Step.profile)

            onboardingPage(
                title: "onboarding.download_model.title",
                description: "onboarding.download_model.description",
                primaryTitle: "common.download",
                primaryDisabled: isPreparingTranslation,
                primaryAction: {
                    prepareTranslation()
                },
                skipDisabled: isPreparingTranslation,
                skipAction: {
                    finishTranslationStep()
                }
            ) {
                EmptyView()
            }
            .translationTask(translationConfiguration) { session in
                nonisolated(unsafe) let translationSession = session
                await prepareTranslation(using: translationSession)
            }
            .tag(Step.translation)

            onboardingPage(
                title: "onboarding.ready.title",
                description: "onboarding.ready.description",
                primaryTitle: "onboarding.ready.start",
                primaryAction: {
                    onFinished()
                }
            ) {
                ZStack {
                    Circle()
                        .glassEffect(.clear.tint(.green))
                        .frame(width: 96, height: 96)

                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .tag(Step.ready)
        }
        .task {
            await checkPreparationStateIfNeeded()
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    @MainActor
    private func checkPreparationStateIfNeeded() async {
        guard !didCheckPreparationState else { return }

        await refreshPreparationState()
        didCheckPreparationState = true
    }

    @MainActor
    private func refreshPreparationState() async {
        let preparationState = await translator.preparationState()

        guard preparationState == .needsDownload else {
            needsTranslationModelDownload = false
            if step != .profile {
                finishTranslationStep()
            }
            return
        }

        needsTranslationModelDownload = true
    }

    @MainActor
    private func finishTranslationStep() {
        step = .ready
    }

    @MainActor
    private func continueAfterProfile() {
        if didCheckPreparationState, !needsTranslationModelDownload {
            step = .ready
        } else {
            step = .translation
        }
    }

    @MainActor
    private func prepareTranslation() {
        isPreparingTranslation = true
        needsTranslationModelDownload = false
        translationConfiguration = TranslationSession.Configuration(
            source: translator.sourceLanguage,
            target: translator.targetLanguage()
        )
    }

    nonisolated private func prepareTranslation(using session: TranslationSession) async {
        try? await session.prepareTranslation()

        await MainActor.run {
            translationConfiguration = nil
            isPreparingTranslation = false
        }
        await refreshPreparationState()
    }
}
