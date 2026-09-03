import CoreData
import CoreTransferable
import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum BookOCRScalarDropTarget: Hashable {
    case title
    case publisher
    case series
    case volume
}

/// Carries only the position of one OCR fragment inside the current analysis result.
/// A dedicated transfer type prevents standard text controls from consuming OCR drags as plain strings.
private struct BookOCRFragmentTransfer: Codable, Sendable, Transferable {
    let index: Int

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .folioraBookOCRFragment)
    }
}

private extension UTType {
    static let folioraBookOCRFragment = UTType(exportedAs: "com.izipuho.foliora.book-ocr-fragment")
}

/// Displays the editor used to create or edit a book.
struct BookEditorView: View {
    let collection: CollectionSummary
    private let existingBook: BookRecord?
    private let initialGenreSuggestions: [String]
    private let initialAnalysisImage: UIImage?
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
    @State private var selectedSeries: BookSeries?
    @State private var volumeNumber: String
    @State private var selectedPublisher: Publisher?
    @State private var contributors: [BookContributor]
    @State private var identifiers: [BookIdentifier]
    @State private var catalogGenreSuggestions: [String] = []
    @State private var catalogSeries: [BookSeries] = []
    @State private var catalogPublishers: [Publisher] = []
    @State private var catalogPeople: [Person] = []
    @State private var editingContributorIndex: Int?
    @State private var isPresentingContributorEditor = false
    @State private var editingIdentifierIndex: Int?
    @State private var isPresentingIdentifierEditor = false
    @State private var photoAnalysis = BookPhotoAnalysisController()
    @State private var didStartInitialAnalysis = false
    @State private var ocrScalarAssignments: [BookOCRScalarDropTarget: [RecognizedTextFeature]] = [:]
    @State private var ocrAuthorAssignments: [Int: [RecognizedTextFeature]] = [:]
    @State private var ocrAuthorBaseNames: [Int: String] = [:]

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

        if Int(selectedPublicationYearOption) != nil,
           !years.contains(selectedPublicationYearOption) {
            years.append(selectedPublicationYearOption)
        }

