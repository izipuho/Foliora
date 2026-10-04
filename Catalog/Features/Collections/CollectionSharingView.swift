import CloudKit
import CoreData
import Foundation
import OSLog
import SwiftUI

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Catalog",
    category: "CollectionSharing"
)

/// Displays the collection sharing view interface.
struct CollectionSharingView: View {
    let collection: CollectionSummary
    let onSharingChanged: () -> Void
    @State private var state: CollectionSharingState
    @State private var sharingAlert: SharingAlert?
    @State private var isPreparingShare = false
    @State private var sharingScreen = CloudSharingScreen()

    private let sharingService: any CollectionSharingService

    init(
        collection: CollectionSummary,
        state: CollectionSharingState,
        sharingService: any CollectionSharingService,
        onSharingChanged: @escaping () -> Void
    ) {
        self.collection = collection
        self.onSharingChanged = onSharingChanged
        self.sharingService = sharingService
        self._state = State(initialValue: state)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    String(localized: "collection.sharing.status.label")
                ) {
                    Text(
                        state.isShared
                            ? "collection.sharing.status.shared"
                            : "collection.sharing.status.private"
                    )
                }

                LabeledContent(
                    String(localized: "collection.sharing.role.label"),
                    value: roleText(state.currentUserRole)
                )
            }

            Section(String(localized: "collection.sharing.participants.section")) {
                if state.peopleParticipants.isEmpty {
                    Text("collection.sharing.participants.empty")
                        .foregroundStyle(.secondary)
                } else {
                    participantsContent(state.peopleParticipants)
                }
            }

            if !state.invitedParticipants.isEmpty {
                Section("collection.sharing.invited.section") {
                    participantsContent(state.invitedParticipants)
                }
            }

            if canManageSharing {
                Section {
                    Button("collection.sharing.share_cta") {
                        Task {
                            await openSharingController()
                        }
                    }
                    .disabled(isPreparingShare)
                }
            }
        }
        .navigationTitle(String(localized: "catalog.dashboard.sharing"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "collection.sharing.not_accessible",
            isPresented: Binding(
                get: { sharingAlert != nil },
                set: { if !$0 { sharingAlert = nil } }
            )
        ) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(sharingAlert?.message ?? "")
        }
    }

    @ViewBuilder
    private func participantsContent(_ participants: [CollectionParticipant]) -> some View {
        ForEach(participants) { participant in
            LabeledContent(
                participantName(participant),
                value: roleText(participant.role)
            )
        }
    }

    private func participantName(_ participant: CollectionParticipant) -> String {
        if participant.isCurrentUser {
            return String(localized: "collection.sharing.participant.you")
        }

        let youText = String(localized: "collection.sharing.participant.you")
        if let displayName = participant.displayName, !displayName.isEmpty, displayName != youText {
            return displayName
        }

        return String(localized: "collection.sharing.participant.unknown_user")
    }

    private func roleText(_ role: CollectionAccessRole) -> String {
        switch role {
        case .owner:
            String(localized: "collection.sharing.role.owner")
        case .contributor:
            String(localized: "collection.sharing.role.coowner")
        case .viewer:
            String(localized: "collection.sharing.role.viewer")
        }
    }

    private var canManageSharing: Bool {
        state.currentUserRole == .owner
    }

    @MainActor
    private func openSharingController() async {
        guard !isPreparingShare else { return }

        isPreparingShare = true
        defer { isPreparingShare = false }

        do {
            let shareResult = try await sharingService.createShare(
                for: collection.id,
                title: collection.name
            )
            let didPresent = sharingScreen.present(
                share: shareResult.share,
                container: shareResult.container,
                title: collection.name,
                onSave: { share in
                    Task {
                        await handleSavedShare(share)
                    }
                },
                onStop: {
                    Task {
                        await handleStoppedSharing()
                    }
                },
                onError: { error in
                    sharingAlert = SharingAlert(message: sharingMessage(for: error))
                }
            )
            if !didPresent {
                sharingAlert = SharingAlert(message: String(localized: "collection.sharing.error.preparation_failed"))
            }
        } catch {
            sharingAlert = SharingAlert(message: sharingMessage(for: error))
        }
    }

    /// Stores what the user changed on the system sharing screen, which Core Data does not do on its own.
    @MainActor
    private func handleSavedShare(_ share: CKShare) async {
        do {
            try await sharingService.persistUpdatedShare(share, for: collection.id)
        } catch {
            // The sharing screen is still up, so there is no place for an alert; the share reaches
            // the store with the next iCloud import.
            logger.error("Failed to persist the updated share: \(String(describing: error))")
        }

        await refreshSharingState()
        onSharingChanged()
    }

    /// Handles the end of sharing started from the system sharing screen.
    ///
    /// The owner keeps the collection, now private. A participant has left the share, so the
    /// collection is removed from this device.
    @MainActor
    private func handleStoppedSharing() async {
        if state.currentUserRole != .owner {
            do {
                try await sharingService.purgeSharedCollection(for: collection.id)
                NotificationCenter.default.post(name: .catalogStoreDidChangeExternally, object: nil)
            } catch {
                sharingAlert = SharingAlert(message: sharingMessage(for: error))
            }
        }

        await refreshSharingState()
        onSharingChanged()
    }

    private func sharingMessage(for error: any Error) -> String {
        if let sharingError = error as? CloudKitCollectionSharingError,
           case .shareURLUnavailable = sharingError {
            return String(localized: "collection.sharing.error.not_uploaded")
        }

        let message = String(localized: "collection.sharing.error.preparation_failed")
        #if DEBUG
        return "\(message)\n\(error.localizedDescription)\n\(String(reflecting: error))"
        #else
        return message
        #endif
    }

    @MainActor
    private func refreshSharingState() async {
        do {
            state = try await sharingService.sharingState(for: collection.id)
        } catch {
            state = CollectionSharingState(
                currentUserRole: .owner,
                participants: []
            )
        }
    }
}

