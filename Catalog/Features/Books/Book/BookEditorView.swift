import CoreData
import Foundation
import SwiftUI
import UIKit

/// Displays the editor used to create or edit a book.
struct BookEditorView: View {
    let collection: CollectionSummary
    private let existingBook: BookRecord?
    private let initialGenreSuggestions: [String]
    private let initialAnalysisImages: [UIImage]
    private let onDelete: (() -> Void)?
    private let onSave: (BookRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isSubtitleFocused: Bool

    @State private var editorState: BookEditorState
    @State private var tagInput = ""
    @State private var isGeneratingCoverImage = false
    @State private var isPresentingCoverCaptureFailure = false

    @State private var catalogGenreSuggestions: [String] = []
    @State private var catalogSeries: [BookSeries] = []
    @State private var catalogPublishers: [Publisher] = []
    @State private var catalogPeople: [Person] = []
    @State private var editorCatalogSnapshot: CatalogSnapshot?
    @State private var isPresentingHomeEditor = false
    @State private var draftHome = Home(id: UUID(), name: "", iconName: "house.fill", notes: "")
    @State private var draftHomeLocations: [Location] = []
    @State private var shouldPresentLocationPickerAfterHomeEditor = false
    @State private var locationPickerPresentationToken = 0
    @State private var editingContributorIndex: Int?
    @State private var isPresentingContributorEditor = false
    @State private var editingIdentifierIndex: Int?
    @State private var isPresentingIdentifierEditor = false
    @State private var isPresentingDeleteConfirmation = false
    @State private var photoAnalysis = BookPhotoAnalysisController()
    @State private var didStartInitialAnalysis = false
    @State private var textAssignmentController = BookTextAssignmentController()

    private let editorItemID: UUID
    private let coverExtractor = BookCoverExtractor()
    private let acquiredYearOptions = [String(localized: "common.none")]
        + Array(1900...Calendar.current.component(.year, from: .now)).reversed().map(String.init)

    private var genreSuggestions: [String] {
        Self.normalizedGenreSuggestions(initialGenreSuggestions + catalogGenreSuggestions)
    }

    private var referenceResolver: BookReferenceResolver {
        BookReferenceResolver(
            collectionID: collection.id,
            catalogSeries: catalogSeries,
            catalogPublishers: catalogPublishers,
            catalogPeople: catalogPeople,
            contributors: editorState.contributors,
            selectedSeries: editorState.selectedSeries,
            selectedPublisher: editorState.selectedPublisher
        )
    }

    private var storageContext: CatalogStorageContext {
        CatalogStorageContext(snapshot: editorCatalogSnapshot, collection: collection)
    }

    private var selectedLocationLabel: String {
        guard let selectedLocationID = editorState.selectedLocationID else {
            return String(localized: "common.unassigned")
        }

        if let path = storageContext.locationPathByID[selectedLocationID] {
            return path
        }

        return storageContext.location(for: selectedLocationID)?.name
            ?? String(localized: "common.unassigned")
    }

    private var shouldShowPhotoAnalysisSection: Bool {
        photoAnalysis.isAnalyzing || photoAnalysis.suggestions.hasSuggestions
    }

    private var firstPhotoAsset: MediaAsset? {
        editorState.mediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first
    }

    private var firstPhotoAssetID: UUID? {
        firstPhotoAsset?.id
    }

    private var editorMediaAssets: Binding<[MediaAsset]> {
        Binding(
            get: {
                guard let coverImage = editorState.coverImage else { return editorState.mediaAssets }
                return [coverImage] + editorState.mediaAssets
            },
            set: { updatedAssets in
                guard let coverImage = editorState.coverImage else {
                    editorState.mediaAssets = updatedAssets
                    return
                }

                if !updatedAssets.contains(where: { $0.id == coverImage.id }) {
                    editorState.coverImage = nil
                }
                editorState.mediaAssets = updatedAssets.filter { $0.id != coverImage.id }
            }
        )
    }

    private var textAssignments: [BookTextTarget: [TextFragment]] {
        textAssignmentController.assignments
    }

    init(
        collection: CollectionSummary,
        initialMediaAssets: [MediaAsset] = [],
        initialAnalysisImage: UIImage? = nil,
        book: BookRecord? = nil,
        genreSuggestions: [String] = [],
        onDelete: (() -> Void)? = nil,
        onSave: @escaping (BookRecord) -> Void
    ) {
        self.collection = collection
        self.existingBook = book
        self.initialGenreSuggestions = genreSuggestions
        let mediaImages = initialMediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { asset -> UIImage? in
                guard let data = asset.originalData else { return nil }
                return UIImage(data: data)
            }
        self.initialAnalysisImages = mediaImages.isEmpty
            ? initialAnalysisImage.map { [$0] } ?? []
            : mediaImages
        self.onDelete = onDelete
        self.onSave = onSave
        self.editorItemID = book?.id ?? UUID()
        _editorState = State(
            initialValue: BookEditorState(
                book: book,
                initialMediaAssets: initialMediaAssets
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "editor.docs_and_media")) {
                    MediaSection(
                        itemID: editorItemID,
                        mediaAssets: editorMediaAssets,
                        analysisHighlightedAssetID: photoAnalysis.isAnalyzing ? firstPhotoAssetID : nil,
                        onPhotoAdded: handlePhotoAdded
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
                                    title: String(localized: "common.field.title"),
                                    suggestedValue: suggestion.value,
                                    confidence: suggestion.confidence,
                                    onAccept: {
                                        editorState.title = suggestion.value
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
                                        editorState.selectedPublicationYearOption = String(suggestion.value)
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
                                        editorState.languageCode = suggestion.value
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
                                        editorState.volumeNumber = String(suggestion.value)
                                        photoAnalysis.dismiss(.volumeNumber)
                                    }
                                )
                            }
                        }
                    }
                }

                Section(String(localized: "common.field.title")) {
                    if !editorState.isTitleValid {
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
                        .listRowSeparator(.hidden, edges: .bottom)
                    }

                    Group {
                        if let assignedFragments = textAssignments[.field(.title)],
                           !assignedFragments.isEmpty {
                            assignedTextFragments(for: .field(.title))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    beginManualTextEditing(in: .title)
                                }
                        } else {
                            TextField(String(localized: "common.field.title"), text: $editorState.title)
                                .focused($isTitleFocused)
                        }
                    }
                    .font(.body.weight(.medium))
                    .listRowSeparator(.hidden, edges: .bottom)
                    .dropDestination(for: TextFragmentTransfer.self) { items, _ in
                        assignTextFragments(items, to: .field(.title))
                    }

                    Group {
                        if let assignedFragments = textAssignments[.field(.subtitle)],
                           !assignedFragments.isEmpty {
                            assignedTextFragments(for: .field(.subtitle))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    beginManualTextEditing(in: .subtitle)
                                }
                        } else {
                            TextField("book.field.subtitle", text: $editorState.subtitle, axis: .vertical)
                                .focused($isSubtitleFocused)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1...3)
                    .dropDestination(for: TextFragmentTransfer.self) { items, _ in
                        assignTextFragments(items, to: .field(.subtitle))
                    }
                }

                BookContributorsEditorSubview(
                    rowCount: editorState.contributors.count,
                    onDelete: deleteContributors
                ) { index in
                    let contributor = editorState.contributors[index]

                    VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                        BookContributorEditorRow(
                            role: contributor.role,
                            person: contributor.person,
                            statusSystemImage: assignedReferenceStatusSystemImage(for: .author(index))
                        ) {
                            editingContributorIndex = index
                            isPresentingContributorEditor = true
                        }

                        if contributor.role == .author {
                            assignedTextFragments(for: .author(index))
                        }
                    }
                    .dropDestination(for: TextFragmentTransfer.self) { items, _ in
                        appendTextFragments(items, toContributorAt: index)
                    }
                } addContent: {
                    Button {
                        editingContributorIndex = nil
                        isPresentingContributorEditor = true
                    } label: {
                        Label("book_contributor.action.add", systemImage: "plus")
                    }
                    .dropDestination(for: TextFragmentTransfer.self) { items, _ in
                        createAuthor(from: items)
                    }
                }

                Section("series.title") {
                    VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                        BookSeriesPickerField(
                            selection: $editorState.selectedSeries,
                            series: referenceResolver.availableSeries,
                            collectionID: collection.id,
                            statusSystemImage: assignedReferenceStatusSystemImage(for: .field(.series)),
                            onCreate: { newSeries in
                                catalogSeries.append(newSeries)
                                editorState.selectedSeries = newSeries
                            }
                        )

                        assignedTextFragments(for: .field(.series))
                    }
                    .dropDestination(for: TextFragmentTransfer.self) { items, _ in
                        assignTextFragments(items, to: .field(.series))
                    }

                    if editorState.selectedSeries != nil {
                        volumeField
                    }
                }

                Section("publisher.title") {
                    VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                        BookPublisherPickerField(
                            selection: $editorState.selectedPublisher,
                            publishers: referenceResolver.availablePublishers,
                            collectionID: collection.id,
                            statusSystemImage: assignedReferenceStatusSystemImage(for: .field(.publisher)),
                            onCreate: { newPublisher in
                                catalogPublishers.append(newPublisher)
                                editorState.selectedPublisher = newPublisher
                            }
                        )

                        assignedTextFragments(for: .field(.publisher))
                    }
                    .dropDestination(for: TextFragmentTransfer.self) { items, _ in
                        assignTextFragments(items, to: .field(.publisher))
                    }
                }

                Section("common.book") {
                    VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                        YearPickerField(
                            title: String(localized: "book.field.publication_year"),
                            selection: $editorState.selectedPublicationYearOption,
                            options: editorState.publicationYearOptions
                        )

                        assignedTextFragments(for: .field(.publicationYear))
                    }
                    .dropDestination(for: TextFragmentTransfer.self) { items, _ in
                        assignTextFragments(items, to: .field(.publicationYear))
                    }

                    optionalPositiveIntegerField(
                        title: String(localized: "book.field.pages"),
                        text: $editorState.pageCount
                    )

                    BookLanguagePickerField(languageCode: $editorState.languageCode)

                    LookupTextField(
                        title: String(localized: "book.field.genre"),
                        value: $editorState.genre,
                        suggestions: genreSuggestions
                    )
                }

                Section("book.section.identifiers") {
                    ForEach(editorState.identifiers.indices, id: \.self) { index in
                        let identifier = editorState.identifiers[index]

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
                        selection: $editorState.selectedAcquiredYearOption,
                        options: acquiredYearOptions
                    )

                    EnumSelectionRow(
                        title: String(localized: "item.detail.acquisition"),
                        selectedLabel: editorState.acquisitionMethod.displayName,
                        options: AcquisitionMethod.allCases,
                        selection: $editorState.acquisitionMethod,
                        optionTitle: \.displayName
                    )

                    EnumSelectionRow(
                        title: String(localized: "common.field.condition"),
                        selectedLabel: editorState.condition.displayName,
                        options: ItemCondition.allCases,
                        selection: $editorState.condition,
                        optionTitle: \.displayName
                    )
                }

                Section(String(localized: "item.detail.section.location")) {
                    LocationPickerField(
                        title: String(localized: "common.location"),
                        selectedLabel: selectedLocationLabel,
                        locations: storageContext.availableLocations,
                        onManageLocations: presentHomeEditor,
                        presentationToken: locationPickerPresentationToken,
                        selectedLocationID: $editorState.selectedLocationID
                    )
                }

                Section(String(localized: "common.field.notes")) {
                    TextField(String(localized: "common.field.notes"), text: $editorState.notes, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)

                    VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
                        Text(String(localized: "common.field.tags"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TagEditorSection(
                            tagInput: $tagInput,
                            tags: $editorState.tags
                        )
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if textAssignmentController.hasUnusedFragments {
                    TextFragmentBar(
                        fragments: textAssignmentController.fragments,
                        usedFragmentIDs: textAssignmentController.usedFragmentIDs
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

                if existingBook != nil, onDelete != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            isPresentingDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .tint(CatalogSemanticColors.destructive)
                        .accessibilityLabel(String(localized: "common.delete"))
                    }
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
            .confirmationDialog(
                String(localized: "book.delete.title"),
                isPresented: $isPresentingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "common.delete"), role: .destructive) {
                    onDelete?()
                }

                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "book.delete.message"))
            }
            .alert(String(localized: "editor.media.cover"), isPresented: $isPresentingCoverCaptureFailure) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text("book.cover.not_found_on_photo.message")
            }
            .task(id: collection.id) {
                loadCatalogMetadata()
                startInitialPhotoAnalysisIfNeeded()
                consumeInitialCoverPhotoIfNeeded()
            }
            .onChange(of: photoAnalysis.recognizedText) { _, recognizedText in
                textAssignmentController.sync(from: recognizedText)
            }
            .sheet(isPresented: $isPresentingContributorEditor) {
                let contributor = editingContributorIndex.flatMap { index in
                    editorState.contributors.indices.contains(index) ? editorState.contributors[index] : nil
                }

                BookContributorEditorView(
                    title: contributor == nil
                        ? String(localized: "book_contributor.action.add")
                        : String(localized: "book_contributor.action.edit"),
                    role: contributor?.role ?? .author,
                    person: contributor?.person,
                    people: referenceResolver.availablePeople,
                    collectionID: collection.id,
                    onCreatePerson: { newPerson in
                        catalogPeople.append(newPerson)
                    },
                    validationMessage: { role, person in
                        guard let person else { return nil }
                        let isDuplicate = editorState.contributors.enumerated().contains { index, existing in
                            index != editingContributorIndex
                                && existing.role == role
                                && existing.person.id == person.id
                        }
                        return isDuplicate
                            ? String(localized: "book_contributor.validation.duplicate_role")
                            : nil
                    },
                    onSave: { role, person in
                        saveContributor(
                            BookContributor(
                                role: role,
                                order: contributor?.order ?? editorState.contributors.count,
                                person: person
                            )
                        )
                    }
                )
            }
            .sheet(isPresented: $isPresentingIdentifierEditor) {
                BookIdentifierEditorView(
                    identifier: editingIdentifierIndex.flatMap { index in
                        editorState.identifiers.indices.contains(index) ? editorState.identifiers[index] : nil
                    },
                    existingIdentifiers: editorState.identifiers,
                    editingIndex: editingIdentifierIndex,
                    onSave: saveIdentifier
                )
            }
            .sheet(isPresented: $isPresentingHomeEditor) {
                HomeEditorView(
                    home: $draftHome,
                    locations: $draftHomeLocations,
                    onSave: saveHomeAndLocations,
                    onDelete: nil
                )
            }
        }
    }

    @ViewBuilder
    private func assignedTextFragments(for target: BookTextTarget) -> some View {
        if let fragments = textAssignments[target], !fragments.isEmpty {
            TagFlowLayout(spacing: CatalogMetrics.Spacing.xs) {
                ForEach(Array(fragments.enumerated()), id: \.element.id) { _, fragment in
                    AssignedTextFragmentChip(
                        fragment: fragment,
                        statusSystemImage: nil
                    ) {
                        removeTextFragment(fragment, from: target)
                    }
                }
            }
        }
    }

    private func assignedReferenceStatusSystemImage(for target: BookTextTarget) -> String? {
        guard let fragments = textAssignments[target], !fragments.isEmpty else { return nil }
        return referenceResolver.status(for: target)?.systemImage
    }

    private var canSave: Bool {
        editorState.canSave(isGeneratingCoverImage: isGeneratingCoverImage)
    }

    private var volumeField: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
            LabeledContent("book.field.volume") {
                numericTextField($editorState.volumeNumber)
            }

            assignedTextFragments(for: .field(.volume))

            if !editorState.isVolumeValid {
                Label(
                    editorState.volumeValidationMessage,
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(CatalogSemanticColors.destructive)
            }
        }
        .dropDestination(for: TextFragmentTransfer.self) { items, _ in
            assignTextFragments(items, to: .field(.volume))
        }
    }

    private func optionalPositiveIntegerField(
        title: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
            LabeledContent(title) {
                numericTextField(text)
            }

            if !editorState.isOptionalPositiveIntegerValid(text.wrappedValue) {
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

    @MainActor
    private func handlePhotoAdded(_ image: UIImage) {
        guard editorState.coverImage == nil, !isGeneratingCoverImage else { return }
        guard let sourceAsset = editorState.mediaAssets
            .filter({ $0.kind == .photo })
            .max(by: { $0.sortOrder < $1.sortOrder }) else {
            return
        }

        consumePhotoAsCover(image, sourceAsset: sourceAsset)
    }

    @MainActor
    private func consumeInitialCoverPhotoIfNeeded() {
        guard existingBook == nil,
              editorState.coverImage == nil,
              !isGeneratingCoverImage,
              let sourceAsset = firstPhotoAsset,
              let sourceData = sourceAsset.originalData,
              let image = UIImage(data: sourceData) else {
            return
        }

        consumePhotoAsCover(image, sourceAsset: sourceAsset)
    }

    @MainActor
    private func consumePhotoAsCover(_ image: UIImage, sourceAsset: MediaAsset) {
        editorState.mediaAssets = editorState.mediaAssets
            .filter { $0.id != sourceAsset.id }
            .enumerated()
            .map { index, asset in
                asset.with(sortOrder: index)
            }
        LocalMediaFileStore.shared.deleteFile(for: sourceAsset.localIdentifier)

        isGeneratingCoverImage = true
        Task { @MainActor in
            let extractedCover = await coverExtractor.extractCover(from: image)
            isGeneratingCoverImage = false

            guard let extractedCover else {
                isPresentingCoverCaptureFailure = true
                return
            }

            editorState.coverImage = extractedCover.with(
                displayName: String(localized: "editor.media.cover")
            )
        }
    }

    private func startInitialPhotoAnalysisIfNeeded() {
        guard !didStartInitialAnalysis,
              existingBook == nil,
              !initialAnalysisImages.isEmpty else { return }

        didStartInitialAnalysis = true
        photoAnalysis.analyze(images: initialAnalysisImages)
    }

    @discardableResult
    private func assignTextFragments(
        _ droppedFragments: [TextFragmentTransfer],
        to target: BookTextTarget
    ) -> Bool {
        guard let preparedAssignment = textAssignmentController.prepareAssignment(
            droppedFragments,
            to: target
        ), applyTextAssignment(preparedAssignment.assignment, to: target) else {
            return false
        }

        textAssignmentController.commit(preparedAssignment)
        return true
    }

    private func removeTextFragment(_ fragment: TextFragment, from target: BookTextTarget) {
        switch textAssignmentController.remove(fragment, from: target) {
        case let .apply(assignment):
            _ = applyTextAssignment(assignment, to: target)
        case let .deleteAuthor(index):
            deleteContributors(at: IndexSet(integer: index))
        }
    }

    @discardableResult
    private func applyTextAssignment(
        _ assignment: BookTextAssignment,
        to target: BookTextTarget
    ) -> Bool {
        switch target {
        case let .field(field):
            switch field {
            case .title:
                editorState.title = assignment.text
                return true
            case .subtitle:
                editorState.subtitle = assignment.text
                return true
            case .publicationYear:
                guard !assignment.text.isEmpty else {
                    editorState.selectedPublicationYearOption = String(localized: "common.none")
                    return true
                }
                guard let year = Int(assignment.text) else { return false }
                editorState.selectedPublicationYearOption = String(year)
                return true
            case .publisher:
                guard !assignment.text.isEmpty else {
                    editorState.selectedPublisher = nil
                    return true
                }
                guard let publisher = referenceResolver.resolvePublisher(named: assignment.text) else { return false }
                editorState.selectedPublisher = publisher
                return true
            case .series:
                guard !assignment.text.isEmpty else {
                    editorState.selectedSeries = nil
                    return true
                }
                guard let series = referenceResolver.resolveSeries(named: assignment.text) else { return false }
                editorState.selectedSeries = series
                return true
            case .volume:
                guard !assignment.text.isEmpty else {
                    editorState.volumeNumber = ""
                    return true
                }
                guard let number = BookTextAssignmentRules.firstPositiveInteger(in: assignment.text) else { return false }
                editorState.volumeNumber = String(number)
                return true
            }

        case let .author(index):
            guard editorState.contributors.indices.contains(index),
                  editorState.contributors[index].role == .author else {
                return false
            }

            let baseName = textAssignmentController.authorBaseName(for: index) ?? ""
            let name = [baseName, assignment.text]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " ")
            guard let person = referenceResolver.resolvePerson(named: name) else { return false }

            let contributor = editorState.contributors[index]
            editorState.contributors[index] = BookContributor(
                role: contributor.role,
                order: contributor.order,
                person: person
            )
            return true
        }
    }

    private func beginManualTextEditing(in field: BookTextField) {
        guard field == .title || field == .subtitle else { return }

        let target = BookTextTarget.field(field)
        guard textAssignmentController.consumeAssignment(for: target) else { return }

        switch field {
        case .title:
            isTitleFocused = true
        case .subtitle:
            isSubtitleFocused = true
        case .publicationYear, .publisher, .series, .volume:
            break
        }
    }

    @discardableResult
    private func createAuthor(from droppedFragments: [TextFragmentTransfer]) -> Bool {
        var fragments = textAssignmentController.matching(droppedFragments)
        guard !fragments.isEmpty else { return false }
        fragments.sort(by: TextFragment.readingOrder)

        for index in textAssignmentController.authorIndices {
            let target = BookTextTarget.author(index)
            guard editorState.contributors.indices.contains(index),
                  editorState.contributors[index].role == .author,
                  textAssignmentController.authorBaseName(for: index) == "",
                  let existingFragments = textAssignmentController.assignment(for: target) else { continue }

            var combinedFragments = existingFragments
            for fragment in fragments where !combinedFragments.contains(fragment) {
                combinedFragments.append(fragment)
            }
            combinedFragments.sort(by: TextFragment.readingOrder)

            let combinedName = combinedFragments.map(\.text).joined(separator: " ")
            guard let existingPerson = referenceResolver.existingCatalogPerson(named: combinedName) else {
                continue
            }

            let contributor = editorState.contributors[index]
            textAssignmentController.setAssignment(combinedFragments, for: target)
            editorState.contributors[index] = BookContributor(
                role: contributor.role,
                order: contributor.order,
                person: existingPerson
            )
            return true
        }

        let name = fragments.map(\.text).joined(separator: " ")
        guard let person = referenceResolver.resolvePerson(named: name) else { return false }

        let index = editorState.contributors.count
        editorState.contributors.append(
            BookContributor(
                role: .author,
                order: index,
                person: person
            )
        )
        normalizeContributorOrder()
        textAssignmentController.setAssignment(fragments, for: .author(index))
        textAssignmentController.setAuthorBaseName("", for: index)
        return true
    }

    @discardableResult
    private func appendTextFragments(
        _ droppedFragments: [TextFragmentTransfer],
        toContributorAt index: Int
    ) -> Bool {
        guard editorState.contributors.indices.contains(index),
              editorState.contributors[index].role == .author else {
            return false
        }

        let target = BookTextTarget.author(index)
        if textAssignmentController.authorBaseName(for: index) == nil {
            textAssignmentController.setAuthorBaseName(
                editorState.contributors[index].person.displayName,
                for: index
            )
        }

        guard let preparedAssignment = textAssignmentController.prepareAssignment(
            droppedFragments,
            to: target
        ), applyTextAssignment(preparedAssignment.assignment, to: target) else {
            return false
        }

        textAssignmentController.commit(preparedAssignment)
        return true
    }

    private func applyAuthorSuggestions(_ suggestions: [SuggestedFieldValue<String>]) {
        let originalAuthorIndex = editorState.contributors.firstIndex { $0.role == .author }
            ?? editorState.contributors.count
        var seen: Set<String> = []
        var authorPeople: [Person] = []

        for suggestion in suggestions {
            let name = suggestion.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = referenceResolver.normalizedKey(name)
            guard !name.isEmpty, seen.insert(key).inserted,
                  let person = referenceResolver.resolvePerson(named: name) else { continue }
            authorPeople.append(person)
        }

        var updated = editorState.contributors.filter { $0.role != .author }
        let insertionIndex = min(originalAuthorIndex, updated.count)
        let newAuthors = authorPeople.enumerated().map { index, person in
            BookContributor(
                role: .author,
                order: insertionIndex + index,
                person: person
            )
        }
        updated.insert(contentsOf: newAuthors, at: insertionIndex)
        editorState.contributors = updated.enumerated().map { index, contributor in
            var normalized = contributor
            normalized.order = index
            return normalized
        }
    }

    private func applyIdentifierSuggestions(_ suggestions: [SuggestedFieldValue<BookIdentifier>]) {
        for suggestion in suggestions {
            let candidate = suggestion.value
            let candidateKey = bookIdentifierDuplicateKey(type: candidate.type, value: candidate.value)
            let isDuplicate = editorState.identifiers.contains { existing in
                existing.type == candidate.type
                    && bookIdentifierDuplicateKey(type: existing.type, value: existing.value) == candidateKey
            }

            if !isDuplicate {
                editorState.identifiers.append(candidate)
            }
        }
    }

    private func applyPublisherSuggestion(_ suggestion: SuggestedFieldValue<String>) {
        editorState.selectedPublisher = referenceResolver.resolvePublisher(named: suggestion.value)
    }

    private func applySeriesSuggestion(_ suggestion: SuggestedFieldValue<String>) {
        editorState.selectedSeries = referenceResolver.resolveSeries(named: suggestion.value)
    }

    private func saveContributor(_ contributor: BookContributor) {
        if let editingContributorIndex,
           editorState.contributors.indices.contains(editingContributorIndex) {
            editorState.contributors[editingContributorIndex] = contributor
        } else {
            editorState.contributors.append(contributor)
        }
        normalizeContributorOrder()
    }

    private func deleteContributors(at offsets: IndexSet) {
        let removedIndices = Set(offsets)
        let survivingIndices = editorState.contributors.indices.filter { !removedIndices.contains($0) }

        editorState.contributors.remove(atOffsets: offsets)
        textAssignmentController.remapAuthors(survivingIndices: survivingIndices)
        normalizeContributorOrder()
    }

    private func normalizeContributorOrder() {
        editorState.contributors = editorState.contributors.enumerated().map { index, contributor in
            var normalized = contributor
            normalized.order = index
            return normalized
        }
    }

    private func saveIdentifier(_ identifier: BookIdentifier) {
        if let editingIdentifierIndex,
           editorState.identifiers.indices.contains(editingIdentifierIndex) {
            editorState.identifiers[editingIdentifierIndex] = identifier
        } else {
            editorState.identifiers.append(identifier)
        }
    }

    private func deleteIdentifiers(at offsets: IndexSet) {
        editorState.identifiers.remove(atOffsets: offsets)
    }

    @MainActor
    private func loadCatalogMetadata() {
        let snapshot = CatalogSnapshot.load(from: managedObjectContext)
        editorCatalogSnapshot = snapshot
        let bookRecords = snapshot.bookRecords

        catalogGenreSuggestions = bookRecords
            .filter { $0.collectionID == collection.id }
            .compactMap(\.details.genre)
        catalogSeries = snapshot.bookSeries
            .filter { $0.collectionID == collection.id }
        catalogPublishers = snapshot.publishers
        catalogPeople = snapshot.people
    }

    @MainActor
    private func presentHomeEditor() {
        if editorCatalogSnapshot == nil {
            loadCatalogMetadata()
        }

        guard let snapshot = editorCatalogSnapshot,
              let home = snapshot.homes.first(where: { $0.id == collection.homeID }) else {
            return
        }

        draftHome = home
        draftHomeLocations = snapshot.locationsByHomeID[collection.homeID] ?? []
        shouldPresentLocationPickerAfterHomeEditor = true
        isPresentingHomeEditor = true
    }

    @MainActor
    private func saveHomeAndLocations() {
        let repository = CoreDataCatalogRepository(context: managedObjectContext)
        repository.saveHome(draftHome)
        repository.saveLocations(draftHomeLocations, in: draftHome.id)
        loadCatalogMetadata()
        continueLocationSelectionIfNeeded()
    }

    private func continueLocationSelectionIfNeeded() {
        guard shouldPresentLocationPickerAfterHomeEditor else { return }
        shouldPresentLocationPickerAfterHomeEditor = false
        isPresentingHomeEditor = false
        DispatchQueue.main.async {
            locationPickerPresentationToken += 1
        }
    }

    private func resolvedStorage() -> (location: Location?, path: StoragePath?) {
        guard let selectedLocationID = editorState.selectedLocationID else {
            return (nil, nil)
        }

        if let location = storageContext.location(for: selectedLocationID) {
            return (location, storageContext.storagePath(for: location))
        }

        if selectedLocationID == existingBook?.item.locationID {
            return (existingBook?.storageLocation, existingBook?.storagePath)
        }

        return (nil, nil)
    }

    private func saveBook() {
        guard canSave else {
            if !editorState.isTitleValid {
                isTitleFocused = true
            }
            return
        }

        let storage = resolvedStorage()
        let book = editorState.makeBook(
            itemID: editorItemID,
            collectionID: collection.id,
            existingBook: existingBook,
            storageLocation: storage.location,
            storagePath: storage.path
        )

        onSave(book)
        dismiss()
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
