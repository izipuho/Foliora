import Foundation
import SwiftUI

struct BookPublisherPickerField: View {
    @Binding var selection: Publisher?
    let publishers: [Publisher]
    let collectionID: UUID
    let statusSystemImage: String?
    let onCreate: (Publisher) -> Void

    @State private var isPresentingPicker = false

    var body: some View {
        Button {
            isPresentingPicker = true
        } label: {
            HStack {
                Text("publisher.title")
                    .foregroundStyle(.primary)

                Spacer()

                Text(selection?.name ?? String(localized: "common.none"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)

                if let statusSystemImage {
                    Image(systemName: statusSystemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(CatalogTypography.chipLabel)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresentingPicker) {
            BookPublisherSelectionView(
                selection: $selection,
                publishers: publishers,
                collectionID: collectionID,
                onCreate: onCreate
            )
        }
    }
}

private struct BookPublisherSelectionView: View {
    @Binding var selection: Publisher?
    let publishers: [Publisher]
    let collectionID: UUID
    let onCreate: (Publisher) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredPublishers: [Publisher] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return publishers }
        return publishers.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var newPublisherName: String? {
        let candidate = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        guard !publishers.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) else {
            return nil
        }
        return candidate
    }

    var body: some View {
        NavigationStack {
            List {
                if let newPublisherName {
                    Button {
                        let newPublisher = Publisher(
                            id: UUID(),
                            collectionID: collectionID,
                            name: newPublisherName
                        )
                        onCreate(newPublisher)
                        selection = newPublisher
                        dismiss()
                    } label: {
                        Label(
                            String.localizedStringWithFormat(String(localized: "common.action.add_value"), newPublisherName),
                            systemImage: "plus.circle.fill"
                        )
                    }
                }

                Button {
                    selection = nil
                    dismiss()
                } label: {
                    HStack {
                        Text(String(localized: "common.none"))
                            .foregroundStyle(.primary)

                        Spacer()

                        if selection == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }

                ForEach(filteredPublishers) { publisher in
                    Button {
                        selection = publisher
                        dismiss()
                    } label: {
                        HStack {
                            Text(publisher.name)
                                .foregroundStyle(.primary)

                            Spacer()

                            if selection?.id == publisher.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("publisher.title")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "picker.search_or_add")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "common.cancel"))
                }
            }
        }
    }
}
