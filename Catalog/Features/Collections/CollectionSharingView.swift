import SwiftUI

struct CollectionSharingView: View {
    let collection: CollectionSummary
    let state: CollectionSharingState

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
                    Text(String(localized: "collection.sharing.people.empty"))
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
                Button(String(localized: "collection.sharing.share_cta")) {}
                    .disabled(true)
            }
        }
        .navigationTitle(String(localized: "collection.sharing.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sharingStatusText: String {
        state.isShared ? "Shared" : String(localized: "collection.sharing.status.private")
    }

    private func roleText(_ role: CollectionAccessRole) -> String {
        switch role {
        case .owner:
            String(localized: "collection.sharing.role.owner")
        case .contributor:
            "Contributor"
        case .viewer:
            "Viewer"
        }
    }
}
