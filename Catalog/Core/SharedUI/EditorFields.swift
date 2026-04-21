import SwiftUI
import PhotosUI
import UIKit
import Observation
import QuickLook
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
                    .font(.caption.weight(.semibold))
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
                    .font(.caption.weight(.semibold))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
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
                        .font(.title3)
                }
                .disabled(tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(String(localized: "common.add"))
            }

            if tags.isEmpty {
                Text(String(localized: "editor.tags.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                TagFlowLayout(spacing: 8) {
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
        HStack(spacing: CatalogSpacing.compact) {
            Text("#\(tag)")
                .font(.subheadline.weight(.medium))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "common.delete"))
        }
        .catalogPillPadding(.regular)
        .background(.thinMaterial, in: Capsule())
    }
}

struct MediaSection: View {
    let itemID: UUID
    @Binding var mediaAssets: [MediaAsset]
    var analysisHighlightedAssetID: UUID? = nil
    var allowsDeletion = true
    var onPhotoAdded: ((UIImage) -> Void)? = nil
    private let mediaStore = LocalMediaFileStore.shared

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isPresentingPhotoPicker = false
    @State private var isPresentingCamera = false
    @State private var isShowingModelPlaceholder = false
    @State private var isPresentingAddMediaOptions = false
    @State private var previewTarget: MediaPreviewTarget?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: CatalogSpacing.compact) {
                ForEach(sortedAssets) { asset in
                    MediaAssetGridTileView(
                        asset: asset,
                        isCover: asset.id == coverPhotoID,
                        isAnalysisHighlighted: asset.id == analysisHighlightedAssetID,
                        allowsDeletion: allowsDeletion,
                        onTap: {
                            preview(asset)
                        },
                        onDelete: {
                            mediaStore.deleteFile(for: asset.localIdentifier)
                            mediaAssets.removeAll { $0.id == asset.id }
                            reindexAssets()
                        }
                    )
                }

                Button {
                    isPresentingAddMediaOptions = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.green, in: Circle())
                        .frame(width: 48, height: 110)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "editor.media.add"))
            }
        }
        .scrollIndicators(.hidden)
        .photosPicker(
            isPresented: $isPresentingPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: nil,
            matching: .images,
            photoLibrary: .shared()
        )
        .fullScreenCover(isPresented: $isPresentingCamera) {
            CameraPickerView { image in
                addCapturedPhoto(image)
            }
        }
        .confirmationDialog(String(localized: "editor.media.add"), isPresented: $isPresentingAddMediaOptions, titleVisibility: .visible) {
            Button(String(localized: "editor.media.photo_library")) {
                isPresentingPhotoPicker = true
            }

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(String(localized: "editor.media.camera")) {
                    isPresentingCamera = true
                }
            }

            Button(String(localized: "editor.media.model")) {
                isShowingModelPlaceholder = true
            }

            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .alert(String(localized: "editor.media.model.placeholder_title"), isPresented: $isShowingModelPlaceholder) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(String(localized: "editor.media.model.placeholder_message"))
        }
        .sheet(item: $previewTarget) { target in
            QuickLookPreview(url: target.url)
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task {
                await addPhotos(from: newItems)
            }
        }
    }

    private func preview(_ asset: MediaAsset) {
        guard asset.kind == .photo || asset.kind == .document else { return }
        guard let url = mediaStore.fileURL(for: asset.localIdentifier) else { return }
        previewTarget = MediaPreviewTarget(url: url)
    }

    private var sortedAssets: [MediaAsset] {
        mediaAssets.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.localIdentifier < rhs.localIdentifier
            }

            return lhs.sortOrder < rhs.sortOrder
        }
    }

    private var coverPhotoID: UUID? {
        let photoAssets = sortedAssets.filter { $0.kind == .photo }
        guard photoAssets.count > 1 else { return nil }
        return photoAssets.first?.id
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

            if let image = UIImage(data: data) {
                onPhotoAdded?(image)
            }
        }

        selectedPhotoItems = []
    }

    private func addCapturedPhoto(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return }
        guard let identifier = try? mediaStore.savePhoto(data: data, preferredFileExtension: "jpg") else { return }

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

        onPhotoAdded?(image)
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
    let isCover: Bool
    let isAnalysisHighlighted: Bool
    let allowsDeletion: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var highlightPulse = false

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
            }
            .frame(width: 110, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: CatalogCornerRadii.thumbnail, style: .continuous))
            .onTapGesture(perform: onTap)
            .overlay {
                if isAnalysisHighlighted {
                    RoundedRectangle(cornerRadius: CatalogCornerRadii.thumbnail, style: .continuous)
                        .stroke(
                            AngularGradient(
                                colors: [
                                    .cyan,
                                    .blue,
                                    .purple,
                                    .pink,
                                    .cyan
                                ],
                                center: .center
                            ),
                            lineWidth: highlightPulse ? 4 : 2
                        )
                        .opacity(highlightPulse ? 1 : 0.45)
                        .scaleEffect(highlightPulse ? 1.035 : 0.99)
                        .animation(
                            .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                            value: highlightPulse
                        )
                }
            }
            .overlay {
                if isCover {
                    RoundedRectangle(cornerRadius: CatalogCornerRadii.thumbnail, style: .continuous)
                        .stroke(.tint.opacity(0.75), lineWidth: 3)
                }
            }
            .onAppear {
                guard isAnalysisHighlighted else { return }
                highlightPulse = true
            }
            .onChange(of: isAnalysisHighlighted) { _, isHighlighted in
                highlightPulse = isHighlighted
            }

            if allowsDeletion {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, CatalogMediaContrast.iconPaletteShadowStrong)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }

            if isCover {
                Image(systemName: "star.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.tint, in: Circle())
                    .padding(5)
                    .frame(width: 110, height: 110, alignment: .bottomLeading)
            }
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

private struct MediaPreviewTarget: Identifiable {
    let id = UUID()
    let url: URL
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
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
        .clipShape(RoundedRectangle(cornerRadius: CatalogCornerRadii.thumbnail, style: .continuous))
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
            RoundedRectangle(cornerRadius: CatalogCornerRadii.thumbnail, style: .continuous)
                .fill(CatalogSemanticColors.groupedSurfaceElevated)

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
            RoundedRectangle(cornerRadius: CatalogCornerRadii.thumbnail, style: .continuous)
                .fill(CatalogSemanticColors.groupedSurfaceElevated)

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
                                    VStack(alignment: .leading, spacing: 3) {
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
                                VStack(alignment: .leading, spacing: 3) {
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
            .navigationTitle(String(localized: "editor.origin.title"))
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
                                VStack(alignment: .leading, spacing: 2) {
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
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(location.name)
                                        .foregroundStyle(.primary)
                                    Text(location.kind.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if hasChildren(location) {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
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

private struct CameraPickerView: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        controller.allowsEditing = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImagePicked: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImagePicked: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImagePicked = onImagePicked
            self.dismiss = dismiss
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
            dismiss()
        }
    }
}
