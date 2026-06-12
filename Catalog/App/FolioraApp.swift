import SwiftUI
import CloudKit
import CoreData
import UIKit

final class FolioraAppDelegate: NSObject, UIApplicationDelegate {
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
        let container = CKContainer.default()

        container.accept(cloudKitShareMetadata) { metadata, error in
            if let error {
                print("CLOUDKIT_SHARE_ACCEPT_ERROR:", error)
                return
            }

            print("CLOUDKIT_SHARE_ACCEPT_SUCCESS:", metadata as Any)
        }
    }
}

@main
struct FolioraApp: App {
    @UIApplicationDelegateAdaptor(FolioraAppDelegate.self)
    private var appDelegate

    private let coreDataContainer: NSPersistentCloudKitContainer = {
        do {
            let container = try CatalogCoreDataStack.makeContainer()
            return container
        } catch {
            fatalError("Failed to create Core Data container: \(error)")
        }
    }()
    private let container: AppContainer

    init() {
        self.container = AppContainer(coreDataContainer: coreDataContainer)
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(repository: container.repository)
                .environment(\.managedObjectContext, coreDataContainer.viewContext)
                .onOpenURL { url in
                    print("OPEN_URL:", url.absoluteString)
                }
        }
    }
}
