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
