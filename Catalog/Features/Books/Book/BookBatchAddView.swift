import SwiftUI

/// Creates one book per selected photo using a shared set of direct item and book fields.
struct BookBatchAddView: View {
    let collection: CollectionSummary
    let initialMediaAssets: [MediaAsset]
    let repository: any CatalogRepository
    private let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var notes = ""
    @State private var selectedAcquiredYearOption = String(localized: "common.none")
    @State private var condition: ItemCondition = .good
    @State private var acquisitionMethod: AcquisitionMethod = .bought
    @State private var tagInput = ""
    @State private var tags: [String] = []

    @State private var languageCode = ""
    @State private var pageCount = ""
    @State private var publicationPlaceName = ""
    @State private var publicationYear = ""
    @State private var volumeNumber = ""

    private let acquiredYearOptions = [String(localized: "common.none")]
        + Array(1900...Calendar.current.component(.year, from: .now)).reversed().map(String.init)

    init(
        collection: CollectionSummary,
        initialMediaAssets: [MediaAsset],
        repository: any CatalogRepository,
        onComplete: @escaping () -> Void = {}
    ) {
        self.collection = collection
        self.initialMediaAssets = initialMediaAssets
        self.repository = repository
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "common.field.description")) {
                    TextField(String(localized: "common.field.notes"), text: $notes, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                }

                Section(String(localized: "editor.acquisition_details")) {
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
                }

                Section(String(localized: "editor.attributes")) {
                    EnumSelectionRow(
                        title: String(localized: "common.field.condition"),
                        selectedLabel: condition.displayName,
                        options: ItemCondition.allCases,
                        selection: $condition,
                        optionTitle: \.displayName
                    )
                }

                Section("Book") {
                    TextField("Language", text: $languageCode)
                    TextField("Pages", text: $pageCount)
                    TextField("Publication place", text: $publicationPlaceName)
                    TextField("Publication year", text: $publicationYear)
                    TextField("Volume", text: $volumeNumber)
                }

                Section(String(localized: "common.field.tags")) {
                    TagEditorSection(
                        tagInput: $tagInput,
                        tags: $tags
                    )
                }

                Section {
                    Button(createButtonLabel) {
                        createBooks()
                    }
                    .disabled(initialMediaAssets.isEmpty)
                }
            }
            .navigationTitle(String(localized: "bell_batch_add.title"))
            .navigationBarTitleDisplayMode(.inline)
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

    private var localizedBookCount: String {
        String.localizedStringWithFormat(
            String(localized: "collection.count.books"),
            initialMediaAssets.count
        )
    }

    private var createButtonLabel: String {
        String.localizedStringWithFormat(
            String(localized: "common.create_format"),
            localizedBookCount
        )
    }

    @MainActor
    private func createBooks() {
        guard !initialMediaAssets.isEmpty else { return }

        let timestamp = Date()
        let batchPrefix = "Book \(timestamp.formatted(date: .numeric, time: .shortened))"
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let books = initialMediaAssets.enumerated().map { index, mediaAsset in
            let itemID = UUID()

            return BookRecord(
                item: ItemRecord(
                    id: itemID,
                    collectionID: collection.id,
                    kind: .books,
                    locationID: nil,
                    originPlaceID: nil,
                    createdAt: timestamp,
                    createdBy: "me",
                    title: "\(batchPrefix) · \(index + 1)",
                    notes: trimmedNotes,
                    acquiredYear: Int(selectedAcquiredYearOption),
                    condition: condition,
                    acquisitionMethod: acquisitionMethod,
                    isFavorite: false,
                    tags: tags,
                    originPlace: nil,
                    storageLocation: nil,
                    storagePath: nil,
                    mediaAssets: [mediaAsset.with(itemID: itemID, sortOrder: 0)]
                ),
                details: BookDetails(
                    itemID: itemID,
                    languageCode: optionalString(languageCode)?.lowercased(),
                    pageCount: optionalInt(pageCount),
                    publicationPlaceName: optionalString(publicationPlaceName),
                    publicationYear: optionalInt(publicationYear),
                    volumeNumber: optionalInt(volumeNumber),
                    publicationPlace: nil,
                    contributors: []
                )
            )
        }

        (repository as! any BookCatalogRepository).saveBookRecords(books)
        onComplete()
        dismiss()
    }

    private func optionalString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func optionalInt(_ value: String) -> Int? {
        optionalString(value).flatMap(Int.init)
    }
}
