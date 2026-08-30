import CoreData
import SwiftUI

/// Creates one book per selected photo using a shared set of direct item and book fields.
struct BookBatchAddView: View {
    let collection: CollectionSummary
    let initialMediaAssets: [MediaAsset]
    let repository: any CatalogRepository
    private let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext

    @State private var selectedAcquiredYearOption = String(localized: "common.none")
    @State private var condition: ItemCondition = .good
    @State private var acquisitionMethod: AcquisitionMethod = .bought
    @State private var tagInput = ""
    @State private var tags: [String] = []

    @State private var languageCode = ""
    @State private var genre = ""
    @State private var selectedAuthor: Person?
    @State private var selectedPublisher: Publisher?
    @State private var selectedSeries: BookSeries?

    @State private var catalogPeople: [Person] = []
    @State private var catalogPublishers: [Publisher] = []
    @State private var catalogSeries: [BookSeries] = []

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
                Section("common.book") {
                    Picker("Author", selection: $selectedAuthor) {
                        Text(String(localized: "common.none"))
                            .tag(Person?.none)

                        ForEach(catalogPeople) { person in
                            Text(person.name)
                                .tag(Optional(person))
                        }
                    }

                    Picker("Publisher", selection: $selectedPublisher) {
                        Text(String(localized: "common.none"))
                            .tag(Publisher?.none)

                        ForEach(catalogPublishers) { publisher in
                            Text(publisher.name)
                                .tag(Optional(publisher))
                        }
                    }

                    Picker("Series", selection: $selectedSeries) {
                        Text(String(localized: "common.none"))
                            .tag(BookSeries?.none)

                        ForEach(catalogSeries) { series in
                            Text(series.name)
                                .tag(Optional(series))
                        }
                    }

                    TextField("Language", text: $languageCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Genre", text: $genre)
                }

                Section(String(localized: "item.detail.section.collection_info")) {
                    YearPickerField(
                        title: String(localized: "common.field.acquired_year"),
                        selection: $selectedAcquiredYearOption,
                        options: acquiredYearOptions
                    )

                    EnumSelectionRow(
                        title: String(localized: "item.detail.acquisition"),
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
            .task(id: collection.id) {
                loadCatalogMetadata()
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
    private func loadCatalogMetadata() {
        let snapshot = CatalogSnapshot.load(from: managedObjectContext)

        catalogPeople = snapshot.people.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        catalogPublishers = snapshot.publishers.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        catalogSeries = snapshot.bookSeries
            .filter { $0.collectionID == collection.id }
            .sorted {
                let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    @MainActor
    private func createBooks() {
        guard !initialMediaAssets.isEmpty else { return }

        let timestamp = Date()
        let batchPrefix = "Book \(timestamp.formatted(date: .numeric, time: .shortened))"
        let trimmedLanguageCode = optionalString(languageCode)?.lowercased()
        let trimmedGenre = optionalString(genre)
        let contributors = selectedAuthor.map {
            [BookContributor(role: .author, order: 0, person: $0)]
        } ?? []

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
                    notes: "",
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
                    languageCode: trimmedLanguageCode,
                    genre: trimmedGenre,
                    pageCount: nil,
                    publicationYear: nil,
                    volumeNumber: nil,
                    publisher: selectedPublisher,
                    contributors: contributors,
                    series: selectedSeries
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
}

#if DEBUG
#Preview {
    let container = PreviewContainer.makeBooksMinimal()
    let repository = CoreDataCatalogRepository(
        context: container.viewContext,
        persistentContainer: nil
    )
    let snapshot = CatalogSnapshot.load(from: container.viewContext)
    let collection = snapshot.collections.first { $0.kind == .books }!
    let itemCount = snapshot.bookRecords.filter { $0.collectionID == collection.id }.count
    let summary = CollectionSummary(
        id: collection.id,
        homeID: collection.homeID,
        kind: collection.kind,
        name: collection.title,
        subtitle: collection.notes,
        backgroundStyle: collection.backgroundStyle,
        itemCount: itemCount,
        status: .active,
        sharingSummary: "Invitation-only. Members join with Apple ID and receive a role inside the collection."
    )
    let mediaAssets = snapshot.bookRecords
        .flatMap(\.mediaAssets)
        .prefix(3)
        .map { $0.with(itemID: nil) }

    BookBatchAddView(
        collection: summary,
        initialMediaAssets: mediaAssets,
        repository: repository
    )
    .environment(\.managedObjectContext, container.viewContext)
}
#endif
