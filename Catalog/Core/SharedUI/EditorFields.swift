import SwiftUI
import PhotosUI
import UIKit

private func EL(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

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
                        .accessibilityLabel(EL("common.cancel"))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField(EL("editor.tags.add_placeholder"), text: $tagInput)
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
                .accessibilityLabel(EL("common.add"))
            }

            if tags.isEmpty {
                Text(EL("editor.tags.empty"))
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
        HStack(spacing: 6) {
            Text("#\(tag)")
                .font(.subheadline.weight(.medium))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(EL("common.delete"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
    }
}

private struct TagFlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX > 0, currentX + size.width > maxWidth {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(
            width: proposal.width ?? currentX,
            height: currentY + rowHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct MediaSection: View {
    let itemID: UUID
    @Binding var mediaAssets: [MediaAsset]
    private let mediaStore = LocalMediaFileStore.shared

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isPresentingPhotoPicker = false
    @State private var isPresentingCamera = false
    @State private var isShowingModelPlaceholder = false
    @State private var isPresentingAddMediaOptions = false
    private let gridColumns = [GridItem(.adaptive(minimum: 96, maximum: 128), spacing: 12)]

    var body: some View {
        if mediaAssets.isEmpty {
            ContentUnavailableView(
                EL("editor.media.empty.title"),
                systemImage: "photo.on.rectangle.angled",
                description: Text(EL("editor.media.empty.description"))
            )
        } else {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                ForEach(sortedAssets) { asset in
                    MediaAssetGridTileView(
                        asset: asset,
                        isCover: asset.id == coverPhotoID
                    ) {
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
            Label(EL("editor.media.add"), systemImage: "plus")
        }
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
        .confirmationDialog(EL("editor.media.add"), isPresented: $isPresentingAddMediaOptions, titleVisibility: .visible) {
            Button(EL("editor.media.photo_library")) {
                isPresentingPhotoPicker = true
            }

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(EL("editor.media.camera")) {
                    isPresentingCamera = true
                }
            }

            Button(EL("editor.media.model")) {
                isShowingModelPlaceholder = true
            }

            Button(EL("common.cancel"), role: .cancel) {}
        }
        .alert(EL("editor.media.model.placeholder_title"), isPresented: $isShowingModelPlaceholder) {
            Button(EL("common.ok"), role: .cancel) {}
        } message: {
            Text(EL("editor.media.model.placeholder_message"))
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

                HStack(spacing: 6) {
                    Text(asset.kind.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if isCover {
                        Text(EL("editor.media.cover"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.regularMaterial, in: Capsule())
                    }
                }
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
                            Text(EL("common.unassigned"))
                            Spacer()
                            if selectedPlaceID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }

                Section(EL("editor.origin.places")) {
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
            .navigationTitle(EL("editor.origin.title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: EL("editor.origin.search"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(EL("common.done")) {
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
                            Text(EL("common.unassigned"))
                            Spacer()
                            if selectedLocationID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }

                if !ancestors.isEmpty {
                    Section(EL("editor.location.current_path")) {
                        Text(ancestors.map(\.name).joined(separator: " / "))
                            .foregroundStyle(.secondary)

                        Button {
                            goBackOneLevel()
                        } label: {
                            Label(EL("editor.location.up_one_level"), systemImage: "chevron.left")
                        }
                    }
                }

                Section(ancestors.isEmpty ? EL("editor.location.select") : EL("editor.location.next_level")) {
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

                                Text(EL("editor.location.use_current"))
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
            .navigationTitle(EL("editor.location.title"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                initializeNavigationState()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(EL("common.cancel"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(selectedLocationID == nil)
                    .accessibilityLabel(EL("common.save"))
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
