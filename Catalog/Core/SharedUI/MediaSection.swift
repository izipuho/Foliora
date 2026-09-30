import SwiftUI
import PhotosUI
import UIKit
import QuickLook

/// Displays the media section interface.
struct MediaSection: View {
    let itemID: UUID
    @Binding var mediaAssets: [MediaAsset]
    var leadingMediaAsset: MediaAsset? = nil
    var maxMediaCount: Int? = nil
    var analysisHighlightedAssetID: UUID? = nil
    var allowsAdding = true
    var allowsDeletion = true
    var onLeadingMediaAssetDelete: (() -> Void)? = nil
    var onPhotoAdded: ((UIImage) -> Void)? = nil
    private let imageMediaBuilder = ImageMediaBuilder()

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isPresentingPhotoPicker = false
    @State private var isPresentingCamera = false
    @State private var isShowingModelPlaceholder = false
    @State private var isPresentingAddMediaOptions = false
    @State private var isPresentingArrangeSheet = false
    @State private var pendingDeletionAssetID: MediaAsset.ID?
    @State private var recentlyAddedPhotoAssetIDs: Set<MediaAsset.ID> = []

    var body: some View {
        MediaQuickLookPresenter(mediaAssets: previewAssets) { preview in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: CatalogMetrics.Spacing.xs) {
                    if let leadingMediaAsset {
                        MediaAssetGridTileView(
                            asset: leadingMediaAsset,
                            isAnalysisHighlighted: isAnalysisHighlighted(leadingMediaAsset),
                            allowsDeletion: allowsDeletion,
                            onTap: {
                                preview(leadingMediaAsset)
                            },
                            onDelete: {
                                pendingDeletionAssetID = leadingMediaAsset.id
                            }
                        )
                        .confirmationDialog(
                            "editor.media.delete_action",
                            isPresented: deleteConfirmationBinding(for: leadingMediaAsset.id),
                            titleVisibility: .visible
                        ) {
                            Button("editor.media.delete_title", role: .destructive) {
                                confirmDeletion(of: leadingMediaAsset.id)
                            }
                            Button("common.cancel", role: .cancel) {}
                        }
                    }

                    ForEach(sortedAssets) { asset in
                        MediaAssetGridTileView(
                            asset: asset,
                            isAnalysisHighlighted: isAnalysisHighlighted(asset),
                            allowsDeletion: allowsDeletion,
                            onTap: {
                                preview(asset)
                            },
                            onDelete: {
                                pendingDeletionAssetID = asset.id
                            }
                        )
                        .confirmationDialog("editor.media.delete_action", isPresented: deleteConfirmationBinding(for: asset.id), titleVisibility: .visible) {
                            Button("editor.media.delete_title", role: .destructive) {
                                confirmDeletion(of: asset.id)
                            }

                            Button(String(localized: "common.cancel"), role: .cancel) {
                                pendingDeletionAssetID = nil
                            }
                        }
                    }

                    if canAddMedia || canArrangeMedia {
                        VStack(spacing: CatalogMetrics.Spacing.sm) {
                            if canAddMedia {
                                Button {
                                    isPresentingAddMediaOptions = true
                                } label: {
                                    Image(systemName: "plus")
                                        .font(CatalogTypography.cardTitle)
                                        .foregroundStyle(CatalogMediaContrast.onMediaPrimary)
                                        .frame(width: 38, height: 38)
                                        .glassEffect(.regular.tint(CatalogSemanticColors.success).interactive(), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String(localized: "editor.media.add"))
                            }

                            if canArrangeMedia {
                                Button {
                                    isPresentingArrangeSheet = true
                                } label: {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .font(CatalogTypography.cardTitle)
                                        .frame(width: 38, height: 38)
                                        .glassEffect(.regular.interactive(), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String(localized: "editor.media.arrange"))
                            }
                        }
                        .frame(width: 48, height: 110)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .sheet(isPresented: $isPresentingArrangeSheet) {
                MediaArrangeSheet(
                    assets: sortedAssets,
                    marksFirstPhotoAsCover: leadingMediaAsset == nil
                ) { arrangedAssets in
                    applyArrangement(arrangedAssets)
                }
            }
            .photosPicker(
                isPresented: $isPresentingPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: photoPickerSelectionLimit,
                matching: .images,
                photoLibrary: .shared()
            )
            .fullScreenCover(isPresented: $isPresentingCamera) {
                CameraPickerView { image in
                    Task {
                        await addCapturedPhoto(image)
                    }
                }
                .ignoresSafeArea()
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

                #if DEBUG
                Button(String(localized: "editor.media.add_model3d")) {
                    isShowingModelPlaceholder = true
                }
                #endif

                Button(String(localized: "common.cancel"), role: .cancel) {}
            }
            .alert(String(localized: "editor.media.model.placeholder_title"), isPresented: $isShowingModelPlaceholder) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "editor.media.model.placeholder_message"))
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                Task {
                    await addPhotos(from: newItems)
                }
            }
            .onChange(of: analysisHighlightedAssetID) { _, highlightedAssetID in
                if highlightedAssetID == nil {
                    recentlyAddedPhotoAssetIDs.removeAll()
                }
            }
        }
    }

