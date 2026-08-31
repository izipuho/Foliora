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
    @State private var catalogGenreSuggestions: [String] = []

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
                    BookBatchNamedPickerField(
                        title: String(localized: "Author"),
                        selection: $selectedAuthor,
                        values: catalogPeople,
                        name: \.name,
                        subtitle: { _ in nil },
                        create: { name in
                            Person(
                                id: UUID(),
                                name: name,
                                birthYear: nil,
                                deathYear: nil,
                                biography: nil,
                                birthPlace: nil,
                                deathPlace: nil,
                                photos: []
                            )
                        },
                        onCreate: { catalogPeople.append($0) }
                    )

                    BookBatchNamedPickerField(
                        title: String(localized: "Publisher"),
                        selection: $selectedPublisher,
                        values: catalogPublishers,
                        name: \.name,
                        subtitle: { _ in nil },
                        create: { name in
                            Publisher(
                                id: UUID(),
                                name: name,
                                location: nil
                            )
                        },
                        onCreate: { catalogPublishers.append($0) }
                    )

                    BookBatchNamedPickerField(
                        title: String(localized: "Series"),
                        selection: $selectedSeries,
                        values: catalogSeries,
                        name: \.name,
                        subtitle: { series in
                            series.totalBookCount.map { String(localized: "\($0) books") }
                        },
                        create: { name in
                            BookSeries(
                                id: UUID(),
                                collectionID: collection.id,
                                name: name,
                                totalBookCount: nil,
                                publisher: nil
                            )
                        },
                        onCreate: { catalogSeries.append($0) }
                    )

                    BookBatchLanguagePickerField(languageCode: $languageCode)

                    BookBatchLookupTextField(
                        title: String(localized: "Genre"),
                        value: $genre,
                        suggestions: catalogGenreSuggestions
                    )
                }

                Section(String(localized: "item.detail.section.collection_info")) {
                    YearPickerField(
                        title: String(localized: "item.detail.acquisition_year"),
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
        let bookRecords = snapshot.bookRecords
        let bookSeries = snapshot.bookSeries

        catalogPeople = snapshot.people.sorted(by: namedPersonLessThan)

        catalogSeries = bookSeries
            .filter { $0.collectionID == collection.id }
            .sorted(by: namedSeriesLessThan)

        var publishersByID: [UUID: Publisher] = [:]
        for publisher in bookRecords.compactMap(\.details.publisher) + bookSeries.compactMap(\.publisher) {
            publishersByID[publisher.id] = publisher
        }
        catalogPublishers = Array(publishersByID.values).sorted(by: namedPublisherLessThan)

        catalogGenreSuggestions = normalizedGenreSuggestions(
            bookRecords
                .filter { $0.collectionID == collection.id }
                .compactMap(\.details.genre)
        )
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

    private func normalizedGenreSuggestions(_ values: [String]) -> [String] {
        var seen: Set<String> = []

        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter {
                seen.insert(
                    $0.folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: .current
                    )
                ).inserted
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func namedPersonLessThan(_ lhs: Person, _ rhs: Person) -> Bool {
        namedLessThan(lhs.name, lhs.id, rhs.name, rhs.id)
    }

    private func namedPublisherLessThan(_ lhs: Publisher, _ rhs: Publisher) -> Bool {
        namedLessThan(lhs.name, lhs.id, rhs.name, rhs.id)
    }

    private func namedSeriesLessThan(_ lhs: BookSeries, _ rhs: BookSeries) -> Bool {
        namedLessThan(lhs.name, lhs.id, rhs.name, rhs.id)
    }

    private func namedLessThan(
        _ lhsName: String,
        _ lhsID: UUID,
        _ rhsName: String,
        _ rhsID: UUID
    ) -> Bool {
        let comparison = lhsName.localizedCaseInsensitiveCompare(rhsName)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return lhsID.uuidString < rhsID.uuidString
    }
}

private struct BookBatchNamedPickerField<Value: Identifiable & Hashable>: View {
    let title: String
    @Binding var selection: Value?
    let values: [Value]
    let name: KeyPath<Value, String>
    let subtitle: (Value) -> String?
    let create: (String) -> Value
    let onCreate: (Value) -> Void

    @State private var isPresentingPicker = false

    var body: some View {
        Button {
            isPresentingPicker = true
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)

                Spacer()

                Text(selection.map { $0[keyPath: name] } ?? String(localized: "common.none"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)

                Image(systemName: "chevron.right")
                    .font(CatalogTypography.chipLabel)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresentingPicker) {
            BookBatchNamedSelectionView(
                title: title,
                selection: $selection,
                values: values,
                name: name,
                subtitle: subtitle,
                create: create,
                onCreate: onCreate
            )
        }
    }
}

private struct BookBatchNamedSelectionView<Value: Identifiable & Hashable>: View {
    let title: String
    @Binding var selection: Value?
    let values: [Value]
    let name: KeyPath<Value, String>
    let subtitle: (Value) -> String?
    let create: (String) -> Value
    let onCreate: (Value) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredValues: [Value] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return values }
        return values.filter {
            $0[keyPath: name].localizedCaseInsensitiveContains(query)
        }
    }

    private var newValueName: String? {
        let candidate = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        guard !values.contains(where: {
            $0[keyPath: name].caseInsensitiveCompare(candidate) == .orderedSame
        }) else {
            return nil
        }
        return candidate
    }

    var body: some View {
        NavigationStack {
            List {
                if let newValueName {
                    Button {
                        let newValue = create(newValueName)
                        onCreate(newValue)
                        selection = newValue
                        dismiss()
                    } label: {
                        Label("Add “\(newValueName)”", systemImage: "plus.circle.fill")
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

                ForEach(filteredValues) { value in
                    Button {
                        selection = value
                        dismiss()
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                                Text(value[keyPath: name])
                                    .foregroundStyle(.primary)

                                if let subtitle = subtitle(value) {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if selection?.id == value.id {
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

private struct BookBatchLanguagePickerField: View {
    @Binding var languageCode: String
    @State private var isPresentingPicker = false

    private var selectedLabel: String {
        guard !languageCode.isEmpty else { return String(localized: "common.none") }
        return batchBookLanguageDisplayName(for: languageCode)
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
            BookBatchLanguagePickerView(languageCode: $languageCode)
        }
    }
}

private struct BookBatchLanguagePickerView: View {
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
                    name: batchBookLanguageDisplayName(for: code)
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

private struct BookBatchLookupTextField: View {
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
            BookBatchLookupSelectionView(
                title: title,
                selection: $value,
                suggestions: suggestions
            )
        }
    }
}

private struct BookBatchLookupSelectionView: View {
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
        guard !suggestions.contains(where: {
            $0.caseInsensitiveCompare(candidate) == .orderedSame
        }) else {
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

private func batchBookLanguageDisplayName(for code: String) -> String {
    BookLanguageFormatter.displayName(for: code)
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
