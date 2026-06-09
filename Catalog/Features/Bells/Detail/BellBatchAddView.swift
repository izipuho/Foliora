import SwiftUI
import SwiftData
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

    func names(count: Int) -> [String] {
        guard count > 0 else { return [] }

        let formattedTimestamp = formatter.string(from: timestamp)
        return (1...count).map { index in
            "\(prefix) \(formattedTimestamp) #\(index)"
        }
    }
}

private enum BellBatchMediaLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

struct BellBatchAddView: View {
    let collection: CollectionSummary
    let photoCount: Int
    private let photoItems: [PhotosPickerItem]
    private let imageMediaBuilder = ImageMediaBuilder(store: .shared)

    @Query private var queriedLocations: [LocationEntity]
    @Query private var queriedBells: [BellEntity]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedLocationID: UUID?
    @State private var selectedOriginPlace: Place?
    @State private var selectedAcquiredYearOption = String(localized: "common.none")
    @State private var tagInput = ""
    @State private var tags: [String] = []
    @State private var material: BellMaterial = .unknown
    @State private var customMaterialName = ""
    @State private var mediaLoadState: BellBatchMediaLoadState = .idle
    @State private var mediaPayloads: [ImageMedia] = []
    @State private var mediaLoadErrorMessage: String?

    private let acquiredYearOptions = [String(localized: "common.none")] + Array(1900...Calendar.current.component(.year, from: .now)).reversed().map(String.init)

    init(collection: CollectionSummary, photoCount: Int, photoItems: [PhotosPickerItem] = []) {
        self.collection = collection
        self.photoCount = photoCount
        self.photoItems = photoItems
        let homeID = Optional(collection.homeID)
        let collectionID = Optional(collection.id)
        _queriedLocations = Query(
            filter: #Predicate<LocationEntity> { location in
                location.home?.id == homeID
            },
            sort: [SortDescriptor(\.name)]
        )
        _queriedBells = Query(
            filter: #Predicate<BellEntity> { bell in
                bell.collection?.id == collectionID
            },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        NavigationStack {
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
                    Section {
                        Text(mediaLoadErrorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(createButtonLabel) {}
                        .disabled(mediaLoadState == .loading)
                }
            }
            .navigationTitle(String(localized: "bell_batch_add.title"))
            .navigationBarTitleDisplayMode(.inline)
            .task(id: photoItems.map(\.itemIdentifier)) {
                await loadMediaPayloadsIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
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

    private var availableLocations: [Location] {
        queriedLocations.map { entity in
            Location(
                id: entity.id,
                homeID: entity.home?.id ?? collection.homeID,
                parentLocationID: entity.parent?.id,
                kind: entity.kind,
                name: entity.name,
                notes: entity.notes
            )
        }
    }

    private var availablePlaces: [Place] {
        let places = queriedBells
            .compactMap { bell -> Place? in
                guard let place = bell.originPlace else { return nil }
                return Place(
                    id: place.id,
                    displayName: place.displayName,
                    countryCode: place.countryCode,
                    countryName: place.countryName,
                    regionName: place.regionName,
                    cityName: place.cityName,
                    latitude: place.latitude,
                    longitude: place.longitude
                )
            }

        return Array(Set(places)).sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
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
        Dictionary(
            uniqueKeysWithValues: availableLocations.map { location in
                (location.id, locationPath(for: location))
            }
        )
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

    @MainActor
    private func loadMediaPayloadsIfNeeded() async {
        guard mediaLoadState == .idle, !photoItems.isEmpty else { return }

        mediaLoadState = .loading
        mediaLoadErrorMessage = nil

        do {
            var loadedPayloads: [ImageMedia] = []
            for item in photoItems {
                loadedPayloads.append(try await imageMediaBuilder.build(from: item))
            }

            mediaPayloads = loadedPayloads
            mediaLoadState = .loaded
        } catch {
            mediaPayloads = []
            mediaLoadState = .failed
            mediaLoadErrorMessage = String(localized: "bell.detail.preview.load_error")
        }
    }
}
