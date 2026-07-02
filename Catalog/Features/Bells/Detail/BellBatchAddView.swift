import SwiftUI
import CoreData
import PhotosUI

private struct BellBatchNameGenerator {
    private let prefix: String
    private let timestamp: Date
    private let formatter: DateFormatter

    init(timestamp: Date = .now, prefix: String = String(localized: "batch_name_prefix")) {
        self.prefix = prefix
        self.timestamp = timestamp

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        self.formatter = formatter
    }

    var batchPrefix: String {
        "\(prefix) \(formatter.string(from: timestamp))"
    }

    func names(count: Int) -> [String] {
        guard count > 0 else { return [] }

        return (1...count).map { index in
            "\(batchPrefix) #\(index)"
        }
    }
}

#if DEBUG
private extension BellBatchAddView {
    static var completionPreview: some View {
        BellBatchAddView(
            collection: CollectionSummary(
                id: UUID(),
                homeID: UUID(),
                kind: .bells,
                name: "Preview Collection",
                subtitle: "",
                backgroundStyle: .amber,
                itemCount: 0,
                status: .active,
                sharingSummary: ""
            ),
            photoCount: 8
        )
        .completionContent(createdCount: 8, reviewQuery: "Preview Batch")
    }
}

#Preview("Batch Add Completion") {
    NavigationStack {
        BellBatchAddView.completionPreview
            .navigationTitle(String(localized: "bell_batch_add.title"))
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

enum BatchAddCompletionAction {
    case done
    case reviewResults(String)
}

private enum BellBatchMediaLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

private enum BellBatchCreationState: Equatable {
    case editing
    case completed(createdCount: Int, reviewQuery: String)
    case failed
}

struct BellBatchAddView: View {
    let collection: CollectionSummary
    let photoCount: Int
    private let photoItems: [PhotosPickerItem]
    private let initialMediaAssets: [MediaAsset]
    private let repository: (any CatalogRepository)?
    private let onComplete: (BatchAddCompletionAction) -> Void
    private let imageMediaBuilder = ImageMediaBuilder(store: .shared)

    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) private var dismiss
    @State private var lookupSnapshot = BellLookupSnapshot()
    @State private var selectedLocationID: UUID?
    @State private var selectedOriginPlace: Place?
    @State private var selectedAcquiredYearOption = String(localized: "common.none")
    @State private var tagInput = ""
    @State private var tags: [String] = []
    @State private var material: BellMaterial = .unknown
    @State private var customMaterialName = ""
    @State private var mediaLoadState: BellBatchMediaLoadState = .idle
    @State private var mediaPayloads: [MediaAsset] = []
    @State private var mediaLoadErrorMessage: String?
    @State private var creationState: BellBatchCreationState = .editing
    @State private var creationErrorMessage: String?

    private let acquiredYearOptions = [String(localized: "common.none")] + Array(1900...Calendar.current.component(.year, from: .now)).reversed().map(String.init)

    init(
        collection: CollectionSummary,
        photoCount: Int,
        photoItems: [PhotosPickerItem] = [],
        initialMediaAssets: [MediaAsset] = [],
        repository: (any CatalogRepository)? = nil,
        onComplete: @escaping (BatchAddCompletionAction) -> Void = { _ in }
    ) {
        self.collection = collection
        self.photoCount = photoCount
        self.photoItems = photoItems
        self.initialMediaAssets = initialMediaAssets
        self.repository = repository
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            content
            .navigationTitle(String(localized: "bell_batch_add.title"))
            .navigationBarTitleDisplayMode(.inline)
            .task(id: photoItems.map(\.itemIdentifier)) {
                reloadLookupSnapshot()
                await loadMediaPayloadsIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: CatalogMetrics.Spacing.xxs) {
                        Text(String(localized: "bell_batch_add.title"))
                            .font(.headline)
                        Text(selectedCountLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(String(localized: "common.cancel"))
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch creationState {
        case .completed(let createdCount, let reviewQuery):
            completionContent(createdCount: createdCount, reviewQuery: reviewQuery)
        case .editing, .failed:
            editContent
        }
    }

    private var editContent: some View {
        Form {
            Section {
                LocationPickerField(
                    title: String(localized: "editor.location"),
                    selectedLabel: selectedLocationLabel,
                    locations: availableLocations,
                    selectedLocationID: $selectedLocationID
                )

                PlacePickerField(
                    title: String(localized: "common.field.origin"),
                    selectedLabel: selectedOriginLabel,
                    places: availablePlaces,
                    selectedPlace: $selectedOriginPlace
                )

                YearPickerField(
                    title: String(localized: "common.field.acquired_year"),
                    selection: $selectedAcquiredYearOption,
                    options: acquiredYearOptions
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

            Section(String(localized: "common.field.tags")) {
                TagEditorSection(
                    tagInput: $tagInput,
                    tags: $tags
                )
            }

            if let mediaLoadErrorMessage {
                Section(String(localized: "bell_batch_add.error.title")) {
                    Text(mediaLoadErrorMessage)
                        .foregroundStyle(.red)
                }
            }

            if let creationErrorMessage {
                Section(String(localized: "bell_batch_add.error.title")) {
                    Text(creationErrorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(createButtonLabel) {
                    createBatchBells()
                }
                .disabled(!canCreateBatch)
            }
        }
    }

    private func completionContent(createdCount: Int, reviewQuery: String) -> some View {
        CatalogEmptyStateView(
            systemImage: "checkmark.circle",
            title: LocalizedStringKey(String(localized: "bell_batch_add.completion.title")),
            message: LocalizedStringKey(completionMessage(createdCount: createdCount)),
            primaryActionTitle: LocalizedStringKey(String(localized: "common.done")),
            primaryTint: .accentColor,
            primaryAction: {
                onComplete(.done)
            },
            secondaryActionTitle: LocalizedStringKey(String(localized: "bell_batch_add.review_results")),
            secondaryAction: {
                onComplete(.reviewResults(reviewQuery))
            }
        )
    }

    private var localizedBellCount: String {
        String.localizedStringWithFormat(
            String(localized: "collection.count.bells"),
            photoCount
        )
    }

    private var selectedCountLabel: String {
        String.localizedStringWithFormat(
            String(localized: "common.selected_format"),
            localizedBellCount
        )
    }

    private var createButtonLabel: String {
        String.localizedStringWithFormat(
            String(localized: "common.create_format"),
            localizedBellCount
        )
    }

    private func completionMessage(createdCount: Int) -> String {
        String.localizedStringWithFormat(
            String(localized: "bell_batch_add.completion.message"),
            createdCount
        )
    }

    private var canCreateBatch: Bool {
        repository != nil && mediaLoadState == .loaded && !mediaPayloads.isEmpty
    }

    private var selectedAcquiredYear: Int? {
        Int(selectedAcquiredYearOption)
    }

    private var selectedLocation: Location? {
        guard let selectedLocationID else { return nil }
        return availableLocations.first { $0.id == selectedLocationID }
    }

    private var availableLocations: [Location] {
        lookupSnapshot.locations
    }

    private var availablePlaces: [Place] {
        lookupSnapshot.places
    }

    private var selectedLocationLabel: String {
        guard let selectedLocationID else {
            return String(localized: "common.unassigned")
        }

        return locationPathByID[selectedLocationID] ?? String(localized: "common.unassigned")
    }

    private var selectedOriginLabel: String {
        selectedOriginPlace?.displayName ?? String(localized: "common.unassigned")
    }

    private var locationPathByID: [UUID: String] {
        lookupSnapshot.locationPathByID
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

    private func reloadLookupSnapshot() {
        lookupSnapshot = CoreDataBellLookupSnapshotLoader(context: managedObjectContext)
            .loadSnapshot(collectionID: collection.id, homeID: collection.homeID)
    }

    @MainActor
    private func loadMediaPayloadsIfNeeded() async {
        guard mediaLoadState == .idle else { return }

        if !initialMediaAssets.isEmpty {
            mediaPayloads = initialMediaAssets
            mediaLoadState = .loaded
            return
        }

        guard !photoItems.isEmpty else { return }

        mediaLoadState = .loading
        mediaLoadErrorMessage = nil

        do {
            var loadedPayloads: [MediaAsset] = []
            for item in photoItems {
                let media = try await imageMediaBuilder.build(from: item)
                loadedPayloads.append(media.asset)
            }

            mediaPayloads = loadedPayloads
            mediaLoadState = .loaded
        } catch {
            mediaPayloads = []
            mediaLoadState = .failed
            mediaLoadErrorMessage = String(localized: "bell.detail.preview.load_error")
        }
    }

    @MainActor
    private func createBatchBells() {
        guard let repository, !mediaPayloads.isEmpty else {
            creationState = .failed
            creationErrorMessage = String(localized: "bell_batch_add.error.message")
            return
        }

        creationErrorMessage = nil

        let nameGenerator = BellBatchNameGenerator()
        let names = nameGenerator.names(count: mediaPayloads.count)
        let now = Date()
        let bells = mediaPayloads.enumerated().map { index, mediaAsset in
            let bellID = UUID()
            return BellRecord(
                item: Item(
                    id: bellID,
                    collectionID: collection.id,
                    locationID: selectedLocationID,
                    createdAt: now,
                    title: names[index],
                    notes: "",
                    acquiredYear: selectedAcquiredYear,
                    condition: .good,
                    acquisitionMethod: .other
                ),
                details: BellDetails(
                    itemID: bellID,
                    originPlaceID: selectedOriginPlace?.id,
                    material: material,
                    customMaterialName: material == .other ? customMaterialName : nil
                ),
                originPlace: selectedOriginPlace,
                storageLocation: selectedLocation,
                storagePath: selectedLocation.map(locationPath(for:)) ?? "",
                mediaAssets: [mediaAsset.with(itemID: bellID, sortOrder: 0)],
                createdBy: "me",
                tags: tags
            )
        }

        repository.saveBellRecords(bells)
        creationState = .completed(createdCount: bells.count, reviewQuery: nameGenerator.batchPrefix)
    }
}
