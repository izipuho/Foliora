import CloudKit
import CoreData
import Foundation
import SwiftUI

/// Displays the collection sharing view interface.
struct CollectionSharingView: View {
    let collection: CollectionSummary
    let onSharingChanged: () -> Void
    @State private var state: CollectionSharingState
    @State private var sharingAlert: SharingAlert?
    @State private var pendingSharingMessage: String?
    @State private var sharingControllerMode: CloudSharingControllerMode?

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
                }
            }
        }
        .navigationTitle(String(localized: "collection.sharing.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(
            item: $sharingControllerMode,
            onDismiss: {
                Task {
                    await refreshSharingState()
                    onSharingChanged()
                    showPendingSharingMessage()
                }
            }
        ) { mode in
            CloudSharingController(
                collectionTitle: collection.name,
                mode: mode,
                onSharingChanged: onSharingChanged,
                onError: handleSharingControllerError
            )
        }
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
        do {
            let shareResult = if let existingShare = try await sharingService.fetchShare(for: collection.id) {
                existingShare
            } else {
                try await sharingService.createShare(
                    for: collection.id,
                    title: collection.name
                )
            }
            sharingControllerMode = .existingShare(
                share: shareResult.share,
                container: shareResult.container
            )
        } catch {
            handleSharingControllerError(error)
        }
    }

    private func isShareURLUnavailableError(_ error: any Error) -> Bool {
        errorMessages(error).contains {
            $0 == "Коллекция еще не загружена в iCloud. Попробуйте немного позже."
                || $0.contains("You cannot get the URL of a share until it's been saved to the server.")
        }
    }

    private func sharingMessage(for error: any Error) -> String {
        if isShareURLUnavailableError(error) {
            return "Коллекция еще не загружена в iCloud. Попробуйте немного позже."
        }

        return "Ошибка подготовки CloudKit Sharing: \(errorMessages(error).joined(separator: " | "))"
    }

    private func errorMessages(_ error: any Error) -> [String] {
        let nsError = error as NSError
        let userInfoMessages = nsError.userInfo.values.compactMap { value -> String? in
            if let string = value as? String {
                return string
            }

            return (value as? NSError)?.localizedDescription
        }

        return [
            String(describing: error),
            nsError.localizedDescription,
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion
        ].compactMap { $0 } + userInfoMessages
    }

    @MainActor
    private func handleSharingControllerError(_ error: any Error) {
        presentSharingMessage(sharingMessage(for: error))
    }

    @MainActor
    private func presentSharingMessage(_ message: String) {
        if sharingControllerMode != nil {
            pendingSharingMessage = message
            sharingControllerMode = nil
        } else {
            sharingAlert = SharingAlert(message: message)
        }
    }

    @MainActor
    private func showPendingSharingMessage() {
        if let pendingSharingMessage {
            self.pendingSharingMessage = nil
            sharingAlert = SharingAlert(message: pendingSharingMessage)
        }
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

private enum CloudSharingControllerMode: Identifiable {
    case existingShare(share: CKShare, container: CKContainer)

    var id: String {
        switch self {
        case .existingShare(let share, _):
            "existingShare-\(share.recordID.recordName)"
        }
    }
}

private struct CloudSharingController: UIViewControllerRepresentable {
    let collectionTitle: String
    let mode: CloudSharingControllerMode
    let onSharingChanged: () -> Void
    let onError: (any Error) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        switch mode {
        case .existingShare(let share, let container):
            let controller = UICloudSharingController(share: share, container: container)
            controller.delegate = context.coordinator
            controller.availablePermissions = [
                .allowPrivate,
                .allowReadOnly,
                .allowReadWrite
            ]
            return controller
        }
    }

    func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            collectionTitle: collectionTitle,
            onSharingChanged: onSharingChanged,
            onError: onError
        )
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let collectionTitle: String
        let onSharingChanged: () -> Void
        let onError: (any Error) -> Void

        init(
            collectionTitle: String,
            onSharingChanged: @escaping () -> Void,
            onError: @escaping (any Error) -> Void
        ) {
            self.collectionTitle = collectionTitle
            self.onSharingChanged = onSharingChanged
            self.onError = onError
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: any Error
        ) {
            onError(error)
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            collectionTitle
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onSharingChanged()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onSharingChanged()
        }
    }

}
