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

    @State private var showsLaunchScreen = true
    @State private var isPreparingApplication = false
    @State private var coreDataContainer: NSPersistentCloudKitContainer?
    @State private var container: AppContainer?

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let coreDataContainer, let container {
                    TranslationModelPreparationView {
                        AppShellView(repository: container.repository, coreDataContainer: coreDataContainer)
                            .environment(\.managedObjectContext, coreDataContainer.viewContext)
                    }
                }

                if showsLaunchScreen {
                    LaunchScreenHost(
                        isApplicationReady: coreDataContainer != nil && container != nil
                    ) {
                        showsLaunchScreen = false
                    }
                    .ignoresSafeArea()
                }
            }
            .task {
                await prepareApplicationIfNeeded()
            }
        }
    }

    @MainActor
    private func prepareApplicationIfNeeded() async {
        guard !isPreparingApplication, coreDataContainer == nil, container == nil else { return }

        isPreparingApplication = true

        do {
            let coreDataContainer = try await FolioraCoreDataStack.makeContainer()
            let container = AppContainer(coreDataContainer: coreDataContainer)
            FolioraAppDelegate.coreDataContainer = coreDataContainer
            self.coreDataContainer = coreDataContainer
            self.container = container
        } catch {
            fatalError("Failed to create Core Data container: \(error)")
        }
    }
}

private struct LaunchScreenHost: UIViewControllerRepresentable {
    let isApplicationReady: Bool
    let onFinished: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> LaunchScreenViewController {
        let viewController = LaunchScreenViewController.instantiate(storyboardName: "LaunchScreen")!
        context.coordinator.viewController = viewController
        context.coordinator.update(
            isApplicationReady: isApplicationReady,
            onFinished: onFinished
        )
        return viewController
    }

    func updateUIViewController(_ uiViewController: LaunchScreenViewController, context: Context) {
        context.coordinator.viewController = uiViewController
        context.coordinator.update(
            isApplicationReady: isApplicationReady,
            onFinished: onFinished
        )
    }

    @MainActor
    final class Coordinator {
        var viewController: LaunchScreenViewController?

        private var didRequestFinish = false
        private var onFinished: (@MainActor () -> Void)?

        func update(isApplicationReady: Bool, onFinished: @escaping @MainActor () -> Void) {
            self.onFinished = onFinished

            guard isApplicationReady, !didRequestFinish else { return }

            didRequestFinish = true
            let completion: @Sendable () -> Void = { [weak self] in
                Task { @MainActor in
                    self?.finish()
                }
            }
            viewController?.stopAnimation(completion: completion)
        }

        private func finish() {
            onFinished?()
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
