import SwiftUI

/// Displays the editor used to create or edit a book.
struct BookEditorView: View {
    let collection: CollectionSummary
    private let existingBook: BookRecord?
    private let onSave: (BookRecord) -> Void

    @Environment(\.dismiss) private var dismiss
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
    @State private var publicationYear: String
    @State private var volumeNumber: String

    private let editorItemID: UUID
    private let acquiredYearOptions = [String(localized: "common.none")]
        + Array(1900...Calendar.current.component(.year, from: .now)).reversed().map(String.init)

    init(
        collection: CollectionSummary,
        initialMediaAssets: [MediaAsset] = [],
        book: BookRecord? = nil,
        onSave: @escaping (BookRecord) -> Void
    ) {
        self.collection = collection
        self.existingBook = book
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
        _publicationYear = State(initialValue: book?.details.publicationYear.map(String.init) ?? "")
        _volumeNumber = State(initialValue: book?.details.volumeNumber.map(String.init) ?? "")
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

                    TextField(String(localized: "common.field.notes"), text: $notes, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)

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
                }

                Section("common.book") {
                    optionalPositiveIntegerField(
                        title: "Publication year",
                        text: $publicationYear
                    )

                    optionalPositiveIntegerField(
                        title: "Pages",
                        text: $pageCount
                    )

                    LabeledContent("Language") {
                        TextField("—", text: $languageCode)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Genre") {
                        TextField("—", text: $genre)
                            .multilineTextAlignment(.trailing)
                    }

                    optionalPositiveIntegerField(
                        title: "Volume",
                        text: $volumeNumber
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

                Section(String(localized: "common.field.tags")) {
                    TagEditorSection(
                        tagInput: $tagInput,
                        tags: $tags
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
        }
    }

    private var canSave: Bool {
        isTitleValid
            && isOptionalPositiveIntegerValid(publicationYear)
            && isOptionalPositiveIntegerValid(pageCount)
            && isOptionalPositiveIntegerValid(volumeNumber)
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
                publicationYear: optionalPositiveInt(publicationYear),
                volumeNumber: optionalPositiveInt(volumeNumber),
                publisher: existingBook?.details.publisher,
                contributors: existingBook?.details.contributors ?? [],
                series: existingBook?.details.series,
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