    private var previewAssets: [MediaAsset] {
        [leadingMediaAsset].compactMap { $0 } + mediaAssets
    }

    private var sortedAssets: [MediaAsset] {
        mediaAssets.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.sortOrder < rhs.sortOrder
        }
    }

    private var canAddMedia: Bool {
        guard allowsAdding else { return false }
        guard let maxMediaCount else { return true }
        return mediaAssets.count < maxMediaCount
    }

    private var photoPickerSelectionLimit: Int? {
        guard let maxMediaCount else { return nil }
        return max(maxMediaCount - mediaAssets.count, 1)
    }

    private var isEditing: Bool {
        allowsDeletion
    }

    private func isAnalysisHighlighted(_ asset: MediaAsset) -> Bool {
        guard analysisHighlightedAssetID != nil, asset.kind == .photo else { return false }
        guard !recentlyAddedPhotoAssetIDs.isEmpty else { return true }
        return recentlyAddedPhotoAssetIDs.contains(asset.id)
    }

    private func deleteConfirmationBinding(for assetID: MediaAsset.ID) -> Binding<Bool> {
        Binding(
            get: { pendingDeletionAssetID == assetID },
            set: { isPresented in
                if !isPresented {
                    pendingDeletionAssetID = nil
                }
            }
        )
    }

    @MainActor
    private func addPhotos(from items: [PhotosPickerItem]) async {
        guard canAddMedia else { return }
        guard !items.isEmpty else { return }

        for item in items {
            guard canAddMedia else { break }
            guard let media = try? await imageMediaBuilder.build(from: item) else { continue }
            guard canAddMedia else { break }
            appendPhoto(media)
        }

        selectedPhotoItems = []
    }

    @MainActor
    private func addCapturedPhoto(_ image: UIImage) async {
        guard canAddMedia else { return }
        guard let media = try? await imageMediaBuilder.build(from: image) else { return }
        guard canAddMedia else { return }
        appendPhoto(media)
    }

    private func appendPhoto(_ media: ImageMedia) {
        let asset = media.asset.with(itemID: itemID, sortOrder: mediaAssets.count)
        updateMediaAssets { assets in
            assets.append(asset)
        }
        recentlyAddedPhotoAssetIDs.insert(asset.id)

        onPhotoAdded?(media.uiImage)
    }

    private func removeAsset(withID assetID: MediaAsset.ID) {
        updateMediaAssets { assets in
            assets.removeAll { $0.id == assetID }
            assets = assets.sorted { $0.sortOrder < $1.sortOrder }
            normalizeSortOrder(in: &assets)
        }
    }

    private func confirmDeletion(of assetID: MediaAsset.ID) {
        defer { pendingDeletionAssetID = nil }

        if let leadingMediaAsset, leadingMediaAsset.id == assetID {
            onLeadingMediaAssetDelete?()
            return
        }

        guard mediaAssets.contains(where: { $0.id == assetID }) else { return }
        removeAsset(withID: assetID)
    }

    /// Reordering is offered while editing, once there is more than one media item.
    private var canArrangeMedia: Bool {
        isEditing && mediaAssets.count > 1
    }

    private func applyArrangement(_ arrangedAssets: [MediaAsset]) {
        var reorderedAssets = arrangedAssets
        normalizeSortOrder(in: &reorderedAssets)

        updateMediaAssets { assets in
            assets = reorderedAssets
        }
    }

    private func updateMediaAssets(_ update: (inout [MediaAsset]) -> Void) {
        var updatedAssets = mediaAssets
        update(&updatedAssets)
        mediaAssets = updatedAssets
    }

    private func normalizeSortOrder(in assets: inout [MediaAsset]) {
        assets = assets
            .enumerated()
            .map { index, asset in
                asset.with(sortOrder: index)
            }
    }
}

