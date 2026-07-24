import SwiftUI
import Observation
@preconcurrency import MapKit

struct YearPickerField: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(option).tag(option)
            }
        }
    }
}

struct EnumSelectionRow<Option: Hashable>: View {
    let title: String
    let selectedLabel: String
    let options: [Option]
    @Binding var selection: Option
    let optionTitle: (Option) -> String

    @State private var isPresentingPicker = false

    var body: some View {
        Button {
            isPresentingPicker = true
        } label: {
            HStack {
                Text(title)
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
            NavigationStack {
                List {
                    ForEach(options, id: \.self) { option in
                        HStack {
                            Text(optionTitle(option))
                                .foregroundStyle(.primary)

                            Spacer()

                            if option == selection {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selection = option
                            isPresentingPicker = false
                        }
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            isPresentingPicker = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(String(localized: "common.cancel"))
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

struct PlacePickerField: View {
    let title: String
    let selectedLabel: String
    let places: [Place]
    @Binding var selectedPlace: Place?

    @State private var isPresentingPicker = false

    var body: some View {
        Button {
            isPresentingPicker = true
        } label: {
            HStack {
                Text(title)
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
            PlacePickerView(
                places: places,
                selectedPlace: $selectedPlace
            )
        }
    }
}

struct LocationPickerField: View {
    let title: String
    let selectedLabel: String
    let locations: [Location]
    let onManageLocations: () -> Void
    let presentationToken: Int
    @Binding var selectedLocationID: UUID?

    @State private var isPresentingPicker = false

    var body: some View {
        Button {
            if locations.isEmpty {
                onManageLocations()
            } else {
                isPresentingPicker = true
            }
        } label: {
            HStack {
                Text(title)
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
            LocationHierarchyPickerView(
                locations: locations,
                selectedLocationID: $selectedLocationID
            )
        }
        .onChange(of: presentationToken) { _, _ in
            guard !locations.isEmpty else { return }
            isPresentingPicker = true
        }
    }
}

struct TagEditorSection: View {
    @Binding var tagInput: String
    @Binding var tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            HStack(spacing: CatalogMetrics.Spacing.sm) {
                TextField(String(localized: "editor.tags.add_placeholder"), text: $tagInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit {
                        addTag()
                    }

                Button {
                    addTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(CatalogTypography.cardTitle)
                }
                .disabled(tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(String(localized: "common.add"))
            }

            if tags.isEmpty {
                Text(String(localized: "editor.tags.empty"))
                    .font(CatalogTypography.cardSubtitle)
                    .foregroundStyle(.secondary)
            } else {
                TagFlowLayout(spacing: CatalogMetrics.Spacing.sm) {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(tag: tag) {
                            removeTag(tag)
                        }
                    }
                }
            }
        }
    }

    private func addTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            tagInput = ""
            return
        }

        tags.append(trimmed)
        tagInput = ""
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}

private struct TagChip: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: CatalogMetrics.Spacing.xxs) {
            Text("#\(tag)")
                .font(CatalogTypography.cardSubtitle)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "common.delete"))
        }
        .catalogSurfaceCapsule()
    }
}

struct PlacePickerView: View {
    let places: [Place]
    @Binding var selectedPlace: Place?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchModel = PlaceSearchModel()

    private var filteredPlaces: [Place] {
        guard !searchText.isEmpty else { return places }

        return places.filter { place in
            let haystack = [
                place.displayName,
                place.countryName,
                place.regionName ?? "",
                place.cityName ?? ""
            ].joined(separator: " ")

            return haystack.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedPlace = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text(String(localized: "common.unassigned"))
                            Spacer()
                            if selectedPlace == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }

                if !searchModel.results.isEmpty {
                    Section(String(localized: "editor.origin.results")) {
                        ForEach(searchModel.results) { result in
                            Button {
                                PlaceSearchModel.resolve(result) { place in
                                    guard let place else { return }
                                    selectedPlace = place
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xxs) {
                                        Text(result.title)
                                            .foregroundStyle(.primary)

                                        if !result.displaySubtitle.isEmpty {
                                            Text(result.displaySubtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    if selectedPlace?.displayName == result.title {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }

                Section(String(localized: "editor.origin.places")) {
                    ForEach(filteredPlaces) { place in
                        Button {
                            selectedPlace = place
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xxs) {
                                    Text(place.displayName)
                                        .foregroundStyle(.primary)

                                    Text(placeSubtitle(for: place))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if selectedPlace?.id == place.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "common.ui.origin"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: String(localized: "editor.origin.search"))
            .onChange(of: searchText) { _, newValue in
                searchModel.updateQuery(newValue)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(String(localized: "common.cancel"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "checkmark") }
                    .accessibilityLabel(String(localized: "common.save"))
                }
            }
        }
    }

    private func placeSubtitle(for place: Place) -> String {
        [
            place.cityName,
            place.regionName,
            place.countryName
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: ", ")
    }
}

private struct PlaceSearchSuggestion: Identifiable, Hashable {
    let title: String
    let subtitle: String
    let displaySubtitle: String
    let completion: MKLocalSearchCompletion

    var id: String { "\(title)|\(subtitle)" }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@Observable
private final class PlaceSearchModel: NSObject, MKLocalSearchCompleterDelegate, @unchecked Sendable {
    var results: [PlaceSearchSuggestion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
    }

    func updateQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Task { @MainActor in
                self.results = []
            }
            completer.queryFragment = ""
            return
        }

        completer.queryFragment = trimmed
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let mappedResults = completer.results.map {
            PlaceSearchSuggestion(
                title: $0.title,
                subtitle: $0.subtitle,
                displaySubtitle: $0.subtitle,
                completion: $0
            )
        }

        Task { @MainActor in
            self.results = mappedResults
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        Task { @MainActor in
            self.results = []
        }
    }

    static func resolve(_ suggestion: PlaceSearchSuggestion, completion: @escaping @MainActor (Place?) -> Void) {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            guard let mapItem = response?.mapItems.first else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            let address = mapItem.address
            let representations = mapItem.addressRepresentations
            let location = mapItem.location

            let city = representations?.cityName
            let countryName = representations?.regionName ?? suggestion.subtitle
            let displaySubtitle = representations?.cityWithContext(.full) ?? suggestion.subtitle
            let displayName: String = {
                let normalizedParts: [String] = [city, countryName].compactMap { value in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }

                if !normalizedParts.isEmpty {
                    return normalizedParts.joined(separator: ", ")
                }

                if let shortAddress = address?.shortAddress, !shortAddress.isEmpty {
                    return shortAddress
                }

                return suggestion.title
            }()

            let place = Place(
                id: UUID(),
                displayName: displayName,
                countryCode: "",
                countryName: countryName,
                regionName: displaySubtitle,
                cityName: city,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )

            DispatchQueue.main.async {
                completion(place)
            }
        }
    }
}

struct LocationHierarchyPickerView: View {
    let locations: [Location]
    @Binding var selectedLocationID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var currentParentID: UUID?
    @State private var ancestors: [Location] = []

    private var currentLocations: [Location] {
        locations
            .filter { $0.parentLocationID == currentParentID }
            .sorted { $0.name < $1.name }
    }

    private var currentNode: Location? {
        ancestors.last
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedLocationID = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text(String(localized: "common.unassigned"))
                            Spacer()
                            if selectedLocationID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }

                if !ancestors.isEmpty {
                    Section(String(localized: "editor.location.current_path")) {
                        Text(ancestors.map(\.name).joined(separator: " / "))
                            .foregroundStyle(.secondary)

                        Button {
                            goBackOneLevel()
                        } label: {
                            Label(String(localized: "editor.location.up_one_level"), systemImage: "chevron.left")
                        }
                    }
                }

                Section(ancestors.isEmpty ? String(localized: "editor.location.select") : String(localized: "editor.location.next_level")) {
                    if let currentNode {
                        Button {
                            selectedLocationID = currentNode.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xxs) {
                                    Text(currentNode.name)
                                    Text(currentNode.kind.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(String(localized: "editor.location.use_current"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if selectedLocationID == currentNode.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(currentLocations) { location in
                        Button {
                            if hasChildren(location) {
                                ancestors.append(location)
                                currentParentID = location.id
                            } else {
                                selectedLocationID = location.id
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: CatalogMetrics.Spacing.md) {
                                VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xxs) {
                                    Text(location.name)
                                        .foregroundStyle(.primary)
                                    Text(location.kind.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if hasChildren(location) {
                                    Image(systemName: "chevron.right")
                                        .font(CatalogTypography.chipLabel)
                                        .foregroundStyle(.tertiary)
                                } else if selectedLocationID == location.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(String(localized: "editor.location.title"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                initializeNavigationState()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(String(localized: "common.cancel"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "checkmark") }
                    .disabled(selectedLocationID == nil)
                    .accessibilityLabel(String(localized: "common.save"))
                }
            }
        }
    }

    private func initializeNavigationState() {
        guard ancestors.isEmpty, currentParentID == nil, let selectedLocationID else { return }
        guard let selectedLocation = locations.first(where: { $0.id == selectedLocationID }) else { return }

        let locationsByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
        var path: [Location] = []
        var parentID = selectedLocation.parentLocationID

        while let currentParentID = parentID, let parent = locationsByID[currentParentID] {
            path.insert(parent, at: 0)
            parentID = parent.parentLocationID
        }

        ancestors = path
        currentParentID = selectedLocation.parentLocationID
    }

    private func goBackOneLevel() {
        guard !ancestors.isEmpty else { return }
        ancestors.removeLast()
        currentParentID = ancestors.last?.id
    }

    private func hasChildren(_ location: Location) -> Bool {
        locations.contains { $0.parentLocationID == location.id }
    }
}