        years.sort { (Int($0) ?? 0) > (Int($1) ?? 0) }
        return [none] + years
    }

    private var genreSuggestions: [String] {
        Self.normalizedGenreSuggestions(initialGenreSuggestions + catalogGenreSuggestions)
    }

    private var availableSeries: [BookSeries] {
        var uniqueByID = Dictionary(catalogSeries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let selectedSeries {
            uniqueByID[selectedSeries.id] = selectedSeries
        }

        return uniqueByID.values.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var availablePublishers: [Publisher] {
        var uniqueByID = Dictionary(catalogPublishers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let selectedPublisher {
            uniqueByID[selectedPublisher.id] = selectedPublisher
        }

        return uniqueByID.values.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var availablePeople: [Person] {
        var uniqueByID = Dictionary(catalogPeople.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for contributor in contributors {
            uniqueByID[contributor.person.id] = contributor.person
        }

        return uniqueByID.values.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var shouldShowPhotoAnalysisSection: Bool {
        photoAnalysis.isAnalyzing || photoAnalysis.suggestions.hasSuggestions
    }

    private var firstPhotoAssetID: UUID? {
        mediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first?
            .id
    }

    init(
        collection: CollectionSummary,
        initialMediaAssets: [MediaAsset] = [],
        initialAnalysisImage: UIImage? = nil,
        book: BookRecord? = nil,
        genreSuggestions: [String] = [],
        onSave: @escaping (BookRecord) -> Void
    ) {
        self.collection = collection
        self.existingBook = book
        self.initialGenreSuggestions = genreSuggestions
        self.initialAnalysisImage = initialAnalysisImage ?? initialMediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { asset -> UIImage? in
                guard let data = asset.originalData else { return nil }
                return UIImage(data: data)
            }
            .first
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
        _selectedSeries = State(initialValue: book?.details.series)
        _volumeNumber = State(initialValue: book?.details.volumeNumber.map(String.init) ?? "")
        _selectedPublisher = State(initialValue: book?.details.publisher)
        _contributors = State(
            initialValue: (book?.details.contributors ?? []).sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.person.name.localizedCaseInsensitiveCompare($1.person.name) == .orderedAscending
            }
        )
        _identifiers = State(initialValue: book?.details.identifiers ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "editor.docs_and_media")) {
                    MediaSection(
                        itemID: editorItemID,
                        mediaAssets: $mediaAssets,
                        analysisHighlightedAssetID: photoAnalysis.isAnalyzing ? firstPhotoAssetID : nil
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

                if shouldShowPhotoAnalysisSection {
                    Section(String(localized: "editor.photo_analysis.section")) {
                        if photoAnalysis.isAnalyzing {
                            HStack(spacing: CatalogMetrics.Spacing.sm) {
                                ProgressView()
                                Text(String(localized: "editor.photo_analysis.analyzing"))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            if let suggestion = photoAnalysis.suggestions.title {
                                PhotoSuggestionRow(
                                    title: String(localized: "common.field_title"),
                                    suggestedValue: suggestion.value,
                                    confidence: suggestion.confidence,
                                    onAccept: {
                                        title = suggestion.value
                                        photoAnalysis.dismiss(.title)
                                    }
                                )
                            }

                            if !photoAnalysis.suggestions.authors.isEmpty {
                                let suggestions = photoAnalysis.suggestions.authors
                                PhotoSuggestionRow(
                                    title: String(localized: "book_contributor.role.author"),
                                    suggestedValue: suggestions.map(\.value).joined(separator: ", "),
                                    confidence: suggestions.map(\.confidence).min() ?? 0,
                                    onAccept: {
                                        applyAuthorSuggestions(suggestions)
                                        photoAnalysis.dismiss(.authors)
                                    }
                                )
                            }

                            if !photoAnalysis.suggestions.identifiers.isEmpty {
                                let suggestions = photoAnalysis.suggestions.identifiers
                                PhotoSuggestionRow(
                                    title: String(localized: "book.section.identifiers"),
                                    suggestedValue: suggestions
                                        .map { "\($0.value.type.bookEditorDisplayName): \($0.value.value)" }
                                        .joined(separator: "\n"),
                                    confidence: suggestions.map(\.confidence).min() ?? 0,
                                    onAccept: {
                                        applyIdentifierSuggestions(suggestions)
                                        photoAnalysis.dismiss(.identifiers)
                                    }
                                )
                            }

                            if let suggestion = photoAnalysis.suggestions.publisher {
                                PhotoSuggestionRow(
                                    title: String(localized: "publisher.title"),
                                    suggestedValue: suggestion.value,
                                    confidence: suggestion.confidence,
                                    onAccept: {
                                        applyPublisherSuggestion(suggestion)
                                        photoAnalysis.dismiss(.publisher)
                                    }
                                )
                            }

                            if let suggestion = photoAnalysis.suggestions.publicationYear {
                                PhotoSuggestionRow(
                                    title: String(localized: "book.field.publication_year"),
                                    suggestedValue: String(suggestion.value),
                                    confidence: suggestion.confidence,
                                    onAccept: {
                                        selectedPublicationYearOption = String(suggestion.value)
                                        photoAnalysis.dismiss(.publicationYear)
                                    }
                                )
                            }

                            if let suggestion = photoAnalysis.suggestions.languageCode {
                                PhotoSuggestionRow(
                                    title: String(localized: "book.field.language"),
                                    suggestedValue: "\(bookLanguageDisplayName(for: suggestion.value)) (\(suggestion.value.uppercased()))",
                                    confidence: suggestion.confidence,
                                    onAccept: {
                                        languageCode = suggestion.value
                                        photoAnalysis.dismiss(.languageCode)
                                    }
                                )
                            }

                            if let suggestion = photoAnalysis.suggestions.series {
                                PhotoSuggestionRow(
                                    title: String(localized: "series.title"),
                                    suggestedValue: suggestion.value,
                                    confidence: suggestion.confidence,
                                    onAccept: {
                                        applySeriesSuggestion(suggestion)
                                        photoAnalysis.dismiss(.series)
                                    }
                                )
                            }

                            if let suggestion = photoAnalysis.suggestions.volumeNumber {
                                PhotoSuggestionRow(
                                    title: String(localized: "book.field.volume"),
                                    suggestedValue: String(suggestion.value),
                                    confidence: suggestion.confidence,
                                    onAccept: {
                                        volumeNumber = String(suggestion.value)
                                        photoAnalysis.dismiss(.volumeNumber)
                                    }
                                )
                            }
                        }
                    }
                }

                Section(String(localized: "common.field.description")) {
                    TextField(String(localized: "common.field_title"), text: $title)
                        .focused($isTitleFocused)
                        .dropDestination(for: BookOCRFragmentTransfer.self) { items, _ in
                            applyOCRScalarFragments(items, to: .title)
                        }

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
                        title: String(localized: "book.field.publication_year"),
                        selection: $selectedPublicationYearOption,
                        options: publicationYearOptions
                    )

                    optionalPositiveIntegerField(
                        title: String(localized: "book.field.pages"),
                        text: $pageCount
                    )

                    BookLanguagePickerField(languageCode: $languageCode)

                    LookupTextField(
                        title: String(localized: "book.field.genre"),
                        value: $genre,
                        suggestions: genreSuggestions
                    )
                }

                Section("series.title") {
                    BookSeriesPickerField(
                        selection: $selectedSeries,
                        series: availableSeries,
                        collectionID: collection.id,
                        onCreate: { newSeries in
                            catalogSeries.append(newSeries)
                            selectedSeries = newSeries
                        }
                    )
                    .dropDestination(for: BookOCRFragmentTransfer.self) { items, _ in
                        applyOCRScalarFragments(items, to: .series)
                    }

                    if selectedSeries != nil {
                        volumeField
                    }
                }

                Section("publisher.title") {
                    BookPublisherPickerField(
                        selection: $selectedPublisher,
                        publishers: availablePublishers,
                        onCreate: { newPublisher in
                            catalogPublishers.append(newPublisher)
                            selectedPublisher = newPublisher
                        }
                    )
                    .dropDestination(for: BookOCRFragmentTransfer.self) { items, _ in
                        applyOCRScalarFragments(items, to: .publisher)
                    }
                }

                Section("book.section.contributors") {
                    ForEach(contributors.indices, id: \.self) { index in
                        let contributor = contributors[index]

                        Button {
                            editingContributorIndex = index
                            isPresentingContributorEditor = true
                        } label: {
                            HStack {
                                Text(contributor.role.displayName)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text(contributor.person.name)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.trailing)

                                Image(systemName: "chevron.right")
                                    .font(CatalogTypography.chipLabel)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .dropDestination(for: BookOCRFragmentTransfer.self) { items, _ in
                            appendOCRFragments(items, toContributorAt: index)
                        }
                    }
                    .onDelete(perform: deleteContributors)

                    Button {
                        editingContributorIndex = nil
                        isPresentingContributorEditor = true
                    } label: {
                        Label("book_contributor.action.add", systemImage: "plus")
                    }
                    .dropDestination(for: BookOCRFragmentTransfer.self) { items, _ in
                        createOCRAuthor(from: items)
                    }
                }

                Section("book.section.identifiers") {
                    ForEach(identifiers.indices, id: \.self) { index in
                        let identifier = identifiers[index]

                        Button {
                            editingIdentifierIndex = index
                            isPresentingIdentifierEditor = true
                        } label: {
                            HStack {
                                Text(identifier.type.bookEditorDisplayName)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text(identifier.value)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.trailing)

                                Image(systemName: "chevron.right")
                                    .font(CatalogTypography.chipLabel)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteIdentifiers)

                    Button {
                        editingIdentifierIndex = nil
                        isPresentingIdentifierEditor = true
                    } label: {
                        Label("book_identifier.action.add", systemImage: "plus")
                    }
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
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if hasUnusedOCRFragments {
                    BookOCRBottomPalette(
                        fragments: photoAnalysis.recognizedText,
                        usedFragments: usedOCRFragments
                    )
                }
            }
            .navigationTitle(existingBook == nil ? String(localized: "book.action.add") : String(localized: "book.action.edit"))
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
                loadCatalogMetadata()
                startInitialPhotoAnalysisIfNeeded()
            }
            .sheet(isPresented: $isPresentingContributorEditor) {
                BookContributorEditorView(
                    contributor: editingContributorIndex.flatMap { index in
                        contributors.indices.contains(index) ? contributors[index] : nil
                    },
                    people: availablePeople,
                    existingContributors: contributors,
                    editingIndex: editingContributorIndex,
                    onCreatePerson: { newPerson in
                        catalogPeople.append(newPerson)
                    },
                    onSave: saveContributor
                )
            }
            .sheet(isPresented: $isPresentingIdentifierEditor) {
                BookIdentifierEditorView(
                    identifier: editingIdentifierIndex.flatMap { index in
                        identifiers.indices.contains(index) ? identifiers[index] : nil
                    },
                    existingIdentifiers: identifiers,
                    editingIndex: editingIdentifierIndex,
                    onSave: saveIdentifier
                )
            }
        }
    }

    private var usedOCRFragments: Set<RecognizedTextFeature> {
        let scalarFragments = ocrScalarAssignments.values.flatMap { $0 }
        let authorFragments = ocrAuthorAssignments.values.flatMap { $0 }
        return Set(scalarFragments + authorFragments)
    }

    private var hasUnusedOCRFragments: Bool {
        photoAnalysis.recognizedText.contains { !usedOCRFragments.contains($0) }
    }

    private var canSave: Bool {
        isTitleValid
            && isOptionalPositiveIntegerValid(pageCount)
            && isVolumeValid
    }

    private var isTitleValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var volumeField: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
            LabeledContent("book.field.volume") {
                numericTextField($volumeNumber)
            }

            if !isVolumeValid {
                Label(
                    volumeValidationMessage,
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(CatalogSemanticColors.destructive)
            }
        }
        .dropDestination(for: BookOCRFragmentTransfer.self) { items, _ in
            applyOCRScalarFragments(items, to: .volume)
        }
    }

    private var isVolumeValid: Bool {
        guard let selectedSeries else { return true }

        let trimmed = volumeNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let number = Int(trimmed), number > 0 else { return false }

        if let totalBookCount = selectedSeries.totalBookCount {
            return number <= totalBookCount
        }

        return true
    }

    private var volumeValidationMessage: String {
        if let totalBookCount = selectedSeries?.totalBookCount {
            return String.localizedStringWithFormat(
                String(localized: "common.validation.whole_number_range_1_to_max"),
                totalBookCount
            )
        }

        return String(localized: "book.validation.positive_whole_number")
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
                    "book.validation.positive_whole_number",
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

    private func startInitialPhotoAnalysisIfNeeded() {
        guard !didStartInitialAnalysis,
              existingBook == nil,
              let initialAnalysisImage else { return }

        didStartInitialAnalysis = true
        photoAnalysis.analyze(image: initialAnalysisImage)
    }

    // iOS 26 drop destinations don't consume these helpers' success flags, but direct callers may still use them.
    @discardableResult
    private func applyOCRScalarFragments(
        _ droppedFragments: [BookOCRFragmentTransfer],
        to target: BookOCRScalarDropTarget
    ) -> Bool {
        let newFragments = ocrFeatures(matching: droppedFragments)
        guard !newFragments.isEmpty else { return false }

        var assigned = ocrScalarAssignments[target, default: []]
        for fragment in newFragments where !assigned.contains(fragment) {
            assigned.append(fragment)
        }
        assigned.sort(by: Self.ocrReadingOrder)

        let value = assigned.map(\.text).joined(separator: " ")
        let confidence = assigned.map(\.confidence).min() ?? 0

        if target == .volume {
            guard let number = firstPositiveInteger(in: value) else { return false }
            volumeNumber = String(number)
        }

        ocrScalarAssignments[target] = assigned

        switch target {
        case .title:
            title = value
        case .publisher:
            applyPublisherSuggestion(
                SuggestedFieldValue(value: value, confidence: confidence)
            )
        case .series:
            applySeriesSuggestion(
                SuggestedFieldValue(value: value, confidence: confidence)
            )
        case .volume:
            break
        }

        return true
    }

    @discardableResult
    private func createOCRAuthor(from droppedFragments: [BookOCRFragmentTransfer]) -> Bool {
        var fragments = ocrFeatures(matching: droppedFragments)
        guard !fragments.isEmpty else { return false }
        fragments.sort(by: Self.ocrReadingOrder)

        let name = fragments.map(\.text).joined(separator: " ")
        guard !name.isEmpty else { return false }

        // A drop on the empty "add contributor" row creates the first concrete author target.
        let person = personForOCRName(name)
        let index = contributors.count
        contributors.append(
            BookContributor(
                role: .author,
                order: index,
                person: person
            )
        )
        normalizeContributorOrder()
        ocrAuthorAssignments[index] = fragments
        ocrAuthorBaseNames[index] = ""
        return true
    }

    @discardableResult
    private func appendOCRFragments(
        _ droppedFragments: [BookOCRFragmentTransfer],
        toContributorAt index: Int
    ) -> Bool {
        guard contributors.indices.contains(index), contributors[index].role == .author else {
            return false
        }

        let newFragments = ocrFeatures(matching: droppedFragments)
        guard !newFragments.isEmpty else { return false }

        let contributor = contributors[index]
        if ocrAuthorBaseNames[index] == nil {
            // A manually-created author remains the stable prefix; OCR fragments are appended rather than renaming it implicitly.
            ocrAuthorBaseNames[index] = contributor.person.name
        }

        var assigned = ocrAuthorAssignments[index, default: []]
        for fragment in newFragments where !assigned.contains(fragment) {
            assigned.append(fragment)
        }
        assigned.sort(by: Self.ocrReadingOrder)
        ocrAuthorAssignments[index] = assigned

        let fragmentName = assigned.map(\.text).joined(separator: " ")
        let baseName = ocrAuthorBaseNames[index] ?? ""
        let name = [baseName, fragmentName]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")

        guard !name.isEmpty else { return false }

        contributors[index] = BookContributor(
            role: contributor.role,
            order: contributor.order,
            person: personForOCRName(name)
        )
        return true
    }

    private func personForOCRName(_ rawName: String) -> Person {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalizedReferenceKey(name)

        if let existing = catalogPeople.first(where: { normalizedReferenceKey($0.name) == key }) {
            return existing
        }

        let person = Person(
            id: UUID(),
            name: name,
            birthYear: nil,
            deathYear: nil,
            biography: nil,
            birthPlace: nil,
            deathPlace: nil,
            photos: []
        )
        catalogPeople.append(person)
        return person
    }

    private func ocrFeatures(
        matching transfers: [BookOCRFragmentTransfer]
    ) -> [RecognizedTextFeature] {
        transfers.compactMap { transfer in
            guard photoAnalysis.recognizedText.indices.contains(transfer.index) else {
                return nil
            }
            return photoAnalysis.recognizedText[transfer.index]
        }
    }

    private static func ocrReadingOrder(
        _ lhs: RecognizedTextFeature,
        _ rhs: RecognizedTextFeature
    ) -> Bool {
        let lhsRow = Int((lhs.boundingBox.midY * 50).rounded())
        let rhsRow = Int((rhs.boundingBox.midY * 50).rounded())
        if lhsRow != rhsRow {
            return lhsRow > rhsRow
        }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }

    private func firstPositiveInteger(in value: String) -> Int? {
        value
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int(String($0)) }
            .first(where: { $0 > 0 })
    }

    private func applyAuthorSuggestions(_ suggestions: [SuggestedFieldValue<String>]) {
        let originalAuthorIndex = contributors.firstIndex { $0.role == .author } ?? contributors.count
        var seen: Set<String> = []
        var authorPeople: [Person] = []

        for suggestion in suggestions {
            let name = suggestion.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedReferenceKey(name)
            guard !name.isEmpty, seen.insert(key).inserted else { continue }

            if let existing = catalogPeople.first(where: { normalizedReferenceKey($0.name) == key }) {
                authorPeople.append(existing)
            } else {
                let person = Person(
                    id: UUID(),
                    name: name,
                    birthYear: nil,
                    deathYear: nil,
                    biography: nil,
                    birthPlace: nil,
                    deathPlace: nil,
                    photos: []
                )
                catalogPeople.append(person)
                authorPeople.append(person)
            }
        }

        var updated = contributors.filter { $0.role != .author }
        let insertionIndex = min(originalAuthorIndex, updated.count)
        let newAuthors = authorPeople.enumerated().map { index, person in
            BookContributor(
                role: .author,
                order: insertionIndex + index,
                person: person
            )
        }
        updated.insert(contentsOf: newAuthors, at: insertionIndex)
        contributors = updated.enumerated().map { index, contributor in
            var normalized = contributor
            normalized.order = index
            return normalized
        }
    }

    private func applyIdentifierSuggestions(_ suggestions: [SuggestedFieldValue<BookIdentifier>]) {
        for suggestion in suggestions {
            let candidate = suggestion.value
            let candidateKey = bookIdentifierDuplicateKey(type: candidate.type, value: candidate.value)
            let isDuplicate = identifiers.contains { existing in
                existing.type == candidate.type
                    && bookIdentifierDuplicateKey(type: existing.type, value: existing.value) == candidateKey
            }

            if !isDuplicate {
                identifiers.append(candidate)
            }
        }
    }

    private func applyPublisherSuggestion(_ suggestion: SuggestedFieldValue<String>) {
        let name = suggestion.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let key = normalizedReferenceKey(name)
        if let existing = catalogPublishers.first(where: { normalizedReferenceKey($0.name) == key }) {
            selectedPublisher = existing
            return
        }

        let publisher = Publisher(
            id: UUID(),
            name: name,
            location: nil
        )
        catalogPublishers.append(publisher)
        selectedPublisher = publisher
    }

    private func applySeriesSuggestion(_ suggestion: SuggestedFieldValue<String>) {
        let name = suggestion.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let key = normalizedReferenceKey(name)
        if let existing = catalogSeries.first(where: { normalizedReferenceKey($0.name) == key }) {
            selectedSeries = existing
            return
        }

        let series = BookSeries(
            id: UUID(),
            collectionID: collection.id,
            name: name,
            totalBookCount: nil,
            publisher: nil
        )
        catalogSeries.append(series)
        selectedSeries = series
    }

    private func normalizedReferenceKey(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private func saveContributor(_ contributor: BookContributor) {
        if let editingContributorIndex,
           contributors.indices.contains(editingContributorIndex) {
            contributors[editingContributorIndex] = contributor
        } else {
            contributors.append(contributor)
        }
        normalizeContributorOrder()
    }

    private func deleteContributors(at offsets: IndexSet) {
        contributors.remove(atOffsets: offsets)
        normalizeContributorOrder()
    }

    private func normalizeContributorOrder() {
        contributors = contributors.enumerated().map { index, contributor in
            var normalized = contributor
            normalized.order = index
            return normalized
        }
    }

    private func saveIdentifier(_ identifier: BookIdentifier) {
        if let editingIdentifierIndex,
           identifiers.indices.contains(editingIdentifierIndex) {
            identifiers[editingIdentifierIndex] = identifier
        } else {
            identifiers.append(identifier)
        }
    }

    private func deleteIdentifiers(at offsets: IndexSet) {
        identifiers.remove(atOffsets: offsets)
    }

    @MainActor
    private func loadCatalogMetadata() {
        let snapshot = CatalogSnapshot.load(from: managedObjectContext)
        let bookRecords = snapshot.bookRecords
        let bookSeries = snapshot.bookSeries

        catalogGenreSuggestions = bookRecords
            .filter { $0.collectionID == collection.id }
            .compactMap(\.details.genre)
        catalogSeries = bookSeries
            .filter { $0.collectionID == collection.id }

        var publishersByID: [UUID: Publisher] = [:]
        for publisher in bookRecords.compactMap(\.details.publisher) + bookSeries.compactMap(\.publisher) {
            publishersByID[publisher.id] = publisher
        }
        catalogPublishers = Array(publishersByID.values)
        catalogPeople = snapshot.people
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
        let normalizedContributors = contributors.enumerated().map { index, contributor in
            var normalized = contributor
            normalized.order = index
            return normalized
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
                publicationYear: Int(selectedPublicationYearOption),
                volumeNumber: selectedSeries == nil ? nil : optionalPositiveInt(volumeNumber),
                publisher: selectedPublisher,
                contributors: normalizedContributors,
                series: selectedSeries,
                identifiers: identifiers
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

private struct BookOCRBottomPalette: View {
    let fragments: [RecognizedTextFeature]
    let usedFragments: Set<RecognizedTextFeature>

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CatalogMetrics.Spacing.sm) {
                    ForEach(Array(fragments.enumerated()), id: \.offset) { index, feature in
                        if !usedFragments.contains(feature) {
                            BookOCRFragmentChip(
                                feature: feature,
                                transfer: BookOCRFragmentTransfer(index: index)
                            )
                        }
                    }
                }
                .padding(.horizontal, CatalogMetrics.Insets.screen)
                .padding(.vertical, CatalogMetrics.Spacing.sm)
            }
        }
        .background(.ultraThinMaterial)
    }
}

private struct BookOCRFragmentChip: View {
    let feature: RecognizedTextFeature
    let transfer: BookOCRFragmentTransfer

    var body: some View {
        HStack(spacing: CatalogMetrics.Spacing.xs) {
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(feature.text)
                .lineLimit(1)
        }
        .font(.subheadline)
        .padding(.horizontal, CatalogMetrics.Spacing.md)
        .frame(minHeight: 44)
        .frame(maxWidth: 240)
        .background(
            Capsule()
                .fill(Color(uiColor: .tertiarySystemFill))
        )
        // Give the whole 44pt chip a drag hit target instead of making the user catch the small glyph or text.
        .contentShape(Rectangle())
        .draggable(transfer)
        .accessibilityLabel(feature.text)
    }
}

private struct BookSeriesPickerField: View {
    @Binding var selection: BookSeries?
    let series: [BookSeries]
    let collectionID: UUID
    let onCreate: (BookSeries) -> Void

    @State private var isPresentingPicker = false

    var body: some View {
        Button {
            isPresentingPicker = true
        } label: {
            HStack {
                Text("series.title")
                    .foregroundStyle(.primary)

                Spacer()

                Text(selection?.name ?? String(localized: "common.none"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)

                Image(systemName: "chevron.right")
                    .font(CatalogTypography.chipLabel)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresentingPicker) {
            BookSeriesSelectionView(
                selection: $selection,
                series: series,
                collectionID: collectionID,
                onCreate: onCreate
            )
        }
    }
}

private struct BookSeriesSelectionView: View {
    @Binding var selection: BookSeries?
    let series: [BookSeries]
    let collectionID: UUID
    let onCreate: (BookSeries) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredSeries: [BookSeries] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return series }
        return series.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var newSeriesName: String? {
        let candidate = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        guard !series.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) else {
            return nil
        }
        return candidate
    }

    var body: some View {
        NavigationStack {
            List {
                if let newSeriesName {
                    Button {
                        let newSeries = BookSeries(
                            id: UUID(),
                            collectionID: collectionID,
                            name: newSeriesName,
                            totalBookCount: nil,
                            publisher: nil
                        )
                        onCreate(newSeries)
                        selection = newSeries
                        dismiss()
                    } label: {
                        Label(
                            String.localizedStringWithFormat(String(localized: "common.action.add_value"), newSeriesName),
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

                ForEach(filteredSeries) { item in
                    Button {
                        selection = item
                        dismiss()
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                                Text(item.name)
                                    .foregroundStyle(.primary)

                                if let totalBookCount = item.totalBookCount {
                                    Text(CollectionKind.bookCountLabel(for: totalBookCount))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if selection?.id == item.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("series.title")
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

private struct BookPublisherPickerField: View {
    @Binding var selection: Publisher?
    let publishers: [Publisher]
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
                onCreate: onCreate
            )
        }
    }
}

private struct BookPublisherSelectionView: View {
    @Binding var selection: Publisher?
    let publishers: [Publisher]
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
                            name: newPublisherName,
                            location: nil
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

private struct BookContributorEditorView: View {
    let contributor: BookContributor?
    let people: [Person]
    let existingContributors: [BookContributor]
    let editingIndex: Int?
    let onCreatePerson: (Person) -> Void
    let onSave: (BookContributor) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var role: BookContributorRole
    @State private var selectedPerson: Person?
    @State private var isPresentingPersonPicker = false

    init(
        contributor: BookContributor?,
        people: [Person],
        existingContributors: [BookContributor],
        editingIndex: Int?,
        onCreatePerson: @escaping (Person) -> Void,
        onSave: @escaping (BookContributor) -> Void
    ) {
        self.contributor = contributor
        self.people = people
        self.existingContributors = existingContributors
        self.editingIndex = editingIndex
        self.onCreatePerson = onCreatePerson
        self.onSave = onSave
        _role = State(initialValue: contributor?.role ?? .author)
        _selectedPerson = State(initialValue: contributor?.person)
    }

    private var isDuplicate: Bool {
        guard let selectedPerson else { return false }

        return existingContributors.enumerated().contains { index, existing in
            index != editingIndex
                && existing.role == role
                && existing.person.id == selectedPerson.id
        }
    }

    private var canSave: Bool {
        selectedPerson != nil && !isDuplicate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("book_contributor.section.contribution") {
                    Picker("book_contributor.field.role", selection: $role) {
                        ForEach(BookContributorRole.allCases) { role in
                            Text(role.displayName).tag(role)
                        }
                    }

                    Button {
                        isPresentingPersonPicker = true
                    } label: {
                        HStack {
                            Text("person.title")
                                .foregroundStyle(.primary)

                            Spacer()

                            Text(selectedPerson?.name ?? String(localized: "common.none"))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)

                            Image(systemName: "chevron.right")
                                .font(CatalogTypography.chipLabel)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    if isDuplicate {
                        Label(
                            "book_contributor.validation.duplicate_role",
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(CatalogSemanticColors.destructive)
                    }
                }
            }
            .navigationTitle(contributor == nil ? String(localized: "book_contributor.action.add") : String(localized: "book_contributor.action.edit"))
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
                        guard let selectedPerson else { return }
                        onSave(
                            BookContributor(
                                role: role,
                                order: contributor?.order ?? existingContributors.count,
                                person: selectedPerson
                            )
                        )
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave)
                    .accessibilityLabel(String(localized: "common.save"))
                }
            }
            .sheet(isPresented: $isPresentingPersonPicker) {
                BookPersonSelectionView(
                    selection: $selectedPerson,
                    people: people,
                    onCreate: onCreatePerson
                )
            }
        }
    }
}

private struct BookPersonSelectionView: View {
    @Binding var selection: Person?
    let people: [Person]
    let onCreate: (Person) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredPeople: [Person] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return people }
        return people.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var newPersonName: String? {
        let candidate = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        guard !people.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) else {
            return nil
        }
        return candidate
    }

    var body: some View {
        NavigationStack {
            List {
                if let newPersonName {
                    Button {
                        let newPerson = Person(
                            id: UUID(),
                            name: newPersonName,
                            birthYear: nil,
                            deathYear: nil,
                            biography: nil,
                            birthPlace: nil,
                            deathPlace: nil,
                            photos: []
                        )
                        onCreate(newPerson)
                        selection = newPerson
                        dismiss()
                    } label: {
                        Label(
                            String.localizedStringWithFormat(String(localized: "common.action.add_value"), newPersonName),
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

                ForEach(filteredPeople) { person in
                    Button {
                        selection = person
                        dismiss()
                    } label: {
                        HStack {
                            Text(person.name)
                                .foregroundStyle(.primary)

                            Spacer()

                            if selection?.id == person.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("person.title")
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

private struct BookIdentifierEditorView: View {
    let identifier: BookIdentifier?
    let existingIdentifiers: [BookIdentifier]
    let editingIndex: Int?
    let onSave: (BookIdentifier) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var type: BookIdentifierType
    @State private var value: String

    init(
        identifier: BookIdentifier?,
        existingIdentifiers: [BookIdentifier],
        editingIndex: Int?,
        onSave: @escaping (BookIdentifier) -> Void
    ) {
        self.identifier = identifier
        self.existingIdentifiers = existingIdentifiers
        self.editingIndex = editingIndex
        self.onSave = onSave
        _type = State(initialValue: identifier?.type ?? .isbn13)
        _value = State(initialValue: identifier?.value ?? "")
    }

    private var trimmedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        guard !trimmedValue.isEmpty else { return false }
        let key = bookIdentifierDuplicateKey(type: type, value: trimmedValue)

        return existingIdentifiers.enumerated().contains { index, existing in
            index != editingIndex
                && existing.type == type
                && bookIdentifierDuplicateKey(type: existing.type, value: existing.value) == key
        }
    }

    private var validationMessage: String? {
        guard !trimmedValue.isEmpty else {
            return String(localized: "book_identifier.validation.value_required")
        }

        switch type {
        case .isbn10:
            guard isValidISBN10(trimmedValue) else {
                return String(localized: "book_identifier.validation.isbn10_invalid")
            }
        case .isbn13:
            guard isValidISBN13(trimmedValue) else {
                return String(localized: "book_identifier.validation.isbn13_invalid")
            }
        case .sbn, .asin, .inventory, .other:
            break
        }

        if isDuplicate {
            return String(localized: "book_identifier.validation.duplicate")
        }

        return nil
    }

    private var canSave: Bool {
        validationMessage == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("book_identifier.title") {
                    Picker("common.type", selection: $type) {
                        ForEach(BookIdentifierType.allCases) { type in
                            Text(type.bookEditorDisplayName).tag(type)
                        }
                    }

                    TextField("book_identifier.field.value", text: $value)

                    if let validationMessage {
                        Label(
                            validationMessage,
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(CatalogSemanticColors.destructive)
                    }
                }
            }
            .navigationTitle(identifier == nil ? String(localized: "book_identifier.action.add") : String(localized: "book_identifier.action.edit"))
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
                        onSave(BookIdentifier(type: type, value: trimmedValue))
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave)
                    .accessibilityLabel(String(localized: "common.save"))
                }
            }
        }
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

private extension BookIdentifierType {
    var bookEditorDisplayName: String {
        switch self {
        case .isbn10: "ISBN-10"
        case .isbn13: "ISBN-13"
        case .sbn: "SBN"
        case .asin: "ASIN"
        case .inventory: String(localized: "book.field.inventory")
        case .other: String(localized: "common.other")
        }
    }
}

private func compactBookIdentifier(_ value: String) -> String {
    value.filter { $0.isLetter || $0.isNumber }.uppercased()
}

private func bookIdentifierDuplicateKey(type: BookIdentifierType, value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

    switch type {
    case .isbn10, .isbn13, .sbn:
        return compactBookIdentifier(trimmed)
    case .asin:
        return trimmed.uppercased()
    case .inventory, .other:
        return trimmed.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }
}

private func isValidISBN10(_ value: String) -> Bool {
    let characters = Array(compactBookIdentifier(value))
    guard characters.count == 10 else { return false }
    guard characters.dropLast().allSatisfy(\.isNumber), let last = characters.last else { return false }
    return last.isNumber || last == "X"
}

private func isValidISBN13(_ value: String) -> Bool {
    let characters = Array(compactBookIdentifier(value))
    return characters.count == 13 && characters.allSatisfy(\.isNumber)
}

private func bookLanguageDisplayName(for code: String) -> String {
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
