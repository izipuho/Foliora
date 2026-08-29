import CoreData
import Foundation
import SwiftUI

/// Displays the editor used to create or edit a book.
struct BookEditorView: View {
    let collection: CollectionSummary
    private let existingBook: BookRecord?
    private let initialGenreSuggestions: [String]
    private let onSave: (BookRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext
    @FocusState private var isTitleFocused: Bool

    @State private var title: String
    @State private var notes: String
    @State private var selectedAcquiredYearOption: String
    @State private var condition: ItemCondition
    @State private var acquisitionMethod: AcquisitionMethod
    @State private var tagInput = ""
    @State private var tags: [String]
    @State private var mediaAssets: [MediaAsset]

    @State private var languageCode: String
    @State private var genre: String
    @State private var pageCount: String
    @State private var selectedPublicationYearOption: String
    @State private var catalogGenreSuggestions: [String] = []

    private let editorItemID: UUID
    private let acquiredYearOptions = [String(localized: "common.none")]
        + Array(1900...Calendar.current.component(.year, from: .now)).reversed().map(String.init)

    private var publicationYearOptions: [String] {
        let none = String(localized: "common.none")
        let currentYear = Calendar.current.component(.year, from: .now)
        var years = Array(1900...currentYear).map(String.init)

        if let existingYear = existingBook?.details.publicationYear {
            let value = String(existingYear)
            if !years.contains(value) {
                years.append(value)
            }
        }

        years.sort { (Int($0) ?? 0) > (Int($1) ?? 0) }
        return [none] + years
    }

    private var genreSuggestions: [String] {
        Self.normalizedGenreSuggestions(initialGenreSuggestions + catalogGenreSuggestions)
    }

    init(
        collection: CollectionSummary,
        initialMediaAssets: [MediaAsset] = [],
        book: BookRecord? = nil,
        genreSuggestions: [String] = [],
        onSave: @escaping (BookRecord) -> Void
    ) {
        self.collection = collection
        self.existingBook = book
        self.initialGenreSuggestions = genreSuggestions
        self.onSave = onSave
        self.editorItemID = book?.id ?? UUID()

        _title = State(initialValue: book?.title ?? "")
        _notes = State(initialValue: book?.notes ?? "")
        _selectedAcquiredYearOption = State(
            initialValue: book?.acquiredYear.map(String.init) ?? String(localized: "common.none")
        )
        _condition = State(initialValue: book?.condition ?? .good)
        _acquisitionMethod = State(initialValue: book?.acquisitionMethod ?? .bought)
        _tags = State(initialValue: book?.tags ?? [])
        _mediaAssets = State(initialValue: book?.mediaAssets ?? initialMediaAssets)
        _languageCode = State(initialValue: book?.details.languageCode ?? "")
        _genre = State(initialValue: book?.details.genre ?? "")
        _pageCount = State(initialValue: book?.details.pageCount.map(String.init) ?? "")
        _selectedPublicationYearOption = State(
            initialValue: book?.details.publicationYear.map(String.init) ?? String(localized: "common.none")
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "editor.docs_and_media")) {
                    MediaSection(
                        itemID: editorItemID,
                        mediaAssets: $mediaAssets
                    )
                    .safeAreaPadding(.horizontal, CatalogMetrics.Insets.screen)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, CatalogMetrics.Spacing.md)
                    .background(
                        CatalogShapes.section
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .listRowInsets(.init())
                }

                Section(String(localized: "common.field.description")) {
                    TextField(String(localized: "common.field.title"), text: $title)
                        .focused($isTitleFocused)

                    if !isTitleValid {
                        Button {
                            isTitleFocused = true
                        } label: {
                            Label(
                                String(localized: "editor.title.required"),
                                systemImage: "exclamationmark.circle.fill"
                            )
                            .font(.footnote)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(CatalogSemanticColors.destructive)
                    }

                    TextField(String(localized: "common.field.notes"), text: $notes, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)

                    VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
                        Text(String(localized: "common.field.tags"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TagEditorSection(
                            tagInput: $tagInput,
                            tags: $tags
                        )
                    }
                }

                Section("common.book") {
                    YearPickerField(
                        title: "Publication year",
                        selection: $selectedPublicationYearOption,
                        options: publicationYearOptions
                    )

                    optionalPositiveIntegerField(
                        title: "Pages",
                        text: $pageCount
                    )

                    BookLanguagePickerField(languageCode: $languageCode)

                    LookupTextField(
                        title: "Genre",
                        value: $genre,
                        suggestions: genreSuggestions
                    )
                }

                Section(String(localized: "bell.detail.section.collection_info")) {
                    YearPickerField(
                        title: String(localized: "common.field.acquired_year"),
                        selection: $selectedAcquiredYearOption,
                        options: acquiredYearOptions
                    )

                    EnumSelectionRow(
                        title: String(localized: "bell.detail.aquisition"),
                        selectedLabel: acquisitionMethod.displayName,
                        options: AcquisitionMethod.allCases,
                        selection: $acquisitionMethod,
                        optionTitle: \.displayName
                    )

                    EnumSelectionRow(
                        title: String(localized: "common.field.condition"),
                        selectedLabel: condition.displayName,
                        options: ItemCondition.allCases,
                        selection: $condition,
                        optionTitle: \.displayName
                    )
                }
            }
            .navigationTitle(existingBook == nil ? "Add Book" : "Edit Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "common.cancel"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveBook()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave)
                    .accessibilityLabel(String(localized: "common.save"))
                }
            }
            .task(id: collection.id) {
                loadCatalogGenreSuggestions()
            }
        }
    }

    private var canSave: Bool {
        isTitleValid
            && isOptionalPositiveIntegerValid(pageCount)
    }

    private var isTitleValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func optionalPositiveIntegerField(
        title: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
            LabeledContent(title) {
                numericTextField(text)
            }

            if !isOptionalPositiveIntegerValid(text.wrappedValue) {
                Label(
                    "Enter a positive whole number.",
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(CatalogSemanticColors.destructive)
            }
        }
    }

    @ViewBuilder
    private func numericTextField(_ text: Binding<String>) -> some View {
#if os(iOS)
        TextField("—", text: text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
#else
        TextField("—", text: text)
            .multilineTextAlignment(.trailing)
#endif
    }

    private func isOptionalPositiveIntegerValid(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let number = Int(trimmed) else { return false }
        return number > 0
    }

    @MainActor
    private func loadCatalogGenreSuggestions() {
        let snapshot = CatalogSnapshot.load(from: managedObjectContext)
        catalogGenreSuggestions = snapshot.bookRecords
            .filter { $0.collectionID == collection.id }
            .compactMap(\.details.genre)
    }

    private func saveBook() {
        guard canSave else {
            if !isTitleValid {
                isTitleFocused = true
            }
            return
        }

        let itemID = editorItemID
        let normalizedMediaAssets = mediaAssets.enumerated().map { index, asset in
            asset.with(itemID: itemID, sortOrder: index)
        }
        let existingItem = existingBook?.item
        let existingSeries = existingBook?.details.series

        let book = BookRecord(
            item: ItemRecord(
                id: itemID,
                collectionID: existingItem?.collectionID ?? collection.id,
                kind: .books,
                locationID: existingItem?.locationID,
                originPlaceID: existingItem?.originPlaceID,
                createdAt: existingItem?.createdAt ?? .now,
                createdBy: existingItem?.createdBy ?? "me",
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                acquiredYear: Int(selectedAcquiredYearOption),
                condition: condition,
                acquisitionMethod: acquisitionMethod,
                isFavorite: existingItem?.isFavorite ?? false,
                tags: tags,
                originPlace: existingItem?.originPlace,
                storageLocation: existingItem?.storageLocation,
                storagePath: existingItem?.storagePath,
                mediaAssets: normalizedMediaAssets
            ),
            details: BookDetails(
                itemID: itemID,
                languageCode: optionalString(languageCode)?.lowercased(),
                genre: optionalString(genre),
                pageCount: optionalPositiveInt(pageCount),
                publicationYear: Int(selectedPublicationYearOption),
                volumeNumber: existingSeries == nil ? nil : existingBook?.details.volumeNumber,
                publisher: existingBook?.details.publisher,
                contributors: existingBook?.details.contributors ?? [],
                series: existingSeries,
                identifiers: existingBook?.details.identifiers ?? []
            )
        )

        onSave(book)
        dismiss()
    }

    private func optionalString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func optionalPositiveInt(_ value: String) -> Int? {
        guard let number = optionalString(value).flatMap(Int.init), number > 0 else { return nil }
        return number
    }

    private static func normalizedGenreSuggestions(_ values: [String]) -> [String] {
        var seen: Set<String> = []

        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

private struct BookLanguagePickerField: View {
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
                Text("Language")
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
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search languages")
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

private struct LookupTextField: View {
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
            .accessibilityLabel("Choose or add \(title)")
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
                        Label("Add “\(newValueCandidate)”", systemImage: "plus.circle.fill")
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
            .searchable(text: $searchText, prompt: "Search or add")
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

private func bookLanguageDisplayName(for code: String) -> String {
    let name = Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    guard let firstCharacter = name.first else { return name }

    return String(firstCharacter).uppercased(with: Locale.current) + String(name.dropFirst())
}

#if DEBUG
#Preview {
    let container = PreviewContainer.makeBooksMinimal()
    let repository = CoreDataCatalogRepository(
        context: container.viewContext,
        persistentContainer: nil
    )
    let snapshot = CatalogSnapshot.load(from: container.viewContext)

    if let collection = snapshot.collections
        .compactMap({ snapshot.collectionSummary(id: $0.id) })
        .first(where: { $0.kind == .books }) {
        let book = snapshot.bookRecords.first { $0.item.collectionID == collection.id }

        BookEditorView(
            collection: collection,
            book: book
        ) { updatedBook in
            repository.saveBookRecord(updatedBook)
        }
        .environment(\.managedObjectContext, container.viewContext)
    }
}
#endif
