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
                    LaunchSequenceView(
                        isApplicationReady: coreDataContainer != nil && container != nil,
                        needsOnboarding: needsOnboarding
                    ) {
                        didFinishLaunchFlow = true
                        withAnimation(.easeOut(duration: 0.25)) {
                            showsLaunchScreen = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .onOpenURL { url in
                CollectionAppLinkRouter.shared.handle(url)
            }
            .task {
                NSUbiquitousKeyValueStore.default.synchronize()
                updateOnboardingState()
                await prepareApplicationIfNeeded()
                await refreshTranslationPreparationState()
            }
            .task(id: container != nil) {
                guard container != nil else { return }
                await skipDeviceSetupIfUndecided()
            }
        }
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
            FolioraCloudKitShareInvitationAcceptor.persistentContainerDidBecomeAvailable()
        } catch {
            fatalError("Failed to create Core Data container: \(error)")
        }
    }

    /// Decides whether onboarding is needed without waiting on system services.
    ///
    /// The decision rests only on the recorded completion, so the live state of the
    /// translation model or iCloud never replays the flow. It is made before the
    /// data stack loads, so a new user's intro starts right away.
    ///
    /// A device that only has its own setup left is the exception: whether there is
    /// anything to set up depends on the translation model. That decision is left
    /// open here, with the splash staying up, until `settleDeviceSetup(with:)`.
    @MainActor
    private func updateOnboardingState() {
        guard needsOnboarding == nil else { return }

        switch OnboardingProgress.pendingFlow {
        case .none:
            decideOnboarding(isNeeded: false)
        case .full:
            decideOnboarding(isNeeded: true)
        case .deviceSetup:
            break
        }
    }

    @MainActor
    private func decideOnboarding(isNeeded: Bool) {
        needsOnboarding = isNeeded
        StartupSignposts.signposter.emitEvent(
            "onboardingDecided",
            "needsOnboarding: \(isNeeded)"
        )
    }

    /// Refreshes the cached translation readiness, and settles the device setup decision if it is open.
    ///
    /// Launch does not depend on this check, except on a device that only has its
    /// own setup left; `skipDeviceSetupIfUndecided()` bounds that wait.
    @MainActor
    private func refreshTranslationPreparationState() async {
        let signpostState = StartupSignposts.signposter.beginInterval("translationAvailability")
        let state = await translator.preparationState()
        StartupSignposts.signposter.endInterval("translationAvailability", signpostState)

        TranslationPreparationCache.record(state)
        settleDeviceSetup(with: state)
    }

    /// Decides the open case of a device that only has its own setup left.
    ///
    /// The setup is shown when the translation model is still to be downloaded.
    /// Otherwise there is nothing to set up, and the device is done.
    @MainActor
    private func settleDeviceSetup(with state: TranslationPreparationState) {
        guard needsOnboarding == nil else { return }

        if state == .needsDownload {
            decideOnboarding(isNeeded: true)
        } else {
            OnboardingProgress.markCompleted()
            decideOnboarding(isNeeded: false)
        }
    }

    /// Lets the launch go on when the device setup decision takes too long.
    ///
    /// The decision waits for the translation availability check, which can stall
    /// indefinitely. Called once the data stack is ready, it gives the check a
    /// moment more, then opens the app. The device stays unmarked, so the next
    /// launch asks again.
    @MainActor
    private func skipDeviceSetupIfUndecided() async {
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled, needsOnboarding == nil else { return }
        decideOnboarding(isNeeded: false)
    }
}
