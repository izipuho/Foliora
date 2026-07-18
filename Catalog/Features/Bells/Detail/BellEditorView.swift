import SwiftUI
import CoreData

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

    private enum FocusedField: Hashable {
        case title
    }

    let collection: CollectionSummary
    let repository: any CatalogRepository
    let startSection: StartSection?
    let initialAnalysisImage: UIImage?
    let onSave: (BellRecord) -> Void

    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: FocusedField?
    @State private var lookupSnapshot = BellLookupSnapshot()
    @State private var title = ""
    @State private var notes = ""
    @State private var condition: ItemCondition = .good
    @State private var acquisitionMethod: AcquisitionMethod = .bought
    @State private var material: BellMaterial = .unknown
    @State private var customMaterialName = ""
    @State private var selectedOriginPlace: Place?
    @State private var selectedLocationID: UUID?
    @State private var tagInput = ""
    @State private var tags: [String] = []
    @State private var mediaAssets: [MediaAsset] = []
    @State private var selectedAcquiredYearOption = String(localized: "common.none")
    @State private var highlightedSection: StartSection?
    @State private var analysisFeedbackEvent: AnalysisFeedbackEvent?
    @State private var analysisFeedbackToken = 0
    @State private var photoAnalysis = BellPhotoAnalysisController()
    @State private var didStartInitialAnalysis = false
    private let existingBellID: UUID?
    private let existingCreatedAt: Date?
    private let editorItemID: UUID

    private let acquiredYearOptions = [String(localized: "common.none")] + Array(1900...Calendar.current.component(.year, from: .now)).reversed().map(String.init)

    private var availableLocations: [Location] {
        lookupSnapshot.locations
    }

    private var availablePlaces: [Place] {
        lookupSnapshot.places
    }

    private var locationPathByID: [UUID: String] {
        lookupSnapshot.locationPathByID
    }

    private var canSave: Bool {
        isTitleValid
    }

    private var isTitleValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldShowPhotoAnalysisSection: Bool {
        photoAnalysis.isAnalyzing
        || photoAnalysis.suggestions.title != nil
        || photoAnalysis.suggestions.notes != nil
        || photoAnalysis.suggestions.material != nil
        || photoAnalysis.suggestions.condition != nil
        || photoAnalysis.suggestions.suggestedYear != nil
        || photoAnalysis.suggestions.suggestedGeo != nil
        || !photoAnalysis.suggestions.suggestedTags.isEmpty
    }

    init(
        collection: CollectionSummary,
        repository: any CatalogRepository,
        bell: BellRecord? = nil,
        initialMediaAssets: [MediaAsset] = [],
        initialAnalysisImage: UIImage? = nil,
        startSection: StartSection? = nil,
        onSave: @escaping (BellRecord) -> Void
    ) {
        self.collection = collection
        self.repository = repository
        self.startSection = startSection
        self.initialAnalysisImage = initialAnalysisImage
        self.onSave = onSave
        self.existingBellID = bell?.id
        self.existingCreatedAt = bell?.createdAt
        self.editorItemID = bell?.id ?? UUID()
        _title = State(initialValue: bell?.title ?? "")
        _notes = State(initialValue: bell?.notes ?? "")
        _condition = State(initialValue: bell?.condition ?? .good)
        _acquisitionMethod = State(initialValue: bell?.acquisitionMethod ?? .bought)
        _material = State(initialValue: bell?.details.material ?? .unknown)
        _customMaterialName = State(initialValue: bell?.details.customMaterialName ?? "")
        _selectedOriginPlace = State(initialValue: bell?.originPlace)
        _selectedLocationID = State(initialValue: bell?.item.locationID)
        _tags = State(initialValue: bell?.tags ?? [])
        _mediaAssets = State(initialValue: bell?.mediaAssets ?? initialMediaAssets)
        _selectedAcquiredYearOption = State(initialValue: bell?.acquiredYear.map(String.init) ?? String(localized: "common.none"))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                Form {
                    Section(String(localized: "editor.media")) {
                        MediaSection(
                            itemID: editorItemID,
                            mediaAssets: $mediaAssets,
                            analysisHighlightedAssetID: photoAnalysis.isAnalyzing ? firstPhotoAssetID : nil
                        )
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
                                if !photoAnalysis.suggestions.recognizedText.isEmpty {
                                    PhotoRecognizedTextBlock(textFeatures: photoAnalysis.suggestions.recognizedText)
                                }

                                if let titleSuggestion = photoAnalysis.suggestions.title {
                                    PhotoSuggestionRow(
                                        title: String(localized: "editor.photo_analysis.title"),
                                        suggestedValue: titleSuggestion.value,
                                        confidence: titleSuggestion.confidence,
                                        onAccept: {
                                            title = titleSuggestion.value
                                            photoAnalysis.dismiss(.title)
                                        }
                                    )
                                }

                                if let notesSuggestion = photoAnalysis.suggestions.notes {
                                    PhotoSuggestionRow(
                                        title: String(localized: "editor.photo_analysis.notes"),
                                        suggestedValue: notesSuggestion.value,
                                        confidence: notesSuggestion.confidence,
                                        onAccept: {
                                            notes = notesSuggestion.value
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
                                            material = materialSuggestion.value
                                            if materialSuggestion.value == .other {
                                                customMaterialName = photoAnalysis.suggestions.customMaterialName?.value ?? ""
                                                photoAnalysis.dismiss(.customMaterialName)
                                            } else {
                                                customMaterialName = ""
                                            }
                                            photoAnalysis.dismiss(.material)
                                        }
                                    )
                                }

                                if let conditionSuggestion = photoAnalysis.suggestions.condition {
                                    PhotoSuggestionRow(
                                        title: String(localized: "editor.photo_analysis.condition"),
                                        suggestedValue: conditionSuggestion.value.displayName,
                                        confidence: conditionSuggestion.confidence,
                                        onAccept: {
                                            condition = conditionSuggestion.value
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
                                            selectedAcquiredYearOption = String(yearSuggestion.value)
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
                                            selectedOriginPlace = place(from: geoSuggestion.value)
                                            photoAnalysis.dismiss(.suggestedGeo)
                                        }
                                    )
                                }

                                if !photoAnalysis.suggestions.suggestedTags.isEmpty {
                                    PhotoSuggestedTagsRow(
                                        title: String(localized: "editor.photo_analysis.tags"),
                                        suggestions: photoAnalysis.suggestions.suggestedTags,
                                        onAccept: { newValues in
                                            for value in newValues where !tags.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
                                                tags.append(value)
                                            }
                                            photoAnalysis.dismiss(.suggestedTags)
                                        }
                                    )
                                }
                            }
                        }
                    }

                    Section(String(localized: "common.field.description")) {
                        TextField(String(localized: "editor.short_description"), text: $title)
                            .focused($focusedField, equals: .title)

                        if !isTitleValid {
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

                        TextField(String(localized: "editor.note_history"), text: $notes, axis: .vertical)
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

                        EnumSelectionRow(
                            title: String(localized: "common.field.material"),
                            selectedLabel: material.displayName,
                            options: BellMaterial.allCases,
                            selection: $material,
                            optionTitle: \.displayName
                        )

                        if material == .other {
                            TextField(String(localized: "editor.material.custom"), text: $customMaterialName)
                        }

                    }

                    Section(String(localized: "bell.detail.section.location")) {
                        PlacePickerField(
                            title: String(localized: "common.ui.origin"),
                            selectedLabel: selectedOriginLabel,
                            places: availablePlaces,
                            selectedPlace: $selectedOriginPlace
                        )

                        LocationPickerField(
                            title: String(localized: "editor.location"),
                            selectedLabel: selectedLocationLabel,
                            locations: availableLocations,
                            selectedLocationID: $selectedLocationID
                        )
                    }

                    Section(String(localized: "common.field.tags")) {
                        TagEditorSection(
                            tagInput: $tagInput,
                            tags: $tags
                        )
                    }
                }
                .navigationTitle(existingBellID == nil ? String(localized: "editor.bell.add") : String(localized: "editor.bell.edit"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(String(localized: "common.cancel"))
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button { requestSave() } label: { Image(systemName: "checkmark") }
                        .opacity(canSave ? 1 : 0.35)
                        .accessibilityLabel(String(localized: "common.save"))
                    }
                }
                .task {
                    reloadLookupSnapshot()
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
                    handlePhotoAnalysisCompletion()
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: managedObjectContext)) { _ in
                    reloadLookupSnapshot()
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

    private func handlePhotoAnalysisCompletion() {
        if photoAnalysis.suggestions.hasSuggestions {
            emitAnalysisFeedback(.success)
        }

        // Keep failures / empty results silent by default.
        // If the analysis flow is re-enabled and warning feedback is needed later,
        // emit `.warning` here in a more selective way.
    }

    private func startInitialPhotoAnalysisIfNeeded() {
        guard !didStartInitialAnalysis, existingBellID == nil, let initialAnalysisImage else { return }
        didStartInitialAnalysis = true
        photoAnalysis.analyze(image: initialAnalysisImage)
    }

    private func reloadLookupSnapshot() {
        lookupSnapshot = CoreDataBellLookupSnapshotLoader(context: managedObjectContext)
            .loadSnapshot(collectionID: collection.id, homeID: collection.homeID)
    }

    private func requestSave() {
        guard canSave else {
            if !isTitleValid {
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
        mediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first?
            .id
    }

    private func saveBell() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustomMaterial = customMaterialName.trimmingCharacters(in: .whitespacesAndNewlines)

        let itemID = editorItemID
        let location = availableLocations.first(where: { $0.id == selectedLocationID })
        let originPlace = selectedOriginPlace
        let normalizedMediaAssets = mediaAssets.enumerated().map { index, asset in
            asset.with(itemID: itemID, sortOrder: index)
        }

        let newBell = BellRecord(
            item: Item(
                id: itemID,
                collectionID: collection.id,
                locationID: selectedLocationID,
                createdAt: existingCreatedAt ?? .now,
                title: trimmedTitle,
                notes: trimmedNotes,
                acquiredYear: selectedAcquiredYearOption == String(localized: "common.none") ? nil : Int(selectedAcquiredYearOption),
                condition: condition,
                acquisitionMethod: acquisitionMethod
            ),
            details: BellDetails(
                itemID: itemID,
                originPlaceID: selectedOriginPlace?.id,
                material: material,
                customMaterialName: material == .other ? trimmedCustomMaterial : nil
            ),
            originPlace: originPlace,
            storageLocation: location,
            storagePath: location.map(locationPath(for:)) ?? String(localized: "common.unassigned"),
            mediaAssets: normalizedMediaAssets,
            createdBy: "You",
            tags: tags
        )

        onSave(newBell)
        dismiss()
    }

    private var selectedOriginLabel: String {
        selectedOriginPlace?.displayName ?? String(localized: "common.unassigned")
    }

    private func place(from geoPoint: GeoPoint) -> Place {
        Place(
            id: UUID(),
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
        guard let selectedLocationID, let path = locationPathByID[selectedLocationID] else {
            return String(localized: "common.unassigned")
        }

        return path
    }

    private func locationPath(for location: Location) -> String {
        let locationsByID = Dictionary(uniqueKeysWithValues: availableLocations.map { ($0.id, $0) })
        var parts = [location.name]
        var currentParentID = location.parentLocationID

        while let parentID = currentParentID, let parent = locationsByID[parentID] {
            parts.insert(parent.name, at: 0)
            currentParentID = parent.parentLocationID
        }

        return parts.joined(separator: " / ")
    }

    private func materialSuggestionLabel(_ suggestion: SuggestedFieldValue<BellMaterial>) -> String {
        if suggestion.value == .other,
           let customMaterial = photoAnalysis.suggestions.customMaterialName?.value,
           !customMaterial.isEmpty {
            return customMaterial
        }

        return suggestion.value.displayName
    }
}


private struct PhotoSuggestionRow: View {
    let title: String
    let suggestedValue: String
    let confidence: Double
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(confidenceLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(suggestedValue)
                .foregroundStyle(.primary)

            HStack {
                Spacer()

                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel(String(localized: "common.apply"))
            }
        }
        .padding(.vertical, CatalogMetrics.Spacing.xs)
    }

    private var confidenceLabel: String {
        "\(Int((confidence * 100).rounded()))%"
    }
}

private struct PhotoRecognizedTextBlock: View {
    let textFeatures: [RecognizedTextFeature]

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
            Text(String(localized: "editor.photo_analysis.detected_text"))
                .font(CatalogTypography.chipLabel)
                .foregroundStyle(.secondary)

            TagFlowLayout(spacing: CatalogMetrics.Spacing.sm) {
                ForEach(textFeatures, id: \.self) { feature in
                    Text(feature.text)
                        .font(.caption.weight(.medium))
                        .catalogSurfaceCapsule()
                }
            }
        }
    }
}

private struct PhotoSuggestedTagsRow: View {
    let title: String
    let suggestions: [SuggestedFieldValue<String>]
    let onAccept: ([String]) -> Void

    @State private var selectedValues: Set<String>

    init(
        title: String,
        suggestions: [SuggestedFieldValue<String>],
        onAccept: @escaping ([String]) -> Void
    ) {
        self.title = title
        self.suggestions = suggestions
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
                ForEach(suggestions, id: \.value) { suggestion in
                    PhotoSuggestedTagChip(
                        tag: suggestion.value,
                        isSelected: selectedValues.contains(suggestion.value)
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
                    onAccept(suggestions.map(\.value).filter(selectedValues.contains))
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
}

private struct PhotoSuggestedTagChip: View {
    let tag: String
    let isSelected: Bool
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
    }
}
