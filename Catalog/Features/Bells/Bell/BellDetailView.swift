import SwiftUI

/// Displays the bell detail view interface.
struct BellDetailView: View {

    @Binding var bell: BellRecord
    let repository: any CatalogRepository
    let catalogSnapshot: CatalogSnapshot?
    let canEditCollection: Bool
    let canChangeFavorite: Bool
    let onClose: (() -> Void)?
    @State private var draftNotes = ""
    @State private var draftTags: [String] = []
    @State private var tagInput = ""
    @State private var isPresentingEditor = false
    @State private var isPresentingOriginPicker = false
    @State private var isPresentingLocationPicker = false
    @State private var isPresentingHomeEditor = false
    @State private var draftHome = Home(id: UUID(), name: "", iconName: "house.fill", notes: "")
    @State private var draftHomeLocations: [Location] = []
    @State private var shouldPresentLocationPickerAfterHomeEditor = false
    @State private var isPresentingUnsavedChangesConfirmation = false
    @State private var selectedHeroPhotoID: UUID?
    private let detailContentFadeHeight: CGFloat = 80

    init(
        bell: Binding<BellRecord>,
        repository: any CatalogRepository,
        catalogSnapshot: CatalogSnapshot?,
        canEditCollection: Bool,
        canChangeFavorite: Bool = false,
        onClose: (() -> Void)? = nil
    ) {
        _bell = bell
        _selectedHeroPhotoID = State(initialValue: Self.heroPhotoAssets(in: bell.wrappedValue).first?.id)
        self.repository = repository
        self.catalogSnapshot = catalogSnapshot
        self.canEditCollection = canEditCollection
        self.canChangeFavorite = canChangeFavorite
        self.onClose = onClose
    }

