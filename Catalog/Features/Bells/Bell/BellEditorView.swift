import SwiftUI
import Translation

/// Displays the bell editor view interface.
struct BellEditorView: View {
    enum StartSection: Hashable {
        case storage
    }

    private enum AnalysisFeedback: Equatable {
        case success
        case warning

        var sensoryFeedback: SensoryFeedback {
            switch self {
            case .success:
                return .impact(weight: .light)
            case .warning:
                return .warning
            }
        }
    }

    private struct AnalysisFeedbackEvent: Equatable {
        let kind: AnalysisFeedback
        let token: Int
    }

    private struct LocalizedPhotoSuggestions {
        var title: String?
        var notes: String?
        var customMaterialName: String?
        var suggestedTags: [String]
    }

    private enum PhotoSuggestionTranslationTarget {
        case title
        case notes
        case customMaterialName
        case suggestedTag(Int)
    }

    private enum FocusedField: Hashable {
        case title
    }

    let collection: CollectionSummary
    let repository: any CatalogRepository
    let catalogSnapshot: CatalogSnapshot?
    let startSection: StartSection?
    private let initialAnalysisImages: [UIImage]
    private let existingBell: BellRecord?
    private let onDelete: (() -> Void)?
    let onSave: (BellRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @FocusState private var focusedField: FocusedField?
    @State private var editorState: BellEditorState
    @State private var tagInput = ""
    @State private var highlightedSection: StartSection?
    @State private var analysisFeedbackEvent: AnalysisFeedbackEvent?
    @State private var analysisFeedbackToken = 0
    @State private var photoAnalysis: BellPhotoAnalysisController
    @State private var localizedPhotoSuggestions: LocalizedPhotoSuggestions?
    @State private var pendingPhotoSuggestionsForTranslation: BellPhotoSuggestions?
    @State private var isLocalizingPhotoSuggestions = false
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var didStartInitialAnalysis = false
    @State private var isPresentingHomeEditor = false
    @State private var draftHome = Home(id: UUID(), name: "", iconName: "house.fill", notes: "")
    @State private var draftHomeLocations: [Location] = []
    @State private var shouldPresentLocationPickerAfterHomeEditor = false
    @State private var locationPickerPresentationToken = 0
    @State private var isPresentingDeleteConfirmation = false
    private let editorItemID: UUID

    private let acquiredYearOptions = [String(localized: "common.none")] + Array(1900...Calendar.current.component(.year, from: .now)).reversed().map(String.init)

    private var storageContext: CatalogStorageContext {
        CatalogStorageContext(snapshot: catalogSnapshot, collection: collection)
    }

    private var availableLocations: [Location] {
        storageContext.availableLocations
    }

    private var availablePlaces: [Place] {
        (catalogSnapshot?.places ?? []).filter { $0.collectionID == collection.id }
    }

    private var locationPathByID: [UUID: String] {
        storageContext.locationPathByID
    }

    private var canSave: Bool {
        editorState.canSave
    }

    private var shouldShowPhotoAnalysisSection: Bool {
        photoAnalysis.isAnalyzing
        || (!isLocalizingPhotoSuggestions && (
            photoAnalysis.suggestions.title != nil
            || photoAnalysis.suggestions.notes != nil
            || photoAnalysis.suggestions.material != nil
            || photoAnalysis.suggestions.condition != nil
            || photoAnalysis.suggestions.suggestedYear != nil
            || photoAnalysis.suggestions.suggestedGeo != nil
            || !photoAnalysis.suggestions.suggestedTags.isEmpty
        ))
    }

    init(
        collection: CollectionSummary,
        repository: any CatalogRepository,
        catalogSnapshot: CatalogSnapshot?,
        bell: BellRecord? = nil,
        initialMediaAssets: [MediaAsset] = [],
        startSection: StartSection? = nil,
        onDelete: (() -> Void)? = nil,
        onSave: @escaping (BellRecord) -> Void
    ) {
        self.collection = collection
        self.repository = repository
        self.catalogSnapshot = catalogSnapshot
        self.startSection = startSection
        self.initialAnalysisImages = initialMediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { asset -> UIImage? in
                guard let data = asset.originalData else { return nil }
                return UIImage(data: data)
            }
        self.existingBell = bell
        self.onDelete = onDelete
        self.onSave = onSave
        let editorItemID = bell?.id ?? UUID()
        self.editorItemID = editorItemID
        _photoAnalysis = State(
            initialValue: ItemRecognitionSessionStore.shared.session(
                for: editorItemID,
                as: BellPhotoAnalysisController.self,
                create: BellPhotoAnalysisController.init
            )
        )
        _editorState = State(
            initialValue: BellEditorState(
                bell: bell,
                initialMediaAssets: initialMediaAssets
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                VStack(spacing: 0) {
                    Form {
                        Section(String(localized: "editor.docs_and_media"))
                        {
                            MediaSection(
                                itemID: editorItemID,
                                mediaAssets: $editorState.mediaAssets,
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
                                    if !photoAnalysis.suggestions.isBellDetected {
                                        Label {
                                            Text("editor.analysis.bell_not_found")
                                                .font(.footnote)
                                                .foregroundStyle(.primary)
                                        } icon: {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(.orange)
                                        }
                                        .padding(.vertical, CatalogMetrics.Spacing.xs)
                                        .listRowBackground(collection.backgroundStyle.accentColor.opacity(0.10))
                                    }

                                    if let titleSuggestion = photoAnalysis.suggestions.title {
                                        PhotoSuggestionRow(
                                            title: String(localized: "common.field.title"),
                                            suggestedValue: localizedPhotoSuggestions?.title ?? titleSuggestion.value,
                                            confidence: titleSuggestion.confidence,
                                            onAccept: {
                                                editorState.title = titleSuggestion.value
                                                localizedPhotoSuggestions?.title = nil
                                                photoAnalysis.dismiss(.title)
                                            }
                                        )
                                    }

                                    if let notesSuggestion = photoAnalysis.suggestions.notes {
                                        PhotoSuggestionRow(
                                            title: String(localized: "editor.photo_analysis.notes"),
                                            suggestedValue: localizedPhotoSuggestions?.notes ?? notesSuggestion.value,
                                            confidence: notesSuggestion.confidence,
                                            onAccept: {
                                                editorState.notes = notesSuggestion.value
                                                localizedPhotoSuggestions?.notes = nil
                                                photoAnalysis.dismiss(.notes)
                                            }
                                        )
                                    }

                                    if let materialSuggestion = photoAnalysis.suggestions.material {
                                        PhotoSuggestionRow(
                                            title: String(localized: "editor.photo_analysis.material"),
                                            suggestedValue: materialSuggestionLabel(materialSuggestion),
                                            confidence: materialSuggestion.confidence,
                                            onAccept: {
                                                editorState.material = materialSuggestion.value
                                                if materialSuggestion.value == .other {
                                                    editorState.customMaterialName = photoAnalysis.suggestions.customMaterialName?.value ?? ""
                                                    localizedPhotoSuggestions?.customMaterialName = nil
                                                    photoAnalysis.dismiss(.customMaterialName)
                                                } else {
                                                    editorState.customMaterialName = ""
                                                }
                                                photoAnalysis.dismiss(.material)
                                            }
                                        )
                                    }

                                    if let conditionSuggestion = photoAnalysis.suggestions.condition {
                                        PhotoSuggestionRow(
                                            title: String(localized: "common.field.condition"),
                                            suggestedValue: conditionSuggestion.value.displayName,
                                            confidence: conditionSuggestion.confidence,
                                            onAccept: {
                                                editorState.condition = conditionSuggestion.value
                                                photoAnalysis.dismiss(.condition)
                                            }
                                        )
                                    }

                                    if let yearSuggestion = photoAnalysis.suggestions.suggestedYear {
                                        PhotoSuggestionRow(
                                            title: String(localized: "editor.photo_analysis.year"),
                                            suggestedValue: String(yearSuggestion.value),
                                            confidence: yearSuggestion.confidence,
                                            onAccept: {
                                                editorState.selectedAcquiredYearOption = String(yearSuggestion.value)
                                                photoAnalysis.dismiss(.suggestedYear)
                                            }
                                        )
                                    }

                                    if let geoSuggestion = photoAnalysis.suggestions.suggestedGeo {
                                        PhotoSuggestionRow(
                                            title: String(localized: "common.ui.origin"),
                                            suggestedValue: geoSuggestion.value.name,
                                            confidence: geoSuggestion.confidence,
                                            onAccept: {
                                                editorState.selectedOriginPlace = place(from: geoSuggestion.value)
                                                photoAnalysis.dismiss(.suggestedGeo)
                                            }
                                        )
                                    }

                                    if !photoAnalysis.suggestions.suggestedTags.isEmpty {
                                        PhotoSuggestedTagsRow(
                                            title: String(localized: "common.field.tags"),
                                            suggestions: photoAnalysis.suggestions.suggestedTags,
                                            localizedSuggestions: localizedPhotoSuggestions?.suggestedTags,
                                            onAccept: { newValues in
                                                for value in newValues where !editorState.tags.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
                                                    editorState.tags.append(value)
                                                }
                                                localizedPhotoSuggestions?.suggestedTags = []
                                                photoAnalysis.dismiss(.suggestedTags)
                                            }
                                        )
                                    }
                                }
                            }
                        }

                        Section(String(localized: "common.field.description")) {
                            TextField(String(localized: "editor.short_description"), text: $editorState.title)
                                .focused($focusedField, equals: .title)

                            if !editorState.isTitleValid {
                                Button {
                                    focusTitleValidation()
                                } label: {
                                    Label {
                                        Text(String(localized: "editor.title.required"))
                                            .font(.footnote)
                                    } icon: {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.footnote)
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(CatalogSemanticColors.destructive)
                                .accessibilityHint(String(localized: "editor.title.focus"))
                            }

                            TextField(String(localized: "editor.note_history"), text: $editorState.notes, axis: .vertical)
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

                        Section(String(localized: "editor.acquisition_details")) {
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
                        }

                        Section(String(localized: "editor.attributes")) {
                            EnumSelectionRow(
                                title: String(localized: "common.field.condition"),
                                selectedLabel: editorState.condition.displayName,
                                options: ItemCondition.allCases,
                                selection: $editorState.condition,
                                optionTitle: \.displayName
                            )

                            EnumSelectionRow(
                                title: String(localized: "common.field.material"),
                                selectedLabel: editorState.material.displayName,
                                options: BellMaterial.allCases,
                                selection: $editorState.material,
                                optionTitle: \.displayName
                            )

                            if editorState.material == .other {
                                TextField(String(localized: "editor.material.custom"), text: $editorState.customMaterialName)
                            }

                        }

                        Section(String(localized: "item.detail.section.location")) {
                            PlacePickerField(
                                title: String(localized: "common.ui.origin"),
                                selectedLabel: selectedOriginLabel,
                                collectionID: collection.id,
                                places: availablePlaces,
                                selectedPlace: $editorState.selectedOriginPlace
                            )

                            LocationPickerField(
                                title: String(localized: "common.location"),
                                selectedLabel: selectedLocationLabel,
                                locations: availableLocations,
                                onManageLocations: {
                                    presentHomeEditor()
                                },
                                presentationToken: locationPickerPresentationToken,
                                selectedLocationID: $editorState.selectedLocationID
                            )
                        }
                    }
                }
                .navigationTitle(existingBell == nil ? String(localized: "editor.bell.add") : String(localized: "editor.bell.edit"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(String(localized: "common.cancel"))
                    }

                    if existingBell != nil, onDelete != nil {
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
                        Button { requestSave() } label: { Image(systemName: "checkmark") }
                        .opacity(canSave ? 1 : 0.35)
                        .accessibilityLabel(String(localized: "common.save"))
                    }
                }
                .confirmationDialog(
                    String(localized: "bell.context.delete.title"),
                    isPresented: $isPresentingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "common.delete"), role: .destructive) {
                        onDelete?()
                    }

                    Button(String(localized: "common.cancel"), role: .cancel) {}
                } message: {
                    Text(String(localized: "bell.context.delete.message"))
                }
                .task {
                    startInitialPhotoAnalysisIfNeeded()
                    guard let startSection else { return }
                    highlightedSection = startSection
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation(.snappy(duration: 0.28)) {
                        scrollProxy.scrollTo(startSection, anchor: .top)
                    }
                    try? await Task.sleep(for: .seconds(1.2))
                    if highlightedSection == startSection {
                        withAnimation(.easeOut(duration: 0.35)) {
                            highlightedSection = nil
                        }
                    }
                }
                .sensoryFeedback(trigger: analysisFeedbackEvent) { _, newValue in
                    newValue?.kind.sensoryFeedback
                }
                .onChange(of: photoAnalysis.isAnalyzing) { wasAnalyzing, isAnalyzing in
                    guard wasAnalyzing, !isAnalyzing else { return }
                    Task {
                        await handlePhotoAnalysisCompletion()
                    }
                }
                .translationTask(translationConfiguration) { session in
                    let translator = TextTranslator(sourceLanguage: Locale.Language(identifier: "en"))
                    await translatePhotoSuggestions(using: session, translator: translator)
                }
                .sheet(isPresented: $isPresentingHomeEditor) {
                    HomeEditorView(
                        home: $draftHome,
                        locations: $draftHomeLocations,
                        onSave: {
                            repository.saveHome(draftHome)
                            repository.saveLocations(draftHomeLocations, in: draftHome.id)
                            continueLocationSelectionIfNeeded()
                        },
                        onDelete: nil
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func sectionBackground(for section: StartSection) -> some View {
        if highlightedSection == section {
            CatalogShapes.tile
                .fill(collection.backgroundStyle.accentColor.opacity(0.10))
        } else {
            Color.clear
        }
    }

    private func emitAnalysisFeedback(_ kind: AnalysisFeedback) {
        analysisFeedbackToken += 1
        analysisFeedbackEvent = AnalysisFeedbackEvent(kind: kind, token: analysisFeedbackToken)
    }

    private func handlePhotoAnalysisCompletion() async {
        if photoAnalysis.suggestions.hasSuggestions {
            emitAnalysisFeedback(.success)
            let suggestions = photoAnalysis.suggestions
            let sourceLanguage = Locale.Language(identifier: "en")
            let translator = TextTranslator(sourceLanguage: sourceLanguage)

            switch await translator.preparationState() {
            case .ready:
                pendingPhotoSuggestionsForTranslation = suggestions
            case .needsDownload, .unsupported, .notRequired:
                localizedPhotoSuggestions = localizedPhotoSuggestions(from: suggestions)
                pendingPhotoSuggestionsForTranslation = nil
                isLocalizingPhotoSuggestions = false
                translationConfiguration = nil
                return
            }

            translationConfiguration = TranslationSession.Configuration(
                source: sourceLanguage,
                target: locale.language
            )
        } else {
            isLocalizingPhotoSuggestions = false
            pendingPhotoSuggestionsForTranslation = nil
            translationConfiguration = nil
        }

        // Keep failures / empty results silent by default.
        // If the analysis flow is re-enabled and warning feedback is needed later,
        // emit `.warning` here in a more selective way.
    }

    private func handlePhotoAdded(_ image: UIImage) {
        guard let asset = editorState.mediaAssets
            .filter({ $0.kind == .photo })
            .max(by: { $0.sortOrder < $1.sortOrder }) else {
            return
        }

        isLocalizingPhotoSuggestions = true
        localizedPhotoSuggestions = nil
        pendingPhotoSuggestionsForTranslation = nil
        translationConfiguration = nil
        photoAnalysis.analyzeAddedPhoto(assetID: asset.id, image: image)
    }

    private func startInitialPhotoAnalysisIfNeeded() {
        guard !didStartInitialAnalysis,
              existingBell == nil,
              !initialAnalysisImages.isEmpty else { return }
        didStartInitialAnalysis = true
        isLocalizingPhotoSuggestions = true
        localizedPhotoSuggestions = nil
        pendingPhotoSuggestionsForTranslation = nil
        translationConfiguration = nil
        photoAnalysis.analyze(images: initialAnalysisImages)
    }

    private func translatePhotoSuggestions(
        using session: TranslationSession,
        translator: TextTranslator
    ) async {
        guard let suggestions = pendingPhotoSuggestionsForTranslation else {
            isLocalizingPhotoSuggestions = false
            translationConfiguration = nil
            return
        }

        guard !translator.sourceLanguage.isEquivalent(to: locale.language) else {
            localizedPhotoSuggestions = localizedPhotoSuggestions(from: suggestions)
            pendingPhotoSuggestionsForTranslation = nil
            isLocalizingPhotoSuggestions = false
            translationConfiguration = nil
            return
        }

        var targets: [PhotoSuggestionTranslationTarget] = []
        var texts: [String] = []

        if let title = suggestions.title?.value {
            targets.append(.title)
            texts.append(title)
        }

        if let notes = suggestions.notes?.value {
            targets.append(.notes)
            texts.append(notes)
        }

        if let customMaterialName = suggestions.customMaterialName?.value {
            targets.append(.customMaterialName)
            texts.append(customMaterialName)
        }

        for (index, tag) in suggestions.suggestedTags.enumerated() {
            targets.append(.suggestedTag(index))
            texts.append(tag.value)
        }

        nonisolated(unsafe) let translationSession = session
        let translatedTexts = await translator.translate(texts, using: translationSession)
        guard !Task.isCancelled else { return }

        var localizedSuggestions = localizedPhotoSuggestions(from: suggestions)

        for (target, translatedText) in zip(targets, translatedTexts) {
            switch target {
            case .title:
                localizedSuggestions.title = translatedText
            case .notes:
                localizedSuggestions.notes = translatedText
            case .customMaterialName:
                localizedSuggestions.customMaterialName = translatedText
            case .suggestedTag(let index):
                if localizedSuggestions.suggestedTags.indices.contains(index) {
                    localizedSuggestions.suggestedTags[index] = translatedText.lowercased(with: locale)
                }
            }
        }

        localizedPhotoSuggestions = localizedSuggestions
        pendingPhotoSuggestionsForTranslation = nil
        isLocalizingPhotoSuggestions = false
        translationConfiguration = nil
    }

    private func localizedPhotoSuggestions(from suggestions: BellPhotoSuggestions) -> LocalizedPhotoSuggestions {
        LocalizedPhotoSuggestions(
            title: suggestions.title?.value,
            notes: suggestions.notes?.value,
            customMaterialName: suggestions.customMaterialName?.value,
            suggestedTags: suggestions.suggestedTags.map(\.value)
        )
    }

    private func presentHomeEditor() {
        guard let snapshot = catalogSnapshot,
              let home = snapshot.homes.first(where: { $0.id == collection.homeID }) else { return }
        draftHome = home
        draftHomeLocations = snapshot.locationsByHomeID[collection.homeID] ?? []
        shouldPresentLocationPickerAfterHomeEditor = true
        isPresentingHomeEditor = true
    }

    private func continueLocationSelectionIfNeeded() {
        guard shouldPresentLocationPickerAfterHomeEditor else { return }
        shouldPresentLocationPickerAfterHomeEditor = false
        isPresentingHomeEditor = false
        DispatchQueue.main.async {
            locationPickerPresentationToken += 1
        }
    }

    private func requestSave() {
        guard canSave else {
            if !editorState.isTitleValid {
                focusTitleValidation()
            } else {
                emitAnalysisFeedback(.warning)
            }
            return
        }

        emitAnalysisFeedback(.success)
        saveBell()
    }

    private func focusTitleValidation() {
        emitAnalysisFeedback(.warning)
        focusedField = .title
    }

    private var firstPhotoAssetID: UUID? {
        editorState.mediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first?
            .id
    }

    private func saveBell() {
        let storageLocation = storageContext.location(for: editorState.selectedLocationID)
        let newBell = editorState.makeBell(
            itemID: editorItemID,
            collectionID: collection.id,
            existingBell: existingBell,
            storageLocation: storageLocation,
            storagePath: storageLocation.map(storageContext.storagePath(for:))
        )

        onSave(newBell)
        dismiss()
    }

    private var selectedOriginLabel: String {
        editorState.selectedOriginPlace?.displayName ?? String(localized: "common.unassigned")
    }

    private func place(from geoPoint: GeoPoint) -> Place {
        Place(
            id: UUID(),
            collectionID: collection.id,
            displayName: geoPoint.name,
            countryCode: "",
            countryName: geoPoint.name,
            regionName: nil,
            cityName: nil,
            latitude: geoPoint.coordinate?.latitude,
            longitude: geoPoint.coordinate?.longitude
        )
    }

    private var selectedLocationLabel: String {
        guard let selectedLocationID = editorState.selectedLocationID,
              let path = locationPathByID[selectedLocationID] else {
            return String(localized: "common.unassigned")
        }

        return path
    }

    private func materialSuggestionLabel(_ suggestion: SuggestedFieldValue<BellMaterial>) -> String {
        if suggestion.value == .other,
           let customMaterial = localizedPhotoSuggestions?.customMaterialName ?? photoAnalysis.suggestions.customMaterialName?.value,
           !customMaterial.isEmpty {
            return customMaterial
        }

        return suggestion.value.displayName
    }
}

private struct PhotoSuggestedTagsRow: View {
    private struct DisplaySuggestion: Identifiable {
        let suggestion: SuggestedFieldValue<String>
        let localizedTag: String
        let opacity: Double

        var id: String { suggestion.value }
    }

    private let minimumVisibleConfidence = 0.02
    private let highConfidenceThreshold = 0.75
    private let mediumConfidenceOpacity = 0.75

    let title: String
    let suggestions: [SuggestedFieldValue<String>]
    let localizedSuggestions: [String]?
    let onAccept: ([String]) -> Void

    @State private var selectedValues: Set<String>

    init(
        title: String,
        suggestions: [SuggestedFieldValue<String>],
        localizedSuggestions: [String]? = nil,
        onAccept: @escaping ([String]) -> Void
    ) {
        self.title = title
        self.suggestions = suggestions
        self.localizedSuggestions = localizedSuggestions
        self.onAccept = onAccept
        _selectedValues = State(initialValue: [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            TagFlowLayout(spacing: CatalogMetrics.Spacing.sm) {
                ForEach(displaySuggestions) { displaySuggestion in
                    let suggestion = displaySuggestion.suggestion

                    PhotoSuggestedTagChip(
                        tag: displaySuggestion.localizedTag,
                        isSelected: selectedValues.contains(suggestion.value),
                        opacity: displaySuggestion.opacity
                    ) {
                        if selectedValues.contains(suggestion.value) {
                            selectedValues.remove(suggestion.value)
                        } else {
                            selectedValues.insert(suggestion.value)
                        }
                    }
                }
            }

            HStack {
                Spacer()

                Button {
                    onAccept(displaySuggestions.filter { selectedValues.contains($0.suggestion.value) }.map(\.localizedTag))
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .disabled(selectedValues.isEmpty)
                .accessibilityLabel(String(localized: "common.apply"))
            }
        }
        .padding(.vertical, CatalogMetrics.Spacing.xs)
    }

    private var displaySuggestions: [DisplaySuggestion] {
        suggestions.enumerated()
            .compactMap { index, suggestion in
                guard suggestion.confidence >= minimumVisibleConfidence else {
                    return nil
                }

                let localizedTag: String
                if let localizedSuggestions,
                   localizedSuggestions.indices.contains(index) {
                    localizedTag = localizedSuggestions[index]
                } else {
                    localizedTag = suggestion.value
                }

                return DisplaySuggestion(
                    suggestion: suggestion,
                    localizedTag: localizedTag,
                    opacity: suggestion.confidence >= highConfidenceThreshold ? 1 : mediumConfidenceOpacity
                )
            }
            .sorted { $0.suggestion.confidence > $1.suggestion.confidence }
    }
}

private struct PhotoSuggestedTagChip: View {
    let tag: String
    let isSelected: Bool
    let opacity: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("#\(tag)")
                .font(CatalogTypography.cardSubtitle)
                .catalogSurfaceCapsule()
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: isSelected ? 1.5 : 0)
            }
            .shadow(color: isSelected ? Color.accentColor.opacity(0.18) : .clear, radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .opacity(opacity)
    }
}

#if DEBUG
#Preview {
    let container = PreviewContainer.makeBellsMinimal()
    let repository = CoreDataCatalogRepository(
        context: container.viewContext,
        persistentContainer: nil
    )
    let snapshot = CatalogSnapshot.load(from: container.viewContext)
    let collection = snapshot.collections.first { $0.kind == .bells }!
    let bell = snapshot.bellRecords.first { $0.item.collectionID == collection.id && $0.mediaAssets.count == 2 }
    let itemCount = snapshot.bellRecords.filter { $0.item.collectionID == collection.id }.count
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

    BellEditorView(
        collection: summary,
        repository: repository,
        catalogSnapshot: snapshot,
        bell: bell
    ) { updatedBell in
        repository.saveBellRecord(updatedBell)
    }
}
#endif