import UIKit
import CloudKit
import CoreData

final class CloudKitSharingSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        FolioraCloudKitShareInvitationAcceptor.accept(cloudKitShareMetadata)
    }
}

enum FolioraCloudKitShareInvitationAcceptor {
    static func accept(_ metadata: CKShare.Metadata) {
        guard let container = FolioraAppDelegate.coreDataContainer else {
            return
        }

        guard let sharedStore = sharedPersistentStore(in: container) else {
            return
        }

        container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, _ in }
    }

    private static func sharedPersistentStore(in container: NSPersistentCloudKitContainer) -> NSPersistentStore? {
        let sharedStoreURL = container.persistentStoreDescriptions.first {
            $0.cloudKitContainerOptions?.databaseScope == .shared
        }?.url

        return container.persistentStoreCoordinator.persistentStores.first {
            $0.url == sharedStoreURL
        }
    }
}
