import Foundation
import SwiftUI

struct LookupTextField: View {
    let title: String
    @Binding var value: String
    let suggestions: [String]

    @State private var isPresentingLookup = false

    var body: some View {
        HStack {
            Text(title)

            Spacer()

            TextField("—", text: $value)
                .multilineTextAlignment(.trailing)

            Button {
                isPresentingLookup = true
            } label: {
                Image(systemName: "chevron.right")
                    .font(CatalogTypography.chipLabel)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                String.localizedStringWithFormat(String(localized: "common.accessibility.choose_or_add"), title)
            )
        }
        .sheet(isPresented: $isPresentingLookup) {
            LookupSelectionView(
                title: title,
                selection: $value,
                suggestions: suggestions
            )
        }
    }
}

private struct LookupSelectionView: View {
    let title: String
    @Binding var selection: String
    let suggestions: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredSuggestions: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return suggestions }
        return suggestions.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var newValueCandidate: String? {
        let candidate = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        guard !suggestions.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) else {
            return nil
        }
        return candidate
    }

    var body: some View {
        NavigationStack {
            List {
                if let newValueCandidate {
                    Button {
                        selection = newValueCandidate
                        dismiss()
                    } label: {
                        Label(
                            String.localizedStringWithFormat(String(localized: "common.action.add_value"), newValueCandidate),
                            systemImage: "plus.circle.fill"
                        )
                    }
                }

                ForEach(filteredSuggestions, id: \.self) { suggestion in
                    Button {
                        selection = suggestion
                        dismiss()
                    } label: {
                        HStack {
                            Text(suggestion)
                                .foregroundStyle(.primary)

                            Spacer()

                            if suggestion.caseInsensitiveCompare(selection) == .orderedSame {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
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