    var body: some View {
        MediaQuickLookPresenter(mediaAssets: bell.mediaAssets) { preview in
            ScrollView {
                ZStack(alignment: .top) {
                    heroHeader(preview: preview)
                    detailContent
                }
            }
            .ignoresSafeArea(edges: .top)
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .interactiveDismissDisabled(canEditCollection && isNotesOrTagsDirty)
            .navigationTitle(bell.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                CatalogItemDetailToolbar(
                    onClose: onClose,
                    favorite: favoriteToolbarAction,
                    contentState: detailToolbarState
                )
            }
            .confirmationDialog(
                String(localized: "bell.detail.unsaved_changes.title"),
                isPresented: $isPresentingUnsavedChangesConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "common.save")) {
                    saveNotesAndTagsChanges()
                }

                Button(String(localized: "bell.detail.unsaved_changes.discard"), role: .destructive) {
                    discardNotesAndTagsChanges()
                }

                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "bell.detail.unsaved_changes.message"))
            }
            .sheet(isPresented: $isPresentingEditor) {
                if canEditCollection, let collection = inferredCollection {
                    BellEditorView(
                        collection: collection,
                        repository: repository,
                        catalogSnapshot: catalogSnapshot,
                        bell: bell
                    ) { updatedBell in
                        (repository as! any BellCatalogRepository).saveBellRecord(updatedBell)
                        bell = updatedBell
                        syncDraftsFromBell()
                    }
                }
            }
            .sheet(isPresented: $isPresentingOriginPicker) {
                PlacePickerView(
                    places: availablePlaces,
                    selectedPlace: originPlaceBinding
                )
            }
            .sheet(isPresented: $isPresentingLocationPicker) {
                LocationHierarchyPickerView(
                    locations: availableLocations,
                    selectedLocationID: locationIDBinding
                )
            }
            .sheet(isPresented: $isPresentingHomeEditor) {
                HomeEditorView(
                    home: $draftHome,
                    locations: $draftHomeLocations,
                    onSave: {
                        repository.saveHome(draftHome)
                        repository.saveLocations(draftHomeLocations, in: draftHome.id)
                        continueLocationSelectionIfNeeded()
                    },
                    onDelete: nil
                )
            }
            .onAppear {
                syncDraftsFromBell()
                syncSelectedHeroPhoto()
            }
            .onChange(of: bell) { _, _ in
                guard !isNotesOrTagsDirty else { return }
                syncDraftsFromBell()
            }
            .onChange(of: heroPhotoAssetIDs) { _, _ in
                syncSelectedHeroPhoto()
            }
        }
    }

    private var detailToolbarState: CatalogItemDetailToolbar.ContentState {
        guard canEditCollection else { return .readOnly }

        if isNotesOrTagsDirty {
            return .pendingChanges(
                onCancel: requestDiscardNotesAndTagsChanges,
                onSave: saveNotesAndTagsChanges
            )
        }

        return .viewing {
            isPresentingEditor = true
        }
    }

    private var favoriteToolbarAction: CatalogItemDetailToolbar.FavoriteAction? {
        guard canChangeFavorite else { return nil }

        return CatalogItemDetailToolbar.FavoriteAction(
            isFavorite: bell.isFavorite,
            action: toggleFavorite
        )
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.lg) {
            detailSection(String(localized: "bell.detail.section.collection_info")) {
                if let acquiredYear = bell.acquiredYear {
                    detailRow(String(localized: "common.field.acquired_year"), value: String(acquiredYear))
                }

                detailRow(String(localized: "bell.detail.acquisition"), value: bell.acquisitionMethod.displayName)
                detailRow(String(localized: "common.field.condition"), value: bell.condition.displayName)
                detailRow(String(localized: "common.field.material"), value: bell.materialDisplayName)
            }
            .padding(.horizontal, CatalogMetrics.Insets.screen)

            detailSection(String(localized: "bell.detail.section.location")) {
                OriginStorageSection(
                    place: bell.originPlace,
                    storagePath: bell.storageDisplayPath,
                    accentColor: detailAccentColor,
                    isStorageAssigned: bell.item.locationID != nil,
                    canEdit: canEditCollection,
                    onEditOrigin: {
                        isPresentingOriginPicker = true
                    },
                    onEditStorage: {
                        if availableLocations.isEmpty, let inferredCollection {
                            presentHomeEditor(for: inferredCollection.homeID)
                        } else {
                            isPresentingLocationPicker = true
                        }
                    }
                )
            }
            .padding(.horizontal, CatalogMetrics.Insets.screen)

            detailSection(String(localized: "common.field.notes")) {
                if canEditCollection {
                    TextField(String(localized: "editor.note_history"), text: $draftNotes, axis: .vertical)
                        .lineLimit(2...6)
                        .textFieldStyle(.plain)

                    TagEditorSection(
                        tagInput: $tagInput,
                        tags: $draftTags
                    )
                } else {
                    Text(bell.notes.isEmpty ? String(localized: "editor.note_history") : bell.notes)
                        .foregroundStyle(bell.notes.isEmpty ? .secondary : .primary)

                    if bell.tags.isEmpty {
                        Text(String(localized: "editor.tags.empty"))
                            .font(CatalogTypography.cardSubtitle)
                            .foregroundStyle(.secondary)
                    } else {
                        TagFlowLayout(spacing: CatalogMetrics.Spacing.sm) {
                            ForEach(bell.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(CatalogTypography.cardSubtitle)
                                    .catalogSurfaceCapsule()
                            }
                        }
                    }
                }
            }
            .padding(CatalogMetrics.Spacing.lg)
            .background(
                CatalogShapes.section
                    .fill(isNotesOrTagsDirty ? AnyShapeStyle(detailAccentColor.opacity(0.10)) : AnyShapeStyle(.ultraThinMaterial))
            )

            if !detailMediaAssets.isEmpty || canEditCollection {
                detailSection(String(localized: "editor.docs_and_media")) {
                    MediaSection(
                        itemID: bell.id,
                        mediaAssets: detailMediaAssetsBinding,
                        allowsAdding: canEditCollection,
                        allowsDeletion: false
                    )
                }
                .padding(.horizontal, CatalogMetrics.Insets.screen)
            }

        }
        .padding(.horizontal, CatalogMetrics.Insets.screen)
        .padding(.top, detailContentFadeHeight)
        .padding(.bottom, CatalogMetrics.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.65),
                        .init(color: Color(.systemBackground), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: detailContentFadeHeight)

                Color(.systemBackground)
            }
        }
        .padding(.top, 240)
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            Text(title)
                .font(CatalogTypography.sectionTitle)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func heroHeader(preview: @escaping (MediaAsset) -> Void) -> some View {
        GeometryReader { proxy in
            ZStack {
                if !heroPhotoAssets.isEmpty {
                    TabView(selection: $selectedHeroPhotoID) {
                        ForEach(heroPhotoAssets) { asset in
                            MediaPreviewImage(
                                identifier: asset.localIdentifier.isEmpty ? nil : asset.localIdentifier,
                                originalData: asset.originalData,
                                size: CGSize(width: proxy.size.width, height: 320)
                            )
                            .frame(width: proxy.size.width, height: 320)
                            .tag(Optional(asset.id))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: heroPhotoAssets.count > 1 ? .automatic : .never))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let selectedHeroPhoto {
                            preview(selectedHeroPhoto)
                        }
                    }
                } else {
                    LinearGradient(
                        colors: [
                            CatalogMediaContrast.onMediaPrimary.opacity(0.88),
                            CatalogMediaContrast.onMediaPrimary.opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: proxy.size.width, height: 320)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color(uiColor: .systemBackground).opacity(0.22), location: 0.72),
                        .init(color: Color(uiColor: .systemBackground).opacity(0.55), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
            }
        }
        .frame(height: 320)
        .ignoresSafeArea(edges: .top)
    }

    private var heroPhotoAssets: [MediaAsset] {
        Self.heroPhotoAssets(in: bell)
    }

    private static func heroPhotoAssets(in bell: BellRecord) -> [MediaAsset] {
        bell.mediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var heroPhotoAssetIDs: [UUID] {
        heroPhotoAssets.map(\.id)
    }

    private var detailMediaAssets: [MediaAsset] {
        let heroPhotoAssetIDs = Set(heroPhotoAssetIDs)
        return bell.mediaAssets.filter { !heroPhotoAssetIDs.contains($0.id) }
    }

    private var selectedHeroPhoto: MediaAsset? {
        heroPhotoAssets.first { $0.id == selectedHeroPhotoID } ?? heroPhotoAssets.first
    }

    private func syncSelectedHeroPhoto() {
        guard !heroPhotoAssets.isEmpty else {
            selectedHeroPhotoID = nil
            return
        }

        if selectedHeroPhotoID.map({ heroPhotoAssetIDs.contains($0) }) != true {
            selectedHeroPhotoID = heroPhotoAssets.first?.id
        }
    }

    private var availableLocations: [Location] {
        guard let snapshot = catalogSnapshot,
              let collection = inferredCollection else { return [] }

        let collectionLocations = snapshot.collectionLocationsByCollectionID[collection.id] ?? []
        if !collectionLocations.isEmpty {
            return collectionLocations
        }

        return snapshot.locationsByHomeID[collection.homeID] ?? []
    }

    private var availablePlaces: [Place] {
        catalogSnapshot?.places ?? []
    }

    private var inferredCollection: CollectionSummary? {
        catalogSnapshot?.collectionSummary(id: bell.item.collectionID)
    }

    private var detailAccentColor: Color {
        inferredCollection?.backgroundStyle.accentColor ?? CollectionBackgroundStyle.amber.accentColor
    }

    private var isNotesOrTagsDirty: Bool {
        draftNotes != bell.notes || draftTags != bell.tags
    }

    private func syncDraftsFromBell() {
        draftNotes = bell.notes
        draftTags = bell.tags
        tagInput = ""
    }

    private func presentHomeEditor(for homeID: UUID) {
        guard let snapshot = catalogSnapshot,
              let home = snapshot.homes.first(where: { $0.id == homeID }) else { return }
        draftHome = home
        draftHomeLocations = snapshot.locationsByHomeID[homeID] ?? []
        shouldPresentLocationPickerAfterHomeEditor = true
        isPresentingHomeEditor = true
    }

    private func continueLocationSelectionIfNeeded() {
        guard shouldPresentLocationPickerAfterHomeEditor else { return }
        shouldPresentLocationPickerAfterHomeEditor = false
        isPresentingHomeEditor = false
        DispatchQueue.main.async {
            isPresentingLocationPicker = true
        }
    }

    private var detailMediaAssetsBinding: Binding<[MediaAsset]> {
        Binding(
            get: { detailMediaAssets },
            set: {
                guard canEditCollection else { return }
                let detailMediaAssetIDs = Set(detailMediaAssets.map(\.id))
                let heroAndUnchangedAssets = bell.mediaAssets.filter { !detailMediaAssetIDs.contains($0.id) }
                persist(mediaAssets: heroAndUnchangedAssets + $0)
            }
        )
    }

    private var locationIDBinding: Binding<UUID?> {
        Binding(
            get: { bell.item.locationID },
            set: {
                guard canEditCollection else { return }
                persistStorage(locationID: $0)
            }
        )
    }

    private var originPlaceBinding: Binding<Place?> {
        Binding(
            get: { bell.originPlace },
            set: {
                guard canEditCollection else { return }
                persistOriginPlace($0)
            }
        )
    }

    private func requestDiscardNotesAndTagsChanges() {
        guard canEditCollection else { return }
        guard isNotesOrTagsDirty else { return }
        isPresentingUnsavedChangesConfirmation = true
    }

    private func discardNotesAndTagsChanges() {
        syncDraftsFromBell()
    }

    private func saveNotesAndTagsChanges() {
        guard canEditCollection else { return }
        persist(
            notes: draftNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: draftTags
        )
        syncDraftsFromBell()
    }

    private func toggleFavorite() {
        guard canChangeFavorite else { return }
        var updatedItem = bell.item
        updatedItem.isFavorite.toggle()
        save(updatedItem)
    }

    private func persist(
        notes: String? = nil,
        tags: [String]? = nil,
        mediaAssets: [MediaAsset]? = nil
    ) {
        guard canEditCollection else { return }
        var updatedItem = bell.item

        if let notes {
            updatedItem.notes = notes
        }

        if let tags {
            updatedItem.tags = tags
        }

        if let mediaAssets {
            updatedItem.mediaAssets = mediaAssets
                .sorted { $0.sortOrder < $1.sortOrder }
                .enumerated()
                .map { index, asset in
                    asset.with(itemID: bell.id, sortOrder: index)
                }
        }

        save(updatedItem)
    }

    private func persistOriginPlace(_ place: Place?) {
        guard canEditCollection else { return }
        var updatedItem = bell.item
        updatedItem.setOriginPlace(place)
        save(updatedItem)
    }

    private func persistStorage(locationID: UUID?) {
        guard canEditCollection else { return }
        var updatedItem = bell.item
        let location = locationID.flatMap { id in
            availableLocations.first { $0.id == id }
        }
        let locationsByID = Dictionary(uniqueKeysWithValues: availableLocations.map { ($0.id, $0) })
        let path = location.map { storagePath(for: $0, locationsByID: locationsByID) }
        updatedItem.setStorageLocation(location, path: path)
        save(updatedItem)
    }

    private func save(_ item: ItemRecord) {
        let updatedBell = BellRecord(item: item, details: bell.details)
        bell = updatedBell
        (repository as! any BellCatalogRepository).saveBellRecord(updatedBell)
    }

    private func storagePath(for location: Location, locationsByID: [UUID: Location]) -> StoragePath {
        var components = [
            StoragePath.Component(
                kind: location.kind,
                name: location.name
            )
        ]
        var currentParentID = location.parentLocationID

        while let parentID = currentParentID, let parent = locationsByID[parentID] {
            components.insert(
                StoragePath.Component(
                    kind: parent.kind,
                    name: parent.name
                ),
                at: 0
            )
            currentParentID = parent.parentLocationID
        }

        return StoragePath(components: components)
    }
}

private struct BellDetailPreviewHost: View {
    let initialBell: BellRecord
    let repository: any CatalogRepository
    let catalogSnapshot: CatalogSnapshot?
    @State private var bell: BellRecord

    init(bell: BellRecord, repository: any CatalogRepository, catalogSnapshot: CatalogSnapshot?) {
        self.initialBell = bell
        self.repository = repository
        self.catalogSnapshot = catalogSnapshot
        _bell = State(initialValue: bell)
    }

    var body: some View {
        BellDetailView(
            bell: $bell,
            repository: repository,
            catalogSnapshot: catalogSnapshot,
            canEditCollection: false,
            canChangeFavorite: false
        )
    }
}

#if DEBUG
#Preview {
    let container = PreviewContainer.makeBellsMinimal()
    let repository = CoreDataCatalogRepository(
        context: container.viewContext,
        persistentContainer: nil
    )
    let snapshot = CatalogSnapshot.load(from: container.viewContext)
    let collection = snapshot.collections.first { $0.kind == .bells }!
    let bell = snapshot.bellRecords.first { $0.item.collectionID == collection.id && $0.mediaAssets.count == 2 }!

    NavigationStack {
        BellDetailPreviewHost(
            bell: bell,
            repository: repository,
            catalogSnapshot: snapshot
        )
        .environment(\.managedObjectContext, container.viewContext)
    }
}
#endif