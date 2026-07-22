import SwiftUI
import Translation

struct PhotoAnalysisSettingsView: View {

    @Environment(\.locale) private var locale

    @State private var preparationState: TranslationPreparationState?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var isRefreshingState = false
    @State private var isPreparingTranslation = false
    @State private var preparationErrorMessage: String?

    private let translator = TextTranslator(sourceLanguage: Locale.Language(identifier: "en"))

    var body: some View {
        Form {
            Section {
                settingsRow("Translation Language", targetLanguageName)
                settingsRow("Language Model Status", preparationStateText)
            }

            if preparationState == .needsDownload {
                Section {
                    Button {
                        prepareTranslation()
                    } label: {
                        if isPreparingTranslation {
                            Label("Downloading Model", systemImage: "arrow.down.circle")
                        } else {
                            Label("Download Model", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(isPreparingTranslation)

                    if let preparationErrorMessage {
                        Text(preparationErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Photo Analysis")
        .task {
            await refreshPreparationState()
        }
        .translationTask(translationConfiguration) { session in
            nonisolated(unsafe) let translationSession = session
            await prepareTranslation(using: translationSession)
        }
    }

    private var targetLanguageName: String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    private var preparationStateText: String {
        guard let preparationState else {
            return isRefreshingState ? "Checking..." : "Unknown"
        }

        return preparationState.settingsStatusText
    }

    private func settingsRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    @MainActor
    private func refreshPreparationState() async {
        isRefreshingState = true
        preparationState = await translator.preparationState()
        isRefreshingState = false
    }

    @MainActor
    private func prepareTranslation() {
        preparationErrorMessage = nil
        isPreparingTranslation = true
        translationConfiguration = TranslationSession.Configuration(
            source: translator.sourceLanguage,
            target: translator.targetLanguage()
        )
    }

    nonisolated private func prepareTranslation(using session: TranslationSession) async {
        do {
            try await session.prepareTranslation()
            await MainActor.run {
                translationConfiguration = nil
                isPreparingTranslation = false
            }
            await refreshPreparationState()
        } catch {
            await MainActor.run {
                translationConfiguration = nil
                isPreparingTranslation = false
                preparationErrorMessage = error.localizedDescription
            }
            await refreshPreparationState()
        }
    }
}

private extension TranslationPreparationState {
    var settingsStatusText: String {
        switch self {
        case .ready:
            return String(localized: "Ready")
        case .needsDownload:
            return String(localized: "Needs Download")
        case .unsupported:
            return String(localized: "Unsupported")
        case .notRequired:
            return String(localized: "Not Required")
        }
    }
}
