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
                        .environment(\.mediaDataLoader, container.mediaDataLoader)
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
                await refreshTranslationPreparationState()
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
        let signpostState = StartupSignposts.signposter.beginInterval("prepareApplication")
        defer { StartupSignposts.signposter.endInterval("prepareApplication", signpostState) }

        do {
            let coreDataContainer = try await FolioraCoreDataStack.makeContainer()
            let container = AppContainer(coreDataContainer: coreDataContainer)
            FolioraAppDelegate.coreDataContainer = coreDataContainer
            self.coreDataContainer = coreDataContainer
            self.container = container
            updateOnboardingState()
        } catch {
            fatalError("Failed to create Core Data container: \(error)")
        }
    }

    /// Decides whether onboarding is needed without waiting on system services.
    ///
    /// The decision rests only on the completion recorded on this device, so the
    /// live state of the translation model or iCloud never replays the flow.
    @MainActor
    private func updateOnboardingState() {
        needsOnboarding = OnboardingProgress.needsOnboarding
        StartupSignposts.signposter.emitEvent(
            "onboardingDecided",
            "needsOnboarding: \(needsOnboarding == true)"
        )
    }

    /// Refreshes the cached translation readiness after launch no longer depends on it.
    @MainActor
    private func refreshTranslationPreparationState() async {
        let signpostState = StartupSignposts.signposter.beginInterval("translationAvailability")
        let state = await translator.preparationState()
        StartupSignposts.signposter.endInterval("translationAvailability", signpostState)

        TranslationPreparationCache.record(state)
    }
}
