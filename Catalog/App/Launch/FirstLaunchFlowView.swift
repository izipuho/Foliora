import SwiftUI
import Translation

struct FirstLaunchFlowView: View {
    private enum Step: Hashable {
        case translation
        case profile
    }

    @State private var step: Step = .translation
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
        skipAction: @escaping () -> Void,
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

                Button("common.skip", action: skipAction)
                    .buttonStyle(.bordered)
                    .disabled(skipDisabled)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: 420)
        .padding(.horizontal, CatalogMetrics.Insets.screen)
    }

    var body: some View {
        TabView(selection: $step) {
            
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
            .task {
                await checkPreparationStateIfNeeded()
            }
            .translationTask(translationConfiguration) { session in
                nonisolated(unsafe) let translationSession = session
                await prepareTranslation(using: translationSession)
            }
            .tag(Step.translation)

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

                    onFinished()
                },
                skipAction: {
                    NSUbiquitousKeyValueStore.default.set(
                        true,
                        forKey: "foliora.profile.didSkipIntroduction"
                    )
                    onFinished()
                }
            ) {
                TextField("common.name", text: $userName)
                    .textContentType(.name)
                    .catalogSurfaceTile()
            }
            .tag(Step.profile)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    @MainActor
    private func checkPreparationStateIfNeeded() async {
        guard !didCheckPreparationState else { return }

        didCheckPreparationState = true
        await refreshPreparationState()
    }

    @MainActor
    private func refreshPreparationState() async {
        let preparationState = await translator.preparationState()

        guard preparationState == .needsDownload else {
            finishTranslationStep()
            return
        }

        needsTranslationModelDownload = true
    }

    @MainActor
    private func finishTranslationStep() {
        let store = NSUbiquitousKeyValueStore.default
        let displayName = store.string(forKey: "foliora.profile.displayName")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard displayName.isEmpty, !store.bool(forKey: "foliora.profile.didSkipIntroduction") else {
            onFinished()
            return
        }

        step = .profile
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
