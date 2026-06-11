import SwiftUI
import SwiftData
import CloudKit
import UIKit

final class FolioraAppDelegate: NSObject, UIApplicationDelegate {
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

    private let container = AppContainer()

    var body: some Scene {
        WindowGroup {
            AppShellView(repository: container.repository)
                .modelContainer(container.swiftDataContainer)
                .onOpenURL { url in
                    print("OPEN_URL:", url.absoluteString)
                }
        }
    }
}
