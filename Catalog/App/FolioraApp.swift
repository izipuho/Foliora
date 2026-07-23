import SwiftUI
import CloudKit
import CoreData
import Translation
import UIKit

final class FolioraAppDelegate: NSObject, UIApplicationDelegate {
    static var coreDataContainer: NSPersistentCloudKitContainer?

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {

        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )

        configuration.delegateClass = CloudKitSharingSceneDelegate.self

        return configuration
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        FolioraCloudKitShareInvitationAcceptor.accept(cloudKitShareMetadata)
    }
}

@main
struct FolioraApp: App {
    @UIApplicationDelegateAdaptor(FolioraAppDelegate.self)
    private var appDelegate

    private let coreDataContainer: NSPersistentCloudKitContainer = {
        do {
            let container = try FolioraCoreDataStack.makeContainer()
            return container
        } catch {
            fatalError("Failed to create Core Data container: \(error)")
        }
    }()
    private let container: AppContainer

    init() {
        FolioraAppDelegate.coreDataContainer = coreDataContainer
        self.container = AppContainer(coreDataContainer: coreDataContainer)
    }

    var body: some Scene {
        WindowGroup {
            TranslationModelPreparationView {
                AppShellView(repository: container.repository, coreDataContainer: coreDataContainer)
                    .environment(\.managedObjectContext, coreDataContainer.viewContext)
            }
        }
    }
}

private struct TranslationModelPreparationView<Content: View>: View {
    @State private var didCheckPreparationState = false
    @State private var didShowDownloadDialog = false
    @State private var showsDownloadDialog = false
    @State private var translationConfiguration: TranslationSession.Configuration?

    private let translator = TextTranslator(sourceLanguage: Locale.Language(identifier: "en"))
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .task {
                await checkPreparationStateIfNeeded()
            }
            .alert(
                "translation.download_model.description",
                isPresented: $showsDownloadDialog
            ) {
                Button("common.download") {
                    prepareTranslation()
                }
                Button("common.not_now", role: .cancel) {}
            }
            .translationTask(translationConfiguration) { session in
                nonisolated(unsafe) let translationSession = session
                await prepareTranslation(using: translationSession)
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

        guard preparationState == .needsDownload, !didShowDownloadDialog else {
            return
        }

        didShowDownloadDialog = true
        showsDownloadDialog = true
    }

    @MainActor
    private func prepareTranslation() {
        translationConfiguration = TranslationSession.Configuration(
            source: translator.sourceLanguage,
            target: translator.targetLanguage()
        )
    }

    nonisolated private func prepareTranslation(using session: TranslationSession) async {
        try? await session.prepareTranslation()

        await MainActor.run {
            translationConfiguration = nil
        }
        await refreshPreparationState()
    }
}
