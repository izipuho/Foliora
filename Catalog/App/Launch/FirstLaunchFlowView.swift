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

    var body: some View {
        TabView(selection: $step) {
            VStack(spacing: CatalogMetrics.Spacing.xl) {
                if needsTranslationModelDownload {
                    Text("translation.download_model.title")
                        .font(CatalogTypography.cardTitle)
                        .foregroundStyle(Color("LightAccent"))
                        .multilineTextAlignment(.center)

                    Text("translation.download_model.description")
                        .font(CatalogTypography.cardSubtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: CatalogMetrics.Spacing.md) {
                        Button("common.download") {
                            prepareTranslation()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isPreparingTranslation)
                        .frame(maxWidth: .infinity)

                        Button("common.skip") {
                            finishTranslationStep()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isPreparingTranslation)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, CatalogMetrics.Insets.screen)
            .task {
                await checkPreparationStateIfNeeded()
            }
            .translationTask(translationConfiguration) { session in
                nonisolated(unsafe) let translationSession = session
                await prepareTranslation(using: translationSession)
            }
            .tag(Step.translation)

            VStack(spacing: CatalogMetrics.Spacing.xl) {
                Text("initialize.introduce.title")
                    .font(CatalogTypography.cardTitle)
                    .foregroundStyle(Color("LightAccent"))
                    .multilineTextAlignment(.center)

                Text("initialize.introduce.description")
                    .font(CatalogTypography.cardSubtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("common.name", text: $userName)
                    .textContentType(.name)
                    .catalogSurfaceTile()

                HStack(spacing: CatalogMetrics.Spacing.md) {
                    Button("common.continue") {
                        let displayName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if displayName.isEmpty {
                            NSUbiquitousKeyValueStore.default.removeObject(forKey: "foliora.profile.displayName")
                        } else {
                            NSUbiquitousKeyValueStore.default.set(displayName, forKey: "foliora.profile.displayName")
                        }
                        NSUbiquitousKeyValueStore.default.removeObject(forKey: "foliora.profile.didSkipIntroduction")
                        onFinished()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                    Button("common.skip") {
                        NSUbiquitousKeyValueStore.default.set(true, forKey: "foliora.profile.didSkipIntroduction")
                        onFinished()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, CatalogMetrics.Insets.screen)
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
