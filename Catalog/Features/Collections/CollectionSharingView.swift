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

            Section(String(localized: "collection.sharing.people.section")) {
                if state.peopleParticipants.isEmpty {
                    Text("collection.sharing.people.empty")
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

            Section {
                Button("collection.sharing.share_cta") {
                    Task {
                        await openSharingController()
                    }
                }
                .disabled(isPreparingShare)
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
                }
            }
        ) {
            if let share {
                CloudSharingController(share: share, container: container, onSharingChanged: onSharingChanged)
            }
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

    @MainActor
    private func openSharingController() async {
        isPreparingShare = true
        defer { isPreparingShare = false }

        do {
            share = try await sharingService.createShare(for: collection.id, title: collection.name)
            isPresentingSharingController = true
        } catch {
            share = nil
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

private struct CloudSharingController: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onSharingChanged: () -> Void

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
        Coordinator(share: share, onSharingChanged: onSharingChanged)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let share: CKShare
        private let onSharingChanged: () -> Void

        init(share: CKShare, onSharingChanged: @escaping () -> Void) {
            self.share = share
            self.onSharingChanged = onSharingChanged
        }

        func itemTitle(for cloudSharingController: UICloudSharingController) -> String? {
            share[CKShare.SystemFieldKey.title] as? String
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: any Error
        ) {}

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onSharingChanged()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onSharingChanged()
        }
    }
}