/// Displays the media quick look presenter interface.
struct MediaQuickLookPresenter<Content: View>: View {
    let mediaAssets: [MediaAsset]
    private let content: (@escaping (MediaAsset) -> Void) -> Content
    @State private var documentPreviewTarget: MediaPreviewTarget?
    @State private var photoGalleryTarget: MediaPhotoGalleryTarget?

    init(
        mediaAssets: [MediaAsset],
        @ViewBuilder content: @escaping (@escaping (MediaAsset) -> Void) -> Content
    ) {
        self.mediaAssets = mediaAssets
        self.content = content
    }

    var body: some View {
        content(preview)
            .sheet(item: $documentPreviewTarget) { target in
                QuickLookPreview(url: target.url)
            }
            .sheet(item: $photoGalleryTarget) { target in
                MediaPhotoGallery(
                    assets: target.assets,
                    initialAssetID: target.initialAssetID
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.black)
            }
    }

    private var sortedPhotoAssets: [MediaAsset] {
        mediaAssets
            .filter { $0.kind == .photo }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.id.uuidString < rhs.id.uuidString
                }

                return lhs.sortOrder < rhs.sortOrder
            }
    }

    private func preview(_ asset: MediaAsset) {
        guard let selectedAsset = mediaAssets.first(where: { $0.id == asset.id }) else { return }

        switch selectedAsset.kind {
        case .photo:
            let photoAssets = sortedPhotoAssets
            guard photoAssets.contains(where: { $0.id == selectedAsset.id }) else { return }
            photoGalleryTarget = MediaPhotoGalleryTarget(
                assets: photoAssets,
                initialAssetID: selectedAsset.id
            )
        case .document:
            guard let url = Self.materializePreviewFile(for: selectedAsset) else { return }
            documentPreviewTarget = MediaPreviewTarget(url: url)
        case .model3D:
            return
        }
    }

    private static func materializePreviewFile(for asset: MediaAsset) -> URL? {
        guard let originalData = asset.originalData else { return nil }

        let fileExtension = asset.fileName
            .map { URL(fileURLWithPath: $0).pathExtension }
            .flatMap { $0.isEmpty ? nil : $0 }
        let previewFileName = fileExtension
            .map { "\(asset.id.uuidString).\($0)" } ?? asset.id.uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogQuickLook", isDirectory: true)
        let url = directory.appendingPathComponent(previewFileName)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try originalData.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

private struct MediaAssetGridTileView: View {
    let asset: MediaAsset
    let isAnalysisHighlighted: Bool
    let allowsDeletion: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var highlightPulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
            thumbnail

            if asset.kind != .photo || asset.displayName?.isEmpty == false {
                Text(mediaTitle)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: 110, alignment: .leading)
        .contentShape(CatalogShapes.thumbnail)
        .onTapGesture(perform: onTap)
        .onAppear {
            updateAnalysisHighlight(isAnalysisHighlighted)
        }
        .onChange(of: isAnalysisHighlighted) { _, isHighlighted in
            updateAnalysisHighlight(isHighlighted)
        }
    }

    private var mediaTitle: String {
        if let displayName = asset.displayName, !displayName.isEmpty {
            return displayName
        }

        if let fileName = asset.fileName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fileName.isEmpty {
            return URL(fileURLWithPath: fileName)
                .deletingPathExtension()
                .lastPathComponent
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }

        return asset.kind.rawValue.capitalized
    }

    private var thumbnailSize: CGFloat {
        asset.kind == .photo ? 110 : 88
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack(alignment: .topTrailing) {
            thumbnailImage

            if allowsDeletion {
                deleteButton
            }
        }
        .padding(.top, allowsDeletion ? 6 : 0)
        .padding(.trailing, allowsDeletion ? 6 : 0)
        .contentShape(CatalogShapes.thumbnail)
    }

    private var thumbnailImage: some View {
        MediaAssetThumbnailView(asset: asset, size: thumbnailSize)
            .overlay {
                analysisHighlight
            }
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .font(CatalogTypography.cardTitle)
                .symbolRenderingMode(.palette)
                .foregroundStyle(CatalogMediaContrast.onMediaPrimary, CatalogMediaContrast.scrimStrong)
        }
        .buttonStyle(.plain)
        .offset(x: 6, y: -6)
    }

    private var analysisHighlight: some View {
        CatalogShapes.thumbnail
            .strokeBorder(
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
                lineWidth: 3
            )
            .opacity(isAnalysisHighlighted ? (highlightPulse ? 1 : 0.45) : 0)
    }

    private func updateAnalysisHighlight(_ isHighlighted: Bool) {
        guard isHighlighted else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                highlightPulse = false
            }
            return
        }

        highlightPulse = false
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            highlightPulse = true
        }
    }
}

