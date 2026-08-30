import SwiftUI
import PhotosUI
import CoreData

/// Displays the bell collection view interface.
struct BellCollectionView: View {
    let catalogSnapshot: CatalogSnapshot?
    let collection: CollectionSummary
    let repository: any CatalogRepository
    let coreDataContainer: NSPersistentCloudKitContainer
    private let onBellSelected: ((UUID) -> Void)?
    private let onBatchAddComplete: (BatchAddCompletionAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPresentingAddBell = false
    @State private var isPresentingBatchAdd = false
    @State private var isPresentingAddBellOptions = false
    @State private var isPresentingPhotoPicker = false
    @State private var isPresentingCamera = false
    @State private var shouldPresentEditorAfterCamera = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var draftMediaAssets: [MediaAsset] = []
    @State private var draftAnalysisImage: UIImage?
    @State private var isPresentingEditCollection = false
    @State private var isPresentingFilters = false
    @State private var collectionSharingState: CollectionSharingState?
    @State private var collectionSharingLoadError: Error?
    @State private var favoriteChangeRevision = 0
    @AppStorage("bellCatalog.orderMode") private var selectedOrderRawValue = BellOrderMode.newestFirst.rawValue
    private let layoutMode: Binding<CatalogCardLayoutMode>
    @State private var selectedSummaryFilter = BellFilters()
    @State private var isBellCatalogSelectionMode = false
    private let imageMediaBuilder = ImageMediaBuilder(store: .shared)

    init(
        collection: CollectionSummary,
        catalogSnapshot: CatalogSnapshot?,
        repository: any CatalogRepository,
        coreDataContainer: NSPersistentCloudKitContainer,
        layoutMode: Binding<CatalogCardLayoutMode>,
        onBellSelected: ((UUID) -> Void)? = nil,
        onBatchAddComplete: @escaping (BatchAddCompletionAction) -> Void = { _ in }
    ) {
        self.collection = collection
        self.catalogSnapshot = catalogSnapshot
        self.repository = repository
        self.coreDataContainer = coreDataContainer
        self.onBellSelected = onBellSelected
        self.onBatchAddComplete = onBatchAddComplete
        self.layoutMode = layoutMode
    }

    private var homes: [Home] {
        catalogSnapshot?.homes ?? []
    }

    private var collectionBells: [BellListItem] {
        catalogSnapshot?.bells.filter { $0.collectionID == collection.id } ?? []
    }

    private var hasPlacedItems: Bool {
        catalogSnapshot?.bellRecords.contains {
            $0.item.collectionID == collection.id && $0.item.locationID != nil
        } ?? false
    }

    private var selectedOrder: BellOrderMode {
        get {
            BellOrderMode(rawValue: selectedOrderRawValue) ?? .newestFirst
        }
        nonmutating set {
            selectedOrderRawValue = newValue.rawValue
        }
    }

    private var selectedOrderBinding: Binding<BellOrderMode> {
        Binding(
            get: { selectedOrder },
            set: { selectedOrder = $0 }
        )
    }

    private var selectedLayoutModeBinding: Binding<CatalogCardLayoutMode> {
        layoutMode
    }

    private var canEditCollection: Bool {
        guard collectionSharingLoadError == nil else { return false }

        switch collectionSharingState?.currentUserRole {
        case .owner, .contributor:
            return true
        case .viewer, nil:
            return false
        }
    }

    private var canManageCollectionSharing: Bool {
        guard collectionSharingLoadError == nil else { return false }
        return collectionSharingState?.currentUserRole == .owner
    }

    private var collectionSharingDestination: AnyView? {
        guard canManageCollectionSharing else { return nil }

        return AnyView(CollectionSharingStateLoaderView(
            collection: collection,
            sharingService: CloudKitCollectionSharingService(persistentContainer: coreDataContainer)
        ))
    }

    private var collectionToolbar: some ToolbarContent {
        CatalogCollectionToolbar(
            selectedSort: selectedOrderBinding,
            selectedLayoutMode: selectedLayoutModeBinding,
            isPresentingAddOptions: $isPresentingAddBellOptions,
            sortOptions: [.newestFirst, .title, .geography, .acquisitionYear, .storage],
            sortSectionTitle: String(localized: "bell_catalog.sort.menu"),
            sortTitle: { option in
                if option == .newestFirst {
                    return String(localized: "bell_catalog.sort.recently_added")
                }

                return String(localized: option.title)
            },
            hasActiveFilters: !selectedSummaryFilter.isEmpty,
            onFilters: {
                isPresentingFilters = true
            },
            canEdit: canEditCollection,
            onEdit: {
                guard canEditCollection else { return }
                isPresentingEditCollection = true
            },
            onPhotoLibrary: {
                guard canEditCollection else { return }
                isPresentingPhotoPicker = true
            },
            onCamera: {
                guard canEditCollection else { return }
                isPresentingCamera = true
            }
        )
    }

    var body: some View {
        let _ = favoriteChangeRevision

        content
            .toolbar {
                if !isBellCatalogSelectionMode {
                    collectionToolbar
                }
            }
            .onPreferenceChange(BellCatalogSelectionModePreferenceKey.self) { isSelectionMode in
                isBellCatalogSelectionMode = isSelectionMode
            }
            .onReceive(NotificationCenter.default.publisher(for: .catalogItemFavoriteDidChange)) { notification in
                guard
                    let change = notification.object as? CatalogItemFavoriteChange,
                    change.collectionID == collection.id
                else {
                    return
                }

                favoriteChangeRevision &+= 1
            }
            .photosPicker(
                isPresented: $isPresentingPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: nil,
                matching: .images,
                photoLibrary: .shared()
            )
            .fullScreenCover(isPresented: $isPresentingCamera) {
                cameraPicker
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                Task {
                    await addDraftPhotosAndPresentEditor(from: newItems)
                }
            }
            .onChange(of: isPresentingCamera) { _, isPresented in
                if !isPresented, shouldPresentEditorAfterCamera, !draftMediaAssets.isEmpty {
                    shouldPresentEditorAfterCamera = false
                    isPresentingAddBell = true
                }
            }
            .sheet(isPresented: $isPresentingAddBell, onDismiss: clearDraftBell) {
                addBellSheet
            }
            .sheet(isPresented: $isPresentingBatchAdd, onDismiss: clearDraftBell) {
                batchAddSheet
            }
            .sheet(isPresented: $isPresentingEditCollection) {
                editCollectionSheet
            }
            .sheet(isPresented: $isPresentingFilters) {
                BellCollectionFilterView(
                    bells: collectionBells,
                    filters: selectedSummaryFilter
                ) { updatedFilters in
                    selectedSummaryFilter = updatedFilters
                }
            }
            .task(id: collection.id) {
                await loadCollectionSharingState()
            }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if canEditCollection && collection.itemCount == 0 {
                CatalogEmptyStateView(
                    systemImage: "bell.slash",
                    title: "bell_catalog.empty.title",
                    message: "bell_catalog.empty.description",
                    primaryActionTitle: "editor.bell.add",
                    primaryActionSystemImage: "plus.circle.fill",
                    primaryTint: collection.backgroundStyle.accentColor,
                    primaryAction: { isPresentingAddBellOptions = true }
                )
                .background(
                    CatalogBackgrounds.collection(
                        collection.backgroundStyle.accentColor,
                        scheme: colorScheme
                    )
                    .ignoresSafeArea()
                )
            } else {
                BellCatalogView(
                    collection: collection,
                    repository: repository,
                    catalogSnapshot: catalogSnapshot,
                    layoutMode: selectedLayoutModeBinding,
                    orderMode: selectedOrderBinding,
                    filters: $selectedSummaryFilter,
                    sharingState: collectionSharingState ?? .privateState,
                    sharingService: CloudKitCollectionSharingService(persistentContainer: coreDataContainer),
                    onSharingChanged: {
                        Task {
                            await loadCollectionSharingState()
                        }
                    },
                    canEditCollection: canEditCollection,
                    onBellSelected: onBellSelected
                )
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var addBellSheet: some View {
        BellEditorView(
            collection: collection,
            repository: repository,
            catalogSnapshot: catalogSnapshot,
            initialMediaAssets: draftMediaAssets,
            initialAnalysisImage: draftAnalysisImage
        ) { newBell in
            (repository as! any BellCatalogRepository).saveBellRecord(newBell)
        }
    }

    private var batchAddSheet: some View {
        BellBatchAddView(
            collection: collection,
            photoCount: draftMediaAssets.count,
            catalogSnapshot: catalogSnapshot,
            initialMediaAssets: draftMediaAssets,
            repository: repository,
            onComplete: handleBatchAddCompletion
        )
    }

    private var editCollectionSheet: some View {
        CollectionEditorView(
            homes: homes,
            screenTitle: String(localized: "collection.editor.edit_title"),
            initialTitle: collection.name,
            initialNotes: collection.subtitle,
            initialHomeID: collection.homeID,
            initialBackgroundStyle: collection.backgroundStyle,
            hasPlacedItems: hasPlacedItems,
            allowsDeletion: true,
            sharingDestination: collectionSharingDestination
        ) { title, notes, homeID, backgroundStyle in
            saveCollectionEdits(title: title, notes: notes, homeID: homeID, backgroundStyle: backgroundStyle)
        } onDelete: {
            repository.deleteCollection(collectionID: collection.id)
            dismiss()
        }
    }

    private var cameraPicker: some View {
        CameraPicker { image in
            Task {
                await addCapturedPhotoAndPresentEditor(image)
            }
        }
    }

    private func clearDraftBell() {
        draftMediaAssets = []
        draftAnalysisImage = nil
    }

    private func saveCollectionEdits(title: String, notes: String, homeID: UUID, backgroundStyle: CollectionBackgroundStyle) {
        guard canEditCollection else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedCollection = Collection(
            id: collection.id,
            homeID: homeID,
            kind: collection.kind,
            title: trimmedTitle.isEmpty ? collection.name : trimmedTitle,
            notes: trimmedNotes,
            backgroundStyle: backgroundStyle
        )

        repository.saveCollection(updatedCollection)
    }

    @MainActor
    private func loadCollectionSharingState() async {
        collectionSharingState = nil
        collectionSharingLoadError = nil

        do {
            collectionSharingState = try await CloudKitCollectionSharingService(
                persistentContainer: coreDataContainer
            ).sharingState(for: collection.id)
        } catch {
            collectionSharingLoadError = error
        }
    }

    private func handleBatchAddCompletion(_ action: BatchAddCompletionAction) {
        isPresentingBatchAdd = false

        if case .reviewResults = action {
            onBatchAddComplete(action)
        }
    }

    @MainActor
    private func addDraftPhotosAndPresentEditor(from items: [PhotosPickerItem]) async {
        guard canEditCollection else { return }
        guard !items.isEmpty else { return }

        var newAssets: [MediaAsset] = []
        var firstImage: UIImage?

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

            if firstImage == nil {
                firstImage = media.uiImage
            }

            newAssets.append(
                media.asset.with(sortOrder: newAssets.count)
            )
        }

        selectedPhotoItems = []

        guard !newAssets.isEmpty else { return }
        draftMediaAssets = newAssets
        draftAnalysisImage = firstImage
        if newAssets.count == 1 {
            isPresentingAddBell = true
        } else {
            isPresentingBatchAdd = true
        }
    }

    @MainActor
    private func addCapturedPhotoAndPresentEditor(_ image: UIImage) async {
        guard canEditCollection else { return }
        guard let media = try? imageMediaBuilder.build(from: image) else { return }

        draftMediaAssets = [
            media.asset.with(sortOrder: 0)
        ]
        draftAnalysisImage = media.uiImage
        shouldPresentEditorAfterCamera = true
    }
}

private struct CollectionSharingStateLoaderView: View {
    let collection: CollectionSummary
    private let sharingService: any CollectionSharingService
    @State private var state = CollectionSharingState.privateState
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(
        collection: CollectionSummary,
        sharingService: any CollectionSharingService
    ) {
        self.collection = collection
        self.sharingService = sharingService
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView(String(localized: "collection.sharing.loading"))
            } else if errorMessage != nil {
                sharingLoadFailedView
            } else {
                CollectionSharingView(collection: collection, state: state, sharingService: sharingService) {
                    Task {
                        await loadSharingState()
                    }
                }
            }
        }
        .task(id: collection.id) {
            await loadSharingState()
        }
    }

