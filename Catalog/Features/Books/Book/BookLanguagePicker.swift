import Foundation
import SwiftUI

struct BookLanguagePickerField: View {
    @Binding var languageCode: String
    @State private var isPresentingPicker = false

    private var selectedLabel: String {
        guard !languageCode.isEmpty else { return String(localized: "common.none") }
        return bookLanguageDisplayName(for: languageCode)
    }

    var body: some View {
        Button {
            isPresentingPicker = true
        } label: {
            HStack {
                Text("book.field.language")
                    .foregroundStyle(.primary)

                Spacer()

                Text(selectedLabel)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)

                Image(systemName: "chevron.right")
                    .font(CatalogTypography.chipLabel)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresentingPicker) {
            BookLanguagePickerView(languageCode: $languageCode)
        }
    }
}

private struct BookLanguagePickerView: View {
    @Binding var languageCode: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private struct LanguageOption: Identifiable {
        let code: String
        let name: String

        var id: String { code }
    }

    private var languageOptions: [LanguageOption] {
        Locale.LanguageCode.isoLanguageCodes
            .map(\.identifier)
            .map { code in
                LanguageOption(
                    code: code,
                    name: bookLanguageDisplayName(for: code)
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var filteredOptions: [LanguageOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return languageOptions }

        return languageOptions.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.code.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    languageCode = ""
                    dismiss()
                } label: {
                    HStack {
                        Text(String(localized: "common.none"))
                            .foregroundStyle(.primary)

                        Spacer()

                        if languageCode.isEmpty {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }

                ForEach(filteredOptions) { option in
                    Button {
                        languageCode = option.code
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.name)
                                .foregroundStyle(.primary)

                            Spacer()

                            Text(option.code.uppercased())
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if languageCode.caseInsensitiveCompare(option.code) == .orderedSame {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("book.field.language")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "picker.search_languages")
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

func bookLanguageDisplayName(for code: String) -> String {
    BookLanguageFormatter.displayName(for: code)
}
