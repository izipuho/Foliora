import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

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

struct MediaSection: View {
    let itemID: UUID
    @Binding var mediaAssets: [MediaAsset]
    private let mediaStore = LocalMediaFileStore.shared

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isPresentingPhotoPicker = false
    @State private var isPresentingDocumentImporter = false
    @State private var isShowingModelPlaceholder = false
    @State private var isPresentingAddMediaOptions = false
    private let gridColumns = [GridItem(.adaptive(minimum: 96, maximum: 128), spacing: 12)]

    var body: some View {
        if mediaAssets.isEmpty {
            ContentUnavailableView(
                "No media yet",
                systemImage: "photo.on.rectangle.angled",
                description: Text("Add photos, documents, or 3D models.")
            )
        } else {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                ForEach(sortedAssets) { asset in
                    MediaAssetGridTileView(asset: asset) {
                        mediaStore.deleteFile(for: asset.localIdentifier)
                        mediaAssets.removeAll { $0.id == asset.id }
                        reindexAssets()
                    }
                }
            }
        }

        Button {
            isPresentingAddMediaOptions = true
        } label: {
            Label("Add Media", systemImage: "plus")
        }
        .photosPicker(
            isPresented: $isPresentingPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: nil,
            matching: .images,
            photoLibrary: .shared()
        )
        .fileImporter(
            isPresented: $isPresentingDocumentImporter,
            allowedContentTypes: [.content, .data],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            addDocuments(from: urls)
        }
        .confirmationDialog("Add Media", isPresented: $isPresentingAddMediaOptions, titleVisibility: .visible) {
            Button("Add Photo") {
                isPresentingPhotoPicker = true
            }

            Button("Add Document") {
                isPresentingDocumentImporter = true
            }

            Button("Add 3D Model") {
                isShowingModelPlaceholder = true
            }

            Button("Cancel", role: .cancel) {}
        }
        .alert("3D Models Coming Later", isPresented: $isShowingModelPlaceholder) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("3D model import is still a placeholder. Photos and documents already use real system pickers.")
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task {
                await addPhotos(from: newItems)
            }
        }
    }

    private var sortedAssets: [MediaAsset] {
        mediaAssets.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.localIdentifier < rhs.localIdentifier
            }

            return lhs.sortOrder < rhs.sortOrder
        }
    }

    @MainActor
    private func addPhotos(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension
            guard let identifier = try? mediaStore.savePhoto(data: data, preferredFileExtension: fileExtension) else { continue }

            mediaAssets.append(
                MediaAsset(
                    id: UUID(),
                    itemID: itemID,
                    kind: .photo,
                    localIdentifier: identifier,
                    displayName: nil,
                    sortOrder: mediaAssets.count
                )
            )
        }

        selectedPhotoItems = []
    }

    private func addDocuments(from urls: [URL]) {
        guard !urls.isEmpty else { return }

        for url in urls {
            guard let fileName = try? mediaStore.importDocument(from: url) else { continue }
            mediaAssets.append(
                MediaAsset(
                    id: UUID(),
                    itemID: itemID,
                    kind: .document,
                    localIdentifier: fileName,
                    displayName: url.lastPathComponent,
                    sortOrder: mediaAssets.count
                )
            )
        }
    }

    private func reindexAssets() {
        mediaAssets = mediaAssets
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, asset in
                MediaAsset(
                    id: asset.id,
                    itemID: asset.itemID,
                    kind: asset.kind,
                    localIdentifier: asset.localIdentifier,
                    displayName: asset.displayName,
                    sortOrder: index
                )
            }
    }
}

private struct MediaAssetGridTileView: View {
    let asset: MediaAsset
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                MediaAssetThumbnailView(
                    asset: asset,
                    size: asset.kind == .photo ? 110 : 88
                )

                if asset.kind != .photo {
                    Text(mediaTitle)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                }

                Text(asset.kind.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.35))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
    }

    private var mediaTitle: String {
        if let displayName = asset.displayName, !displayName.isEmpty {
            return displayName
        }

        return URL(fileURLWithPath: asset.localIdentifier)
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

private struct MediaAssetThumbnailView: View {
    let asset: MediaAsset
    let size: CGFloat
    private let mediaStore = LocalMediaFileStore.shared

    var body: some View {
        Group {
            switch asset.kind {
            case .photo:
                if let image = previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder(systemImage: "photo")
                }
            case .document:
                documentPlaceholder
            case .model3D:
                placeholder(systemImage: "cube.transparent")
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var previewImage: UIImage? {
        guard let url = mediaStore.fileURL(for: asset.localIdentifier),
              let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }

        return image
    }

    private var documentPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.05))

            VStack(spacing: 3) {
                Image(systemName: "doc.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(documentExtension)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func placeholder(systemImage: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.05))

            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var documentExtension: String {
        let ext = URL(fileURLWithPath: asset.localIdentifier).pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : ext
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
