import UIKit
import CloudKit

final class CloudKitSharingSceneDelegate: UIResponder, UIWindowSceneDelegate {

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        print("SCENE_ACCEPT_SHARE_METADATA")

        let container = CKContainer.default()

        container.accept(cloudKitShareMetadata) { metadata, error in
            if let error {
                print("SCENE_ACCEPT_SHARE_ERROR:", error)
                return
            }

            print("SCENE_ACCEPT_SHARE_SUCCESS:", metadata as Any)
        }
    }
}
