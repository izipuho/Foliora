import CloudKit
import SwiftUI

struct CollectionSharingView: View {
    let collection: CollectionSummary
    @State private var state: CollectionSharingState
    @State private var share: CKShare?
    @State private var isPresentingSharingController = false
    @State private var isPreparingShare = false

    private let container = CKContainer(identifier: CloudKitConfiguration.default.containerIdentifier)
    private let sharingService = CloudKitCollectionSharingService()

    init(collection: CollectionSummary, state: CollectionSharingState) {
        self.collection = collection
        self._state = State(initialValue: state)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    String(localized: "collection.sharing.status.label"),
                    value: sharingStatusText
                )

                LabeledContent(
                    String(localized: "collection.sharing.role.label"),
                    value: roleText(state.currentUserRole)
                )
            }

            Section(String(localized: "collection.sharing.people.section")) {
                if state.participants.isEmpty {
                    Text("collection.sharing.people.empty")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.participants) { participant in
                        LabeledContent(
                            participant.displayName ?? "Unknown person",
                            value: roleText(participant.role)
                        )
                    }
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
                }
            }
        ) {
            if let share {
                CloudSharingController(share: share, container: container)
            }
        }
    }

    private var sharingStatusText: String {
        state.isShared ? "Shared" : String(localized: "collection.sharing.status.private")
    }

    private func roleText(_ role: CollectionAccessRole) -> String {
        switch role {
        case .owner:
            String(localized: "collection.sharing.role.owner")
        case .contributor:
            String(localized: "collection.sharing.role.contributor")
        case .viewer:
            String(localized: "collection.sharing.role.viewer")
        }
    }

    @MainActor
    private func openSharingController() async {
        isPreparingShare = true
        defer { isPreparingShare = false }

        do {
            if let existingShare = try await sharingService.fetchShare(for: collection.id) {
                share = existingShare
            } else {
                share = try await sharingService.createShare(for: collection.id)
            }
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

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UICloudSharingController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(share: share)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let share: CKShare

        init(share: CKShare) {
            self.share = share
        }

        func itemTitle(for cloudSharingController: UICloudSharingController) -> String? {
            share[CKShare.SystemFieldKey.title] as? String
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: any Error
        ) {}
    }
}
