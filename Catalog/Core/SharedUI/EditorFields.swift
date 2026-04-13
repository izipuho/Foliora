import SwiftUI

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

struct PlacePickerField: View {
    let title: String
    let selectedLabel: String
    let places: [Place]
    @Binding var selectedPlaceID: UUID?

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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresentingPicker) {
            PlacePickerView(
                places: places,
                selectedPlaceID: $selectedPlaceID
            )
        }
    }
}

struct LocationPickerField: View {
    let title: String
    let selectedLabel: String
    let locations: [Location]
    @Binding var selectedLocationID: UUID?

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
                    .font(.caption.weight(.semibold))
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
    }
}

struct TagEditorSection: View {
    @Binding var tagInput: String
    @Binding var tags: [String]

    var body: some View {
        HStack(spacing: 10) {
            TextField("Add tag", text: $tagInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit {
                    addTag()
                }

            Button("Add") {
                addTag()
            }
            .disabled(tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        if tags.isEmpty {
            Text("No tags yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(tags, id: \.self) { tag in
                HStack {
                    Text("#\(tag)")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        removeTag(tag)
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

struct PlacePickerView: View {
    let places: [Place]
    @Binding var selectedPlaceID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

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
                        selectedPlaceID = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("Unassigned")
                            Spacer()
                            if selectedPlaceID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }

                Section("Places") {
                    ForEach(filteredPlaces) { place in
                        Button {
                            selectedPlaceID = place.id
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(place.displayName)
                                        .foregroundStyle(.primary)

                                    Text(placeSubtitle(for: place))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if selectedPlaceID == place.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Origin")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search places")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedLocationID = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("Unassigned")
                            Spacer()
                            if selectedLocationID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }

                if !ancestors.isEmpty {
                    Section("Current Path") {
                        Text(ancestors.map(\.name).joined(separator: " / "))
                            .foregroundStyle(.secondary)
                    }
                }

                Section(ancestors.isEmpty ? "Select Location" : "Next Level") {
                    ForEach(currentLocations) { location in
                        HStack(spacing: 12) {
                            Button {
                                selectedLocationID = location.id
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(location.name)
                                    Text(location.kind.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            if hasChildren(location) {
                                Button {
                                    ancestors.append(location)
                                    currentParentID = location.id
                                    selectedLocationID = location.id
                                } label: {
                                    Image(systemName: "chevron.right.circle")
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !ancestors.isEmpty {
                        Button("Back") {
                            ancestors.removeLast()
                            currentParentID = ancestors.last?.id
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func hasChildren(_ location: Location) -> Bool {
        locations.contains { $0.parentLocationID == location.id }
    }
}
