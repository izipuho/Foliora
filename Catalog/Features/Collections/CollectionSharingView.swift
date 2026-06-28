import CloudKit
import CoreData
import SwiftUI

struct CollectionSharingView: View {
    let collection: CollectionSummary
    let onSharingChanged: () -> Void
    @State private var state: CollectionSharingState
    @State private var share: CKShare?
    @State private var isPresentingSharingController = false
    @State private var isPreparingShare = false
    @State private var sharingAlert: SharingAlert?
    @State private var pendingSharingMessage: String?

    private let container = CKContainer.default()
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
        .navigationTitle(String(localized: "collection.sharing.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(
            isPresented: $isPresentingSharingController,
            onDismiss: {
                Task {
                    await refreshSharingState()
                    onSharingChanged()
                    showPendingSharingMessage()
                }
            }
        ) {
            if let share {
                CloudSharingController(
                    share: share,
                    container: container,
                    onSharingChanged: onSharingChanged,
                    onError: handleSharingControllerError
                )
            }
        }
        .alert(
            "Управление доступом недоступно",
            isPresented: Binding(
                get: { sharingAlert != nil },
                set: { if !$0 { sharingAlert = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
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
            String(localized: "collection.sharing.role.editor")
        case .viewer:
            String(localized: "collection.sharing.role.viewer")
        }
    }

    private var canManageSharing: Bool {
        state.currentUserRole == .owner
    }

    @MainActor
    private func openSharingController() async {
        isPreparingShare = true
        defer { isPreparingShare = false }

        do {
            let readiness = try await sharingService.localSharingReadiness(for: collection.id)
            guard readiness.isReady else {
                presentSharingMessage(localReadinessMessage(reasons: readiness.reasons))
                return
            }

            share = try await sharingService.createShare(for: collection.id, title: collection.name)
            isPresentingSharingController = true
        } catch {
            share = nil
            presentSharingMessage(sharingMessage(for: error))
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

    private func localReadinessMessage(reasons: [String]) -> String {
        let reasonText = reasons.isEmpty ? "unknown" : reasons.joined(separator: ", ")

        return "Локальная проверка не пройдена: \(reasonText)"
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
        if isPresentingSharingController {
            pendingSharingMessage = message
            isPresentingSharingController = false
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
                isShared: false,
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

private struct CloudSharingController: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onSharingChanged: () -> Void
    let onError: (any Error) -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [
            .allowPrivate,
            .allowReadOnly,
            .allowReadWrite
        ]
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UICloudSharingController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            share: share,
            onSharingChanged: onSharingChanged,
            onError: onError
        )
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let share: CKShare
        private let onSharingChanged: () -> Void
        private let onError: (any Error) -> Void

        init(
            share: CKShare,
            onSharingChanged: @escaping () -> Void,
            onError: @escaping (any Error) -> Void
        ) {
            self.share = share
            self.onSharingChanged = onSharingChanged
            self.onError = onError
        }

        func itemTitle(for cloudSharingController: UICloudSharingController) -> String? {
            share[CKShare.SystemFieldKey.title] as? String
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: any Error
        ) {
            DispatchQueue.main.async {
                self.onError(error)
            }
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onSharingChanged()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onSharingChanged()
        }
    }
}
