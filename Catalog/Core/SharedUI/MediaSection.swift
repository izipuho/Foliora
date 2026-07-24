import SwiftUI
import PhotosUI
import UIKit
import QuickLook

struct MediaSection: View {
    let itemID: UUID
    @Binding var mediaAssets: [MediaAsset]
    var analysisHighlightedAssetID: UUID? = nil
    var allowsAdding = true
    var allowsDeletion = true
    var onPhotoAdded: ((UIImage) -> Void)? = nil
    private let mediaStore = LocalMediaFileStore.shared
    private var imageMediaBuilder: ImageMediaBuilder {
        ImageMediaBuilder(store: mediaStore)
    }

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isPresentingPhotoPicker = false
    @State private var isPresentingCamera = false
    @State private var isShowingModelPlaceholder = false
    @State private var isPresentingAddMediaOptions = false

    var body: some View {
        MediaQuickLookPresenter(mediaAssets: mediaAssets) { preview in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: CatalogMetrics.Spacing.xs) {
                    ForEach(sortedAssets) { asset in
                        MediaAssetGridTileView(
                            asset: asset,
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

                    if allowsAdding {
                        Button {
                            isPresentingAddMediaOptions = true
                        } label: {
                            Image(systemName: "plus")
                                .font(CatalogTypography.cardTitle)
                                .foregroundStyle(CatalogMediaContrast.onMediaPrimary)
                                .frame(width: 38, height: 38)
                                .background(CatalogSemanticColors.success, in: Circle())
                                .frame(width: 48, height: 110)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "editor.media.add"))
                    }
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
        guard allowsAdding else { return }
        guard !items.isEmpty else { return }

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            guard let image = UIImage(data: data) else { continue }
            let contentType = item.supportedContentTypes.first
            guard let media = try? imageMediaBuilder.build(
                from: data,
                image: image,
                preferredFileExtension: contentType?.preferredFilenameExtension,
                mimeType: contentType?.preferredMIMEType
            ) else { continue }

            mediaAssets.append(
                media.asset.with(itemID: itemID, sortOrder: mediaAssets.count)
            )

            onPhotoAdded?(image)
        }

        selectedPhotoItems = []
    }

    private func addCapturedPhoto(_ image: UIImage) {
        guard allowsAdding else { return }
        guard let data = image.jpegData(compressionQuality: 0.92) else { return }
        guard let media = try? imageMediaBuilder.build(
            from: data,
            image: image,
            preferredFileExtension: "jpg",
            mimeType: "image/jpeg"
        ) else { return }

        mediaAssets.append(
            media.asset.with(itemID: itemID, sortOrder: mediaAssets.count)
        )

        onPhotoAdded?(image)
    }

    private func reindexAssets() {
        mediaAssets = mediaAssets
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, asset in
                asset.with(sortOrder: index)
            }
    }
}

struct MediaQuickLookPresenter<Content: View>: View {
    let mediaAssets: [MediaAsset]
    private let mediaStore = LocalMediaFileStore.shared
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
                    return lhs.localIdentifier < rhs.localIdentifier
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
            guard let url = mediaStore.fileURL(for: selectedAsset.localIdentifier) else { return }
            documentPreviewTarget = MediaPreviewTarget(url: url)
        case .model3D:
            return
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
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
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
            .contentShape(CatalogShapes.thumbnail)
            .onTapGesture(perform: onTap)
            .overlay {
                if isAnalysisHighlighted {
                    CatalogShapes.thumbnail
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
                        .font(CatalogTypography.cardTitle)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(CatalogMediaContrast.onMediaPrimary, CatalogMediaContrast.scrimStrong)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
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
    private let mediaStore = LocalMediaFileStore.shared

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

        let localIdentifier = asset.localIdentifier
        let originalData = asset.originalData
        let localURL = mediaStore.fileURL(for: localIdentifier)

        let loadTask = Task<Data?, Never>.detached(priority: .userInitiated) {
            if let localURL,
               let data = try? Data(contentsOf: localURL) {
                return data
            }

            if let originalData {
                return originalData
            }

            return nil
        }
        let loadedData = await loadTask.value

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
            if let image = previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                switch asset.kind {
                case .photo:
                    placeholder(systemImage: "photo")
                case .document:
                    documentPlaceholder
                case .model3D:
                    placeholder(systemImage: "cube.transparent")
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(CatalogShapes.thumbnail)
    }

    private var previewImage: UIImage? {
        if let thumbnailData = asset.thumbnailData,
           let image = UIImage(data: thumbnailData) {
            return image
        }

        if let url = mediaStore.thumbnailFileURL(for: asset.localIdentifier) ?? mediaStore.fileURL(for: asset.localIdentifier),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }

        if let originalData = asset.originalData,
           let image = UIImage(data: originalData) {
            return image
        }

        return nil
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
        let ext = URL(fileURLWithPath: asset.localIdentifier).pathExtension.uppercased()
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