private struct SharingAlert: Identifiable {
    let id = UUID()
    let message: String
}

/// Presents the system sharing screen and reports what the user did there.
///
/// The screen is presented by UIKit, as it is designed to be: wrapped in a SwiftUI sheet it
/// ends up as a sheet inside a sheet.
@MainActor
private final class CloudSharingScreen: NSObject, UICloudSharingControllerDelegate {
    private var shareTitle: String?
    private var onSave: ((CKShare) -> Void)?
    private var onStop: (() -> Void)?
    private var onError: ((any Error) -> Void)?

    /// Presents the sharing screen for the share. Returns `false` when there is nothing to present it from.
    func present(
        share: CKShare,
        container: CKContainer,
        title: String,
        onSave: @escaping (CKShare) -> Void,
        onStop: @escaping () -> Void,
        onError: @escaping (any Error) -> Void
    ) -> Bool {
        guard let presenter = Self.topViewController() else { return false }

        shareTitle = title
        self.onSave = onSave
        self.onStop = onStop
        self.onError = onError

        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = self
        controller.availablePermissions = [
            .allowPrivate,
            .allowReadOnly,
            .allowReadWrite
        ]
        controller.modalPresentationStyle = .formSheet
        presenter.present(controller, animated: true)
        return true
    }

    func cloudSharingController(
        _ csc: UICloudSharingController,
        failedToSaveShareWithError error: any Error
    ) {
        // The alert cannot appear over the sharing screen, so the screen goes first.
        let onError = onError
        csc.dismiss(animated: true) {
            onError?(error)
        }
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
        shareTitle
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        guard let share = csc.share else { return }
        onSave?(share)
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        onStop?()
    }

    /// The view controller on top of the active window, which may itself be a sheet.
    private static func topViewController() -> UIViewController? {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = windowScenes.first { $0.activationState == .foregroundActive } ?? windowScenes.first

        var controller = activeScene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