/// Reorders media in a native list with system drag handles.
///
/// A horizontal row inside a `Form` row cannot host drag and drop: the `Form` takes over the
/// drag and lifts the whole row. A plain `List` in edit mode is the system reorder surface.
private struct MediaArrangeSheet: View {
    let marksFirstPhotoAsCover: Bool
    let onDone: ([MediaAsset]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var assets: [MediaAsset]

    init(
        assets: [MediaAsset],
        marksFirstPhotoAsCover: Bool,
        onDone: @escaping ([MediaAsset]) -> Void
    ) {
        self.marksFirstPhotoAsCover = marksFirstPhotoAsCover
        self.onDone = onDone
        _assets = State(initialValue: assets)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(assets) { asset in
                    HStack(spacing: CatalogMetrics.Spacing.md) {
                        MediaAssetThumbnailView(asset: asset, size: 88)

                        VStack(alignment: .leading, spacing: 2) {
                            if let title = title(for: asset) {
                                Text(title)
                                    .lineLimit(1)
                            }

                            if isCover(asset) {
                                Text(String(localized: "editor.media.cover"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                .onMove { source, destination in
                    assets.move(fromOffsets: source, toOffset: destination)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(String(localized: "editor.media.arrange"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        onDone(assets)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Names a row only when the name tells something: the media's own name, or its kind
    /// once the list mixes kinds. Photos alone need no label; the thumbnail identifies them.
    private func title(for asset: MediaAsset) -> String? {
        if let displayName = asset.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return displayName
        }

        return hasMixedKinds ? asset.kind.displayName : nil
    }

    private var hasMixedKinds: Bool {
        Set(assets.map(\.kind)).count > 1
    }

    /// The first photo becomes the cover, unless the screen shows a dedicated cover.
    private func isCover(_ asset: MediaAsset) -> Bool {
        marksFirstPhotoAsCover && asset.id == assets.first(where: { $0.kind == .photo })?.id
    }
}

private struct MediaPreviewTarget: Identifiable {
    let id = UUID()
    let url: URL
}

private struct MediaPhotoGalleryTarget: Identifiable {
    let id = UUID()
    let assets: [MediaAsset]
    let initialAssetID: MediaAsset.ID
}

private struct MediaPhotoGallery: View {
    let assets: [MediaAsset]
    let initialAssetID: MediaAsset.ID

    @Environment(\.dismiss) private var dismiss
    @State private var selectedAssetID: MediaAsset.ID

    init(assets: [MediaAsset], initialAssetID: MediaAsset.ID) {
        self.assets = assets
        self.initialAssetID = initialAssetID
        _selectedAssetID = State(initialValue: initialAssetID)
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            TabView(selection: $selectedAssetID) {
                ForEach(assets) { asset in
                    MediaPhotoGalleryPage(asset: asset)
                        .tag(asset.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .safeAreaInset(edge: .top) {
            ZStack {
                if assets.count > 1 {
                    Text(counterText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: Capsule())
                }

                HStack {
                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("common.close")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .onAppear {
            guard assets.contains(where: { $0.id == selectedAssetID }) else { return }
            selectedAssetID = initialAssetID
        }
    }

    private var counterText: String {
        let index = assets.firstIndex { $0.id == selectedAssetID } ?? 0
        return "\(index + 1) / \(assets.count)"
    }
}

private struct MediaPhotoGalleryPage: View {
    let asset: MediaAsset
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var didFail = false

    var body: some View {
        ZStack {
            Color.black

            if let image {
                ZoomableMediaImage(image: image)
            } else if isLoading {
                ProgressView()
                    .tint(.white)
            } else if didFail {
                Image(systemName: "photo")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .task(id: asset.id) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        image = nil
        didFail = false
        isLoading = true

        let loadedData = asset.originalData

        guard !Task.isCancelled else { return }
        let loadedImage = loadedData.flatMap(UIImage.init(data:))
        image = loadedImage
        didFail = loadedImage == nil
        isLoading = false
    }
}

private struct ZoomableMediaImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = ZoomableImageScrollView()
        scrollView.onLayout = { [weak coordinator = context.coordinator, weak scrollView] in
            guard let scrollView else { return }
            coordinator?.updateImageFrame(in: scrollView, resettingZoom: false)
        }
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = context.coordinator.imageView
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.image = image
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView.image = image
        context.coordinator.updateImageFrame(in: scrollView, resettingZoom: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        private var laidOutSize: CGSize = .zero

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
            updatePanState(in: scrollView)
        }

        func updateImageFrame(in scrollView: UIScrollView, resettingZoom: Bool) {
            guard scrollView.bounds.size != .zero else { return }
            guard resettingZoom || laidOutSize != scrollView.bounds.size else { return }
            laidOutSize = scrollView.bounds.size

            if resettingZoom {
                scrollView.zoomScale = 1
            } else if scrollView.zoomScale > scrollView.minimumZoomScale {
                return
            }

            imageView.frame = CGRect(origin: .zero, size: scrollView.bounds.size)
            scrollView.contentSize = imageView.bounds.size
            centerImage(in: scrollView)
            updatePanState(in: scrollView)
        }

        @objc
        func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let zoomScale = min(2.5, scrollView.maximumZoomScale)
                let width = scrollView.bounds.width / zoomScale
                let height = scrollView.bounds.height / zoomScale
                let rect = CGRect(
                    x: point.x - width / 2,
                    y: point.y - height / 2,
                    width: width,
                    height: height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }

        private func centerImage(in scrollView: UIScrollView) {
            let horizontalInset = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
            let verticalInset = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
            scrollView.contentInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
        }

        private func updatePanState(in scrollView: UIScrollView) {
            scrollView.panGestureRecognizer.isEnabled = scrollView.zoomScale > scrollView.minimumZoomScale
        }
    }

    final class ZoomableImageScrollView: UIScrollView {
        var onLayout: (() -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
    }
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

    static func dismantleUIViewController(_ uiViewController: QLPreviewController, coordinator: Coordinator) {
        try? FileManager.default.removeItem(at: coordinator.url)
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

    var body: some View {
        Group {
            switch asset.kind {
            case .photo:
                MediaPreviewImage(
                    assetID: asset.id,
                    originalData: asset.originalData,
                    size: CGSize(width: size, height: size)
                )

            case .document:
                if let image = previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    documentPlaceholder
                }

            case .model3D:
                if let image = previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder(systemImage: "cube.transparent")
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(CatalogShapes.thumbnail)
    }

    private var previewImage: UIImage? {
        guard let originalData = asset.originalData else { return nil }
        return UIImage(data: originalData)
    }

    private var documentPlaceholder: some View {
        ZStack {
            placeholderBackground

            VStack(spacing: CatalogMetrics.Spacing.xxs) {
                Image(systemName: "doc.fill")
                    .font(CatalogTypography.cardTitle)
                    .foregroundStyle(.secondary)
                Text(documentExtension)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func placeholder(systemImage: String) -> some View {
        ZStack {
            placeholderBackground

            Image(systemName: systemImage)
                .font(CatalogTypography.cardTitle)
                .foregroundStyle(.secondary)
        }
    }

    private var placeholderBackground: some View {
        CatalogShapes.thumbnail
            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
    }

    private var documentExtension: String {
        let ext = asset.fileName.map { URL(fileURLWithPath: $0).pathExtension.uppercased() } ?? ""
        return ext.isEmpty ? "FILE" : ext
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
