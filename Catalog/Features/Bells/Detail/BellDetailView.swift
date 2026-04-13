import SwiftUI
import UIKit

struct BellDetailView: View {
    @Binding var bell: BellRecord
    let repository: any CatalogRepository
    @State private var isPresentingEditor = false
    private let mediaColumns = [GridItem(.adaptive(minimum: 108, maximum: 140), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(bell.title)
                        .font(.largeTitle.bold())
                    Text(bell.placeDisplayName)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        DetailBadge(label: bell.materialDisplayName, systemImage: "shippingbox.fill")
                        DetailBadge(label: bell.condition.rawValue, systemImage: "checkmark.seal")
                        if let year = bell.year {
                            DetailBadge(label: String(year), systemImage: "calendar")
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

                detailSection("Характеристики") {
                    detailRow("Материал", value: bell.materialDisplayName)
                    detailRow("Состояние", value: bell.condition.rawValue)
                    detailRow("Способ появления", value: bell.acquisitionMethod.rawValue)
                    detailRow("Хранится", value: bell.storageDisplayPath)
                    detailRow("Добавил", value: bell.createdBy)
                    if let year = bell.year {
                        detailRow("Год", value: String(year))
                    }
                }

                detailSection("Медиа") {
                    detailRow("Фото", value: String(bell.photoCount))
                    detailRow("3D models", value: String(bell.model3DCount))
                    detailRow("Documents", value: String(bell.documentCount))

                    if !bell.mediaAssets.isEmpty {
                        Divider()

                        LazyVGrid(columns: mediaColumns, alignment: .leading, spacing: 12) {
                            ForEach(bell.mediaAssets.sorted { $0.sortOrder < $1.sortOrder }) { asset in
                                BellDetailMediaTile(asset: asset)
                            }
                        }
                    }
                }

                if !bell.tags.isEmpty {
                    detailSection("Теги") {
                        Text(bell.tags.map { "#\($0)" }.joined(separator: "  "))
                            .font(.subheadline)
                            .foregroundStyle(Color(red: 0.43, green: 0.29, blue: 0.10))
                    }
                }

                detailSection("Заметки") {
                    Text(bell.notes)
                        .font(.body)
                }
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.96, blue: 0.90),
                    Color(red: 0.95, green: 0.91, blue: 0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Карточка")
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
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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

    private var inferredCollection: CollectionSummary {
        repository.fetchCollections().first(where: { $0.id == bell.item.collectionID }) ??
            CollectionSummary(
                id: bell.item.collectionID,
                kind: .bells,
                name: "Колокольчики",
                subtitle: "",
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
    private let mediaStore = LocalMediaFileStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail

            if asset.kind != .photo {
                Text(mediaTitle)
                    .font(.caption)
                    .lineLimit(2)
            }

            Text(asset.kind.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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

private struct DetailBadge: View {
    let label: String
    let systemImage: String

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color.black.opacity(0.05), in: Capsule())
            .foregroundStyle(.secondary)
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
