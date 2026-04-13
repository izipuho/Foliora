import SwiftUI
import UIKit
import QuickLook

private func DL(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

struct BellDetailView: View {
    @Binding var bell: BellRecord
    let repository: any CatalogRepository
    @State private var isPresentingEditor = false
    @State private var previewTarget: MediaPreviewTarget?
    private let mediaColumns = [GridItem(.adaptive(minimum: 108, maximum: 140), spacing: 12)]

    private var themeColors: [Color] {
        inferredCollection.backgroundStyle.screenColors
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(bell.title)
                        .font(.largeTitle.bold())
                    Text(bell.placeDisplayName)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        DetailBadge(label: bell.materialDisplayName, systemImage: "shippingbox.fill", tint: inferredCollection.backgroundStyle.accentColor)
                        DetailBadge(label: bell.condition.displayName, systemImage: "checkmark.seal", tint: inferredCollection.backgroundStyle.accentColor)
                        if let year = bell.year {
                            DetailBadge(label: String(year), systemImage: "calendar", tint: inferredCollection.backgroundStyle.accentColor)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.94), Color.white.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )

                detailSection(DL("bell.detail.section.attributes")) {
                    detailRow(DL("bell.detail.material"), value: bell.materialDisplayName)
                    detailRow(DL("bell.detail.condition"), value: bell.condition.displayName)
                    detailRow(DL("bell.detail.acquisition"), value: bell.acquisitionMethod.displayName)
                    detailRow(DL("bell.detail.storage"), value: bell.storageDisplayPath)
                    detailRow(DL("bell.detail.created_by"), value: bell.createdBy)
                    if let year = bell.year {
                        detailRow(DL("bell.detail.year"), value: String(year))
                    }
                }

                detailSection(DL("bell.detail.section.media")) {
                    detailRow(DL("bell.detail.photos"), value: String(bell.photoCount))
                    detailRow(DL("bell.detail.models"), value: String(bell.model3DCount))
                    detailRow(DL("bell.detail.documents"), value: String(bell.documentCount))

                    if !bell.mediaAssets.isEmpty {
                        Divider()

                        LazyVGrid(columns: mediaColumns, alignment: .leading, spacing: 12) {
                            ForEach(bell.mediaAssets.sorted { $0.sortOrder < $1.sortOrder }) { asset in
                                BellDetailMediaTile(asset: asset) {
                                    openPreview(for: asset)
                                }
                            }
                        }
                    }
                }

                if !bell.tags.isEmpty {
                    detailSection(DL("bell.detail.section.tags")) {
                        Text(bell.tags.map { "#\($0)" }.joined(separator: "  "))
                            .font(.subheadline)
                            .foregroundStyle(Color(red: 0.43, green: 0.29, blue: 0.10))
                    }
                }

                detailSection(DL("bell.detail.section.notes")) {
                    Text(bell.notes)
                        .font(.body)
                }
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .background(
            LinearGradient(
                colors: themeColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle(DL("bell.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingEditor = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            BellEditorView(
                collection: inferredCollection,
                repository: repository,
                bell: bell
            ) { updatedBell in
                repository.saveBellRecord(updatedBell)
                bell = updatedBell
            }
        }
        .sheet(item: $previewTarget) { target in
            switch target.kind {
            case .photo:
                MediaPhotoPreviewScreen(url: target.url)
            case .document, .model3D:
                QuickLookPreview(url: target.url)
            }
        }
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.84), inferredCollection.backgroundStyle.colors[0].opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func openPreview(for asset: MediaAsset) {
        let mediaStore = LocalMediaFileStore.shared
        guard let url = mediaStore.fileURL(for: asset.localIdentifier) else { return }
        previewTarget = MediaPreviewTarget(url: url, kind: asset.kind)
    }

    private var inferredCollection: CollectionSummary {
        repository.fetchCollections().first(where: { $0.id == bell.item.collectionID }) ??
            CollectionSummary(
                id: bell.item.collectionID,
                homeID: UUID(),
                kind: .bells,
                name: DL("collection_kind.bells"),
                subtitle: "",
                backgroundStyle: .amber,
                itemCount: 0,
                collaboratorCount: 0,
                role: .owner,
                status: .active,
                sharingSummary: ""
            )
    }
}

private struct BellDetailMediaTile: View {
    let asset: MediaAsset
    let onTap: () -> Void
    private let mediaStore = LocalMediaFileStore.shared

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                thumbnail

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
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch asset.kind {
        case .photo:
            if let image = previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 116, height: 116)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                placeholder(systemImage: "photo")
            }
        case .document:
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
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
            .frame(width: 116, height: 116)
        case .model3D:
            placeholder(systemImage: "cube.transparent")
        }
    }

    private func placeholder(systemImage: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.05))
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(width: 116, height: 116)
    }

    private var previewImage: UIImage? {
        guard let url = mediaStore.fileURL(for: asset.localIdentifier),
              let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }

        return image
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

    private var documentExtension: String {
        let ext = URL(fileURLWithPath: asset.localIdentifier).pathExtension.uppercased()
        return ext.isEmpty ? "FILE" : ext
    }
}

private struct MediaPreviewTarget: Identifiable {
    let id = UUID()
    let url: URL
    let kind: MediaKind
}

private struct MediaPhotoPreviewScreen: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                } else {
                    ContentUnavailableView(
                        "Preview Unavailable",
                        systemImage: "photo",
                        description: Text("The image file could not be loaded.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
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

private struct DetailBadge: View {
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }
}

struct BellDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            let repository = InMemoryCatalogRepository()
            let collection = repository.fetchCollections().first { $0.kind == .bells }!
            BellDetailPreviewHost(collectionID: collection.id, repository: repository)
        }
    }
}

private struct BellDetailPreviewHost: View {
    let collectionID: UUID
    let repository: any CatalogRepository
    @State private var bell: BellRecord

    init(collectionID: UUID, repository: any CatalogRepository) {
        self.collectionID = collectionID
        self.repository = repository
        _bell = State(initialValue: repository.fetchBellRecords(for: collectionID)[0])
    }

    var body: some View {
        BellDetailView(
            bell: $bell,
            repository: repository
        )
    }
}
