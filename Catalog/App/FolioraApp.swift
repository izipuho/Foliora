import SwiftUI
import CloudKit
import CoreData
import UIKit
import os

final class FolioraAppDelegate: NSObject, UIApplicationDelegate {
    static var coreDataContainer: NSPersistentCloudKitContainer?
    private let logger = Logger(subsystem: "com.izipuho.FolioraBells", category: "CloudKitSharing")

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
        logger.info("received share metadata")
        FolioraCloudKitShareInvitationAcceptor.accept(cloudKitShareMetadata, logger: logger)
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
            AppShellView(repository: container.repository, coreDataContainer: coreDataContainer)
                .environment(\.managedObjectContext, coreDataContainer.viewContext)
                .onOpenURL { url in
                    print("OPEN_URL:", url.absoluteString)
                }
        }
    }
}
