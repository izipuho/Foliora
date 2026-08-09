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
                    FirstLaunchFlowView {
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
                NSUbiquitousKeyValueStore.default.synchronize()
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

private struct FirstLaunchFlowView<Content: View>: View {
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
