import SwiftUI

struct CollectionSharingView: View {
    let collection: CollectionSummary

    var body: some View {
        Form {
            Section {
                LabeledContent(
                    String(localized: "collection.sharing.status.label"),
                    value: String(localized: "collection.sharing.status.private")
                )

                LabeledContent(
                    String(localized: "collection.sharing.role.label"),
                    value: String(localized: "collection.sharing.role.owner")
                )
            }

            Section(String(localized: "collection.sharing.people.section")) {
                Text(String(localized: "collection.sharing.people.empty"))
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(String(localized: "collection.sharing.share_cta")) {}
                    .disabled(true)
            }
        }
        .navigationTitle(String(localized: "collection.sharing.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