    private var sharingLoadFailedView: some View {
        CatalogEmptyStateView(
            systemImage: "icloud.slash",
            title: LocalizedStringKey(String(localized: "collection.sharing.load_failed.title")),
            message: LocalizedStringKey(String(localized: "collection.sharing.load_failed.message")),
            primaryActionTitle: LocalizedStringKey(String(localized: "common.retry")),
            primaryAction: {
                Task {
                    await loadSharingState()
                }
            }
        )
    }

    @MainActor
    private func loadSharingState() async {
        isLoading = true
        errorMessage = nil

        do {
            state = try await sharingService.sharingState(for: collection.id)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

private extension CollectionSharingState {
    static let privateState = CollectionSharingState(
        currentUserRole: .owner,
        participants: []
    )
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
    let itemCount = snapshot.bellRecords.filter { $0.item.collectionID == collection.id }.count
    let summary = CollectionSummary(
        id: collection.id,
        homeID: collection.homeID,
        kind: collection.kind,
        name: collection.title,
        subtitle: collection.notes,
        backgroundStyle: collection.backgroundStyle,
        itemCount: itemCount,
        status: .active,
        sharingSummary: "Invitation-only. Members join with Apple ID and receive a role inside the collection."
    )

    NavigationStack {
        BellCollectionView(
            collection: summary,
            catalogSnapshot: snapshot,
            repository: repository,
            coreDataContainer: container,
            layoutMode: .constant(.mini)
        )
        .environment(\.managedObjectContext, container.viewContext)
    }
}
#endif
