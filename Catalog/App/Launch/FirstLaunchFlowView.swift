import SwiftUI
import Translation

struct FirstLaunchFlowView<Content: View>: View {
    private enum Step: Hashable {
        case translation
        case profile
    }

    @State private var step: Step = .translation
    @State private var didFinishFirstLaunchFlow = false
    @State private var didCheckPreparationState = false
    @State private var needsTranslationModelDownload = false
    @State private var isPreparingTranslation = false
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var userName = ""

    private let translator = TextTranslator(sourceLanguage: Locale.Language(identifier: "en"))
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if didFinishFirstLaunchFlow {
            content
        } else {
            TabView(selection: $step) {
                VStack(spacing: 20) {
                    if needsTranslationModelDownload {
                        Text("translation.download_model.description")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)

                        Button("common.download") {
                            prepareTranslation()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isPreparingTranslation)

                        Button("common.skip") {
                            step = .profile
                        }
                        .buttonStyle(.bordered)
                        .disabled(isPreparingTranslation)
                    } else {
                        ProgressView()
                    }
                }
                .padding()
                    .task {
                        await checkPreparationStateIfNeeded()
                    }
                    .translationTask(translationConfiguration) { session in
                        nonisolated(unsafe) let translationSession = session
                        await prepareTranslation(using: translationSession)
                    }
                    .tag(Step.translation)

                VStack(spacing: 20) {
                    Text("initialize.introduce.title")
                        .font(.title)
                        .fontWeight(.semibold)

                    TextField("initialize.introduce.name", text: $userName)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.name)

                    Button("common.continue") {
                        didFinishFirstLaunchFlow = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("common.skip") {
                        didFinishFirstLaunchFlow = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .tag(Step.profile)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
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
            step = .profile
            return
        }

        needsTranslationModelDownload = true
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
