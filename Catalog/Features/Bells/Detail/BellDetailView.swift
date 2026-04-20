import SwiftUI
import UIKit
import QuickLook
import MapKit

struct BellDetailView: View {
    @Binding var bell: BellRecord
    let repository: any CatalogRepository
    @State private var draftNotes = ""
    @State private var draftTags: [String] = []
    @State private var tagInput = ""
    @State private var isPresentingEditor = false
    @State private var isPresentingLocationPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroHeader

                VStack(alignment: .leading, spacing: 18) {
                    detailSection(String(localized: "bell.detail.section.collection_info")) {
                        detailRow(String(localized: "bell.detail.acquisition"), value: bell.acquisitionMethod.displayName)
                        detailRow(String(localized: "bell.detail.condition"), value: bell.condition.displayName)
                    }

                    detailSection(String(localized: "bell.detail.section.location")) {
                        OriginStorageSection(
                            place: bell.originPlace,
                            storagePath: bell.storageDisplayPath,
                            accentColor: inferredCollection.backgroundStyle.accentColor,
                            isStorageAssigned: bell.item.locationID != nil,
                            onEditStorage: {
                                isPresentingLocationPicker = true
                            }
                        )
                    }

                    detailSection(String(localized: "bell.detail.section.media")) {
                        MediaSection(
                            itemID: bell.id,
                            mediaAssets: mediaAssetsBinding
                        )
                    }

                    detailSection(
                        String(localized: "bell.detail.section.notes"),
                        isHighlighted: isNotesOrTagsDirty,
                        tint: inferredCollection.backgroundStyle.accentColor
                    ) {
                        TextField(String(localized: "editor.note_history"), text: $draftNotes, axis: .vertical)
                            .lineLimit(6, reservesSpace: true)
                            .textFieldStyle(.plain)

                        TagEditorSection(
                            tagInput: $tagInput,
                            tags: $draftTags
                        )
                    }
                }
                .padding(.horizontal, CatalogLayoutInsets.screen)
                .padding(.top, CatalogSpacing.section)
                .padding(.bottom, CatalogSpacing.section)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .systemBackground))
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .background(
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNotesOrTagsDirty {
                ToolbarItem(placement: .topBarLeading) {
                    Button { discardNotesAndTagsChanges() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(String(localized: "common.cancel"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { saveNotesAndTagsChanges() } label: { Image(systemName: "checkmark") }
                    .accessibilityLabel(String(localized: "common.save"))
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPresentingEditor = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel(String(localized: "common.edit"))
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
        .sheet(isPresented: $isPresentingLocationPicker) {
            LocationHierarchyPickerView(
                locations: availableLocations,
                selectedLocationID: locationIDBinding
            )
        }
        .onAppear {
            syncDraftsFromBell()
        }
        .onChange(of: bell) { _, _ in
            guard !isNotesOrTagsDirty else { return }
            syncDraftsFromBell()
        }
    }

    private func detailSection<Content: View>(
        _ title: String,
        isHighlighted: Bool = false,
        tint: Color = .clear,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CatalogCornerRadii.section, style: .continuous)
                .fill(isHighlighted ? AnyShapeStyle(tint.opacity(0.10)) : AnyShapeStyle(.ultraThinMaterial))
        )
        .catalogShadow(
            isHighlighted
                ? CatalogElevation.highlightedDetailSection(tint: tint)
                : CatalogElevation.detailSection
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

    private var heroHeader: some View {
        BellCardHeroView(bell: bell)
    }

    private var availableLocations: [Location] {
        repository.fetchLocations(in: inferredCollection.homeID)
    }

    private var inferredCollection: CollectionSummary {
        repository.fetchCollections().first(where: { $0.id == bell.item.collectionID }) ??
            CollectionSummary(
                id: bell.item.collectionID,
                homeID: UUID(),
                kind: .bells,
                name: String(localized: "collection_kind.bells"),
                subtitle: "",
                backgroundStyle: .amber,
                itemCount: 0,
                collaboratorCount: 0,
                role: .owner,
                status: .active,
                sharingSummary: ""
            )
    }

    private var isNotesOrTagsDirty: Bool {
        draftNotes != bell.notes || draftTags != bell.tags
    }

    private func syncDraftsFromBell() {
        draftNotes = bell.notes
        draftTags = bell.tags
        tagInput = ""
    }

    private var mediaAssetsBinding: Binding<[MediaAsset]> {
        Binding(
            get: { bell.mediaAssets },
            set: { persist(mediaAssets: $0) }
        )
    }

    private var locationIDBinding: Binding<UUID?> {
        Binding(
            get: { bell.item.locationID },
            set: { persist(locationID: $0) }
        )
    }

    private func discardNotesAndTagsChanges() {
        syncDraftsFromBell()
    }

    private func saveNotesAndTagsChanges() {
        persist(
            notes: draftNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: draftTags
        )
        syncDraftsFromBell()
    }

    private func persist(
        notes: String? = nil,
        tags: [String]? = nil,
        mediaAssets: [MediaAsset]? = nil,
        locationID: UUID?? = nil
    ) {
        let resolvedLocationID = locationID ?? bell.item.locationID
        let location = availableLocations.first(where: { $0.id == resolvedLocationID })
        let locationsByID = Dictionary(uniqueKeysWithValues: availableLocations.map { ($0.id, $0) })
        let normalizedMediaAssets = (mediaAssets ?? bell.mediaAssets)
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, asset in
                MediaAsset(
                    id: asset.id,
                    itemID: bell.id,
                    kind: asset.kind,
                    localIdentifier: asset.localIdentifier,
                    displayName: asset.displayName,
                    sortOrder: index
                )
            }

        let updatedBell = BellRecord(
            item: Item(
                id: bell.item.id,
                collectionID: bell.item.collectionID,
                locationID: resolvedLocationID,
                createdAt: bell.item.createdAt,
                title: bell.item.title,
                notes: notes ?? bell.notes,
                acquiredYear: bell.item.acquiredYear,
                condition: bell.item.condition,
                acquisitionMethod: bell.item.acquisitionMethod
            ),
            details: bell.details,
            originPlace: bell.originPlace,
            storageLocation: location,
            storagePath: location.map { locationPath(for: $0, locationsByID: locationsByID) } ?? String(localized: "common.unassigned"),
            mediaAssets: normalizedMediaAssets,
            createdBy: bell.createdBy,
            tags: tags ?? bell.tags
        )

        repository.saveBellRecord(updatedBell)
        bell = updatedBell
    }

    private func locationPath(for location: Location, locationsByID: [UUID: Location]) -> String {
        var parts = [location.name]
        var currentParentID = location.parentLocationID

        while let parentID = currentParentID, let parent = locationsByID[parentID] {
            parts.insert(parent.name, at: 0)
            currentParentID = parent.parentLocationID
        }

        return parts.joined(separator: " / ")
    }
}

private struct OriginStorageSection: View {
    let place: Place?
    let storagePath: String
    let accentColor: Color
    let isStorageAssigned: Bool
    let onEditStorage: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            OriginTile(place: place, accentColor: accentColor)

            StorageTile(
                storagePath: storagePath,
                accentColor: accentColor,
                isAssigned: isStorageAssigned,
                onEditStorage: onEditStorage
            )
        }
    }
}

private struct OriginTile: View {
    let place: Place?
    let accentColor: Color

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = place?.latitude, let longitude = place?.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                if let coordinate {
                    Map(initialPosition: .region(
                        MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 4.8, longitudeDelta: 4.8)
                        )
                    ), interactionModes: []) {
                        Marker("", coordinate: coordinate)
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .clipShape(RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous)
                            .fill(CatalogSemanticColors.groupedSurfaceElevated)
                        Image(systemName: "mappin.slash")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                LinearGradient(
                    colors: [
                        CatalogMediaContrast.mapScrimTop,
                        CatalogMediaContrast.mapScrimMiddle,
                        CatalogMediaContrast.mapScrimBottom
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous))

                VStack(alignment: .leading, spacing: CatalogSpacing.compact) {
                    Label(String(localized: "bell.detail.origin"), systemImage: "mappin.and.ellipse")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(place?.displayName ?? String(localized: "common.unassigned"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(CatalogSpacing.regular)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .bottomLeading)
            .overlay(
                RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous)
                    .stroke(accentColor.opacity(0.22), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StorageTile: View {
    let storagePath: String
    let accentColor: Color
    let isAssigned: Bool
    let onEditStorage: () -> Void

    private var pathParts: [String] {
        storagePath
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        Button(action: onEditStorage) {
            tileContent
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tileContent: some View {
        Group {
            if isAssigned {
                assignedTileContent
            } else {
                placeholderTileContent
            }
        }
    }

    private var assignedTileContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(pathParts.enumerated()), id: \.offset) { index, part in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(index == pathParts.count - 1 ? accentColor.opacity(0.80) : CatalogSemanticColors.tertiaryLabel)
                            .frame(width: 7, height: 7)

                        Text(part)
                            .font(index == pathParts.count - 1 ? .subheadline.weight(.semibold) : .subheadline)
                            .foregroundStyle(index == pathParts.count - 1 ? .primary : .secondary)

                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(14)
            .background(CatalogSemanticColors.groupedSurfaceElevated, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous)
                    .stroke(accentColor.opacity(0.22), lineWidth: 1)
            )
        }
    }

    private var placeholderTileContent: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)

            Image(systemName: "square.stack.3d.up.slash")
                .font(.title2.weight(.semibold))
                .foregroundStyle(accentColor)

            Text(String(localized: "bell.detail.storage.assign.action"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(accentColor)
                .multilineTextAlignment(.center)

            Text(String(localized: "bell.detail.storage.placeholder"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        .padding(14)
        .background(accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                .foregroundStyle(accentColor.opacity(0.38))
        )
    }
}

private struct DetailTagChip: View {
    let tag: String
    let accentColor: Color

    var body: some View {
        Text("#\(tag)")
            .font(.subheadline.weight(.medium))
            .catalogPillPadding(.regular)
            .background(
                Capsule(style: .continuous)
                    .fill(accentColor.opacity(0.16))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(accentColor.opacity(0.34), lineWidth: 1)
            )
            .foregroundStyle(accentColor.opacity(0.95))
    }
}

private struct DetailTagFlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
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

            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(width: maxWidth.isFinite ? maxWidth : currentX, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
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

private struct BellDetailMediaTile: View {
    let asset: MediaAsset
    let onTap: () -> Void
    private let mediaStore = LocalMediaFileStore.shared

    var body: some View {
        Button(action: onTap) {
            thumbnail
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
                    .clipShape(RoundedRectangle(cornerRadius: CatalogCornerRadii.highlight, style: .continuous))
            } else {
                placeholder(systemImage: "photo")
            }
        case .document:
            ZStack {
                RoundedRectangle(cornerRadius: CatalogCornerRadii.highlight, style: .continuous)
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
            .frame(width: 116, height: 116)
        case .model3D:
            placeholder(systemImage: "cube.transparent")
        }
    }

    private func placeholder(systemImage: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: CatalogCornerRadii.highlight, style: .continuous)
                .fill(CatalogSemanticColors.groupedSurfaceElevated)
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
    var bright = false

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(backgroundColor, in: Capsule())
            .foregroundStyle(foregroundColor)
    }

    private var backgroundColor: Color {
        bright ? .white.opacity(0.18) : tint.opacity(0.12)
    }

    private var foregroundColor: Color {
        bright ? .white : tint
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
