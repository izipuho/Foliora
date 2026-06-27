import UIKit
import CloudKit
import Combine
import CoreData

enum CloudKitShareInvitationAcceptanceState: Equatable {
    case idle
    case accepting
    case accepted
    case failed(message: String)
}

@MainActor
final class CloudKitShareInvitationAcceptanceController: ObservableObject {
    static let shared = CloudKitShareInvitationAcceptanceController()

    @Published private(set) var state: CloudKitShareInvitationAcceptanceState = .idle

    private init() {}

    func beginAccepting() {
        state = .accepting
    }

    func markAccepted() {
        state = .accepted
    }

    func markFailed(message: String) {
        state = .failed(message: message)
    }

    func reset() {
        state = .idle
    }
}

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
        Task { @MainActor in
            CloudKitShareInvitationAcceptanceController.shared.beginAccepting()

            guard let container = FolioraAppDelegate.coreDataContainer else {
                CloudKitShareInvitationAcceptanceController.shared.markFailed(
                    message: "Не удалось подготовить синхронизацию iCloud. Перезапустите приложение и откройте приглашение еще раз."
                )
                return
            }

            guard let sharedStore = sharedPersistentStore(in: container) else {
                CloudKitShareInvitationAcceptanceController.shared.markFailed(
                    message: "Не удалось найти хранилище общего доступа iCloud. Перезапустите приложение и откройте приглашение еще раз."
                )
                return
            }

            container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
                Task { @MainActor in
                    if let error {
                        CloudKitShareInvitationAcceptanceController.shared.markFailed(
                            message: userFacingMessage(for: error)
                        )
                    } else {
                        container.viewContext.refreshAllObjects()
                        CloudKitShareInvitationAcceptanceController.shared.markAccepted()
                    }
                }
            }
        }
    }

    private static func sharedPersistentStore(in container: NSPersistentCloudKitContainer) -> NSPersistentStore? {
        let sharedStoreURL = container.persistentStoreDescriptions.first {
            $0.cloudKitContainerOptions?.databaseScope == .shared
        }?.url

        return container.persistentStoreCoordinator.persistentStores.first {
            $0.url == sharedStoreURL
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        #if DEBUG
        return "Не удалось открыть доступ. \(error.localizedDescription)\n\(String(reflecting: error))"
        #else
        return "Не удалось открыть доступ. Проверьте iCloud и попробуйте еще раз."
        #endif
    }
}
