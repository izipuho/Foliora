import SwiftUI

struct BellDetailView: View {

    @Binding var bell: BellRecord
    let repository: any CatalogRepository
    let canEditCollection: Bool
    let canChangeFavorite: Bool
    @Environment(\.managedObjectContext) private var managedObjectContext
    @State private var lookupSnapshot = BellLookupSnapshot()
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
    private let detailContentFadeHeight: CGFloat = 80

    init(bell: Binding<BellRecord>, repository: any CatalogRepository, canEditCollection: Bool, canChangeFavorite: Bool = false) {
        _bell = bell
        self.repository = repository
        self.canEditCollection = canEditCollection
        self.canChangeFavorite = canChangeFavorite
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
                if canChangeFavorite {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { toggleFavorite() } label: {
                            Image(systemName: bell.isFavorite ? "star.fill" : "star")
                        }
                        .accessibilityLabel(bell.isFavorite ? "bell.favorite.remove" : "bell.favorite.add")
                    }
                }

                if canEditCollection && isNotesOrTagsDirty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { requestDiscardNotesAndTagsChanges() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(String(localized: "common.cancel"))
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button { saveNotesAndTagsChanges() } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel(String(localized: "common.save"))
                    }
                } else if canEditCollection {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { isPresentingEditor = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel(String(localized: "common.edit"))
                    }
                }
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
                        bell: bell
                    ) { updatedBell in
                        repository.saveBellRecord(updatedBell)
                        bell = updatedBell
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
                        reloadLookupSnapshot()
                        continueLocationSelectionIfNeeded()
                    },
                    onDelete: nil
                )
            }
            .task {
                reloadLookupSnapshot()
            }
            .onAppear {
                syncDraftsFromBell()
            }
            .onChange(of: bell) { _, _ in
                guard !isNotesOrTagsDirty else { return }
                syncDraftsFromBell()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: managedObjectContext)) { _ in
                reloadLookupSnapshot()
            }
        }
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.lg) {
            detailSection(String(localized: "bell.detail.section.collection_info")) {
                if let acquiredYear = bell.acquiredYear {
                    detailRow(String(localized: "common.field.acquired_year"), value: String(acquiredYear))
                }

                detailRow(String(localized: "bell.detail.acquisition"), value: bell.acquisitionMethod.displayName)
                detailRow(String(localized: "common.field.condition"), value: bell.condition.displayName)
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

            detailSection(String(localized: "bell.detail.section.media")) {
                MediaSection(
                    itemID: bell.id,
                    mediaAssets: mediaAssetsBinding,
                    allowsAdding: canEditCollection,
                    allowsDeletion: false
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
        }
        .padding(.horizontal, CatalogMetrics.Insets.screen)
        .padding(.top, detailContentFadeHeight)
        .padding(.bottom, CatalogMetrics.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        .clear,
                        Color(.systemBackground).opacity(0.88),
                        Color(.systemBackground)
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
                if let coverPhoto = heroPhotoAsset {
                    MediaPreviewImage(
                        identifier: coverPhoto.localIdentifier.isEmpty ? nil : coverPhoto.localIdentifier,
                        thumbnailData: coverPhoto.thumbnailData,
                        originalData: coverPhoto.originalData,
                        size: CGSize(width: proxy.size.width, height: 320)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        preview(coverPhoto)
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

    private var heroPhotoAsset: MediaAsset? {
        bell.mediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first
    }

    private var availableLocations: [Location] {
        guard let homeID = inferredCollection?.homeID else { return [] }
        return lookupSnapshot.locations.filter { $0.homeID == homeID }
    }

    private var availablePlaces: [Place] {
        lookupSnapshot.places
    }

    private var inferredCollection: CollectionSummary? {
        lookupSnapshot.collections.first(where: { $0.id == bell.item.collectionID })?.summarySnapshot
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

    private func reloadLookupSnapshot() {
        lookupSnapshot = CoreDataBellLookupSnapshotLoader(context: managedObjectContext)
            .loadSnapshot(collectionID: bell.item.collectionID, homeID: nil)
    }

    private func presentHomeEditor(for homeID: UUID) {
        guard let home = lookupSnapshot.homes.first(where: { $0.id == homeID }) else { return }
        draftHome = home
        draftHomeLocations = availableLocations
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

    private var mediaAssetsBinding: Binding<[MediaAsset]> {
        Binding(
            get: { bell.mediaAssets },
            set: {
                guard canEditCollection else { return }
                persist(mediaAssets: $0)
            }
        )
    }

    private var locationIDBinding: Binding<UUID?> {
        Binding(
            get: { bell.item.locationID },
            set: {
                guard canEditCollection else { return }
                persist(locationID: $0)
            }
        )
    }

    private var originPlaceBinding: Binding<Place?> {
        Binding(
            get: { bell.originPlace },
            set: {
                guard canEditCollection else { return }
                persist(originPlace: $0)
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
        let updatedBell = BellRecord(
            item: bell.item,
            details: bell.details,
            originPlace: bell.originPlace,
            storageLocation: bell.storageLocation,
            storagePath: bell.storagePath,
            mediaAssets: bell.mediaAssets,
            isFavorite: !bell.isFavorite,
            createdBy: bell.createdBy,
            tags: bell.tags
        )

        bell = updatedBell
        repository.saveBellRecord(updatedBell)
    }

    private func persist(
        notes: String? = nil,
        tags: [String]? = nil,
        mediaAssets: [MediaAsset]? = nil,
        originPlace: Place?? = nil,
        locationID: UUID?? = nil
    ) {
        guard canEditCollection else { return }
        let resolvedOriginPlace = originPlace ?? bell.originPlace
        let resolvedLocationID = locationID ?? bell.item.locationID
        let location = availableLocations.first(where: { $0.id == resolvedLocationID })
        let locationsByID = Dictionary(uniqueKeysWithValues: availableLocations.map { ($0.id, $0) })
        let normalizedMediaAssets = (mediaAssets ?? bell.mediaAssets)
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, asset in
                asset.with(itemID: bell.id, sortOrder: index)
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
            details: BellDetails(
                itemID: bell.details.itemID,
                originPlaceID: resolvedOriginPlace?.id,
                material: bell.details.material,
                customMaterialName: bell.details.customMaterialName
            ),
            originPlace: resolvedOriginPlace,
            storageLocation: location,
            storagePath: location.map { locationPath(for: $0, locationsByID: locationsByID) } ?? String(localized: "common.unassigned"),
            mediaAssets: normalizedMediaAssets,
            isFavorite: bell.isFavorite,
            createdBy: bell.createdBy,
            tags: tags ?? bell.tags
        )

        repository.saveBellRecord(updatedBell)
        bell = updatedBell
        reloadLookupSnapshot()
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

private struct BellDetailPreviewHost: View {
    let collectionID: UUID
    let repository: any CatalogRepository
    @Environment(\.managedObjectContext) private var managedObjectContext
    @State private var lookupSnapshot = BellLookupSnapshot()
    @State private var bell: BellRecord?

    var body: some View {
        Group {
            if let binding = bellBinding {
                BellDetailView(
                    bell: binding,
                    repository: repository,
                    canEditCollection: false,
                    canChangeFavorite: false
                )
            } else {
                CatalogEmptyStateView(
                    systemImage: "bell.slash",
                    title: LocalizedStringKey(String(localized: "home.not_found.title"))
                )
            }
        }
        .task {
            reloadLookupSnapshot()
            syncBellIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: managedObjectContext)) { _ in
            reloadLookupSnapshot()
            syncBellIfNeeded()
        }
    }

    private var bellBinding: Binding<BellRecord>? {
        guard bell != nil else { return nil }
        return Binding(
            get: { bell! },
            set: { bell = $0 }
        )
    }

    private func syncBellIfNeeded() {
        guard bell == nil else { return }
        bell = lookupSnapshot.bells.first(where: { $0.item.collectionID == collectionID })
    }

    private func reloadLookupSnapshot() {
        lookupSnapshot = CoreDataBellLookupSnapshotLoader(context: managedObjectContext)
            .loadSnapshot(collectionID: collectionID, homeID: nil)
    }
}

private extension Collection {
    var summarySnapshot: CollectionSummary {
        CollectionSummary(
            id: id,
            homeID: homeID,
            kind: kind,
            name: title,
            subtitle: notes,
            backgroundStyle: backgroundStyle,
            itemCount: 0,
            status: kind == .bells ? .active : .planned,
            sharingSummary: "Invitation-only. Members join with Apple ID and receive a role inside the collection."
        )
    }
}
