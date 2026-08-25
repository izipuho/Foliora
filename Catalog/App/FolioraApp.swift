import SwiftUI
import CloudKit
import CoreData
import Translation
import UIKit

/// Coordinates foliora app delegate behavior.
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

/// Provides the foliora app application entry point.
@main
struct FolioraApp: App {
    @UIApplicationDelegateAdaptor(FolioraAppDelegate.self)
    private var appDelegate

    @State private var showsLaunchScreen = true
    @State private var needsOnboarding: Bool?
    @State private var didFinishLaunchFlow = false
    @State private var isPreparingApplication = false
    @State private var coreDataContainer: NSPersistentCloudKitContainer?
    @State private var container: AppContainer?

    private let translator = TextTranslator(sourceLanguage: Locale.Language(identifier: "en"))

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let coreDataContainer, let container, didFinishLaunchFlow {
                    AppShellView(repository: container.repository, coreDataContainer: coreDataContainer)
                        .environment(\.managedObjectContext, coreDataContainer.viewContext)
                }

                if showsLaunchScreen {
                    LaunchScreenHost(
                        isApplicationReady: coreDataContainer != nil && container != nil && needsOnboarding != nil,
                        shouldPrepareForOnboarding: shouldPrepareForOnboarding
                    ) {
                        showsLaunchScreen = false
                        didFinishLaunchFlow = true
                    }
                    .ignoresSafeArea()
                }
            }
            .onOpenURL { url in
                CollectionAppLinkRouter.shared.handle(url)
            }
            .task {
                NSUbiquitousKeyValueStore.default.synchronize()
                await prepareApplicationIfNeeded()
            }
        }
    }

    private var shouldPrepareForOnboarding: Bool {
        coreDataContainer != nil && container != nil && needsOnboarding == true && !didFinishLaunchFlow
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
            await updateOnboardingState()
        } catch {
            fatalError("Failed to create Core Data container: \(error)")
        }
    }

    @MainActor
    private func updateOnboardingState() async {
        let store = NSUbiquitousKeyValueStore.default
        let displayName = store.string(forKey: "foliora.profile.displayName")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let profileCompleted = displayName?.isEmpty == false
            || store.bool(forKey: "foliora.profile.didSkipIntroduction")

        let translationState = await translator.preparationState()
        let translationCompleted = translationState != .needsDownload
            || store.bool(forKey: "foliora.onboarding.translationDownloadSkipped")

        needsOnboarding = !(profileCompleted && translationCompleted)
    }
}
