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

    private var coverPhotoID: UUID? {
        let photoAssets = sortedAssets.filter { $0.kind == .photo }
        guard photoAssets.count > 1 else { return nil }
        return photoAssets.first?.id
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
    @State private var previewTarget: MediaPreviewTarget?

    init(
        mediaAssets: [MediaAsset],
        @ViewBuilder content: @escaping (@escaping (MediaAsset) -> Void) -> Content
    ) {
        self.mediaAssets = mediaAssets
        self.content = content
    }

    var body: some View {
        content(preview)
            .sheet(item: $previewTarget) { target in
                QuickLookPreview(url: target.url)
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
        guard asset.kind == .photo || asset.kind == .document else { return }
        guard let selectedAsset = mediaAssets.first(where: { $0.id == asset.id }) else { return }
        _ = sortedPhotoAssets
        guard let url = mediaStore.fileURL(for: selectedAsset.localIdentifier) else { return }
        previewTarget = MediaPreviewTarget(url: url)
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
            .overlay {
                if isCover {
                    CatalogShapes.thumbnail
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
                        .font(CatalogTypography.cardTitle)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(CatalogMediaContrast.onMediaPrimary, CatalogMediaContrast.scrimStrong)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }

            if isCover {
                Image(systemName: "star.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CatalogMediaContrast.onMediaPrimary)
                    .frame(width: 20, height: 20)
                    .background(.tint, in: Circle())
                    .padding(CatalogMetrics.Spacing.xxs)
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
