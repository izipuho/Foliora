import SwiftUI
import PhotosUI
import CoreData

struct CollectionShellView: View {
    let repository: any CatalogRepository
    let coreDataContainer: NSPersistentCloudKitContainer
    private let onBellSelected: ((UUID) -> Void)?
    private let onBatchAddComplete: (BatchAddCompletionAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext
    @State private var catalogSnapshot = CollectionShellCatalogSnapshot()
    @State private var collection: CollectionSummary
    @State private var refreshID = UUID()
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
    @State private var isPresentingMap = false
    @State private var selectedBellID: UUID?
    @State private var collectionSharingState: CollectionSharingState?
    @State private var collectionSharingLoadError: Error?
    @AppStorage("bellCatalog.orderMode") private var selectedOrderRawValue = BellOrderMode.newestFirst.rawValue
    private let layoutMode: Binding<BellGridLayoutMode>
    @State private var selectedSummaryFilter = BellFilters()
    @State private var isBellCatalogSelectionMode = false
    private let imageMediaBuilder = ImageMediaBuilder(store: .shared)

    init(
        collection: CollectionSummary,
        repository: any CatalogRepository,
        coreDataContainer: NSPersistentCloudKitContainer,
        layoutMode: Binding<BellGridLayoutMode>,
        onBellSelected: ((UUID) -> Void)? = nil,
        onBatchAddComplete: @escaping (BatchAddCompletionAction) -> Void = { _ in }
    ) {
        self.repository = repository
        self.coreDataContainer = coreDataContainer
        self.onBellSelected = onBellSelected
        self.onBatchAddComplete = onBatchAddComplete
        self.layoutMode = layoutMode
        _collection = State(initialValue: collection)
    }

    private var homes: [Home] {
        catalogSnapshot.homes
    }

    private var hasPlacedItems: Bool {
        catalogSnapshot.collectionIDsWithPlacedItems.contains(collection.id)
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

    private var selectedLayoutModeBinding: Binding<BellGridLayoutMode> {
        layoutMode
    }

    private var isBellDetailPresented: Binding<Bool> {
        Binding(
            get: { selectedBellID != nil },
            set: { isPresented in
                if !isPresented {
                    selectedBellID = nil
                }
            }
        )
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

    var body: some View {
        content
            .toolbar {
                if !isBellCatalogSelectionMode {
                    CollectionShellToolbar(
                        selectedOrder: selectedOrderBinding,
                        selectedLayoutMode: selectedLayoutModeBinding,
                        isPresentingAddBellOptions: $isPresentingAddBellOptions,
                        onEdit: {
                            isPresentingEditCollection = true
                        },
                        onOpenMap: {
                            isPresentingMap = true
                        },
                        onLibrary: {
                            isPresentingPhotoPicker = true
                        },
                        onCamera: {
                            isPresentingCamera = true
                        }
                    )
                }
            }
            .onPreferenceChange(BellCatalogSelectionModePreferenceKey.self) { isSelectionMode in
                isBellCatalogSelectionMode = isSelectionMode
            }
            .overlay(alignment: .bottomTrailing) {
                if !isBellCatalogSelectionMode {
                    CollectionMapButton {
                        isPresentingMap = true
                    }
                    .padding(.trailing, CatalogLayoutInsets.screen)
                    .padding(.bottom, 16)
                }
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
            .sheet(isPresented: $isPresentingMap) {
                mapSheet
            }
            .sheet(isPresented: isBellDetailPresented) {
                if let selectedBellID {
                    BellCatalogDetailSheetContainer(
                        bellID: selectedBellID,
                        repository: repository,
                        canEditCollection: canEditCollection
                    )
                        .presentationDragIndicator(.visible)
                }
            }
            .onAppear(perform: refreshContent)
            .task(id: collection.id) {
                await loadCollectionSharingState()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .NSManagedObjectContextObjectsDidChange,
                object: managedObjectContext
            )) { _ in
                refreshContent()
            }
    }

    private var content: some View {
        BellCatalogView(
            collection: collection,
            repository: repository,
            layoutMode: selectedLayoutModeBinding,
            orderMode: selectedOrderBinding,
            filters: $selectedSummaryFilter,
            canEditCollection: canEditCollection,
            onBellSelected: openBell
        )
        .id("collection-\(refreshID.uuidString)")
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var addBellSheet: some View {
        BellEditorView(
            collection: collection,
            repository: repository,
            initialMediaAssets: draftMediaAssets,
            initialAnalysisImage: draftAnalysisImage
        ) { newBell in
            repository.saveBellRecord(newBell)
            refreshContent()
        }
    }

    private var batchAddSheet: some View {
        BellBatchAddView(
            collection: collection,
            photoCount: draftMediaAssets.count,
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
            sharingDestination: AnyView(CollectionSharingStateLoaderView(
                collection: collection,
                sharingService: CloudKitCollectionSharingService(persistentContainer: coreDataContainer)
            ))
        ) { title, notes, homeID, backgroundStyle in
            saveCollectionEdits(title: title, notes: notes, homeID: homeID, backgroundStyle: backgroundStyle)
        } onDelete: {
            repository.deleteCollection(collectionID: collection.id)
            dismiss()
        }
    }

    private var mapSheet: some View {
        NavigationStack {
            CollectionOriginMapView(
                collection: collection,
                repository: repository
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) {
                        isPresentingMap = false
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
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
        refreshContent()
    }

    private func refreshContent() {
        let snapshot = CollectionShellCatalogSnapshot(context: managedObjectContext)
        catalogSnapshot = snapshot
        collection = snapshot.collections.first(where: { $0.id == collection.id }) ?? collection
        refreshID = UUID()
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
        refreshContent()

        if case .reviewResults = action {
            onBatchAddComplete(action)
        }
    }

    private func openBell(_ bellID: UUID) {
        if let onBellSelected {
            onBellSelected(bellID)
        } else {
            selectedBellID = bellID
        }
    }

    @MainActor
    private func addDraftPhotosAndPresentEditor(from items: [PhotosPickerItem]) async {
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
        guard let media = try? imageMediaBuilder.build(from: image) else { return }

        draftMediaAssets = [
            media.asset.with(sortOrder: 0)
        ]
        draftAnalysisImage = media.uiImage
        shouldPresentEditorAfterCamera = true
    }
}

private struct CollectionShellCatalogSnapshot {
    var collections: [CollectionSummary] = []
    var homes: [Home] = []
    var collectionIDsWithPlacedItems: Set<UUID> = []

    init() {}

    init(context: NSManagedObjectContext) {
        let collectionEntities = Self.fetchEntities(
            named: "CollectionEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "title", ascending: true)]
        )
        let homeEntities = Self.fetchEntities(
            named: "HomeEntity",
            in: context,
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
        )

        collections = collectionEntities.map(Self.collectionSummary)
        homes = homeEntities.map(Self.home)
        collectionIDsWithPlacedItems = Set(collectionEntities.compactMap(Self.collectionIDWithPlacedItems))
    }

    private static func fetchEntities(
        named entityName: String,
        in context: NSManagedObjectContext,
        sortDescriptors: [NSSortDescriptor]
    ) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.sortDescriptors = sortDescriptors
        return (try? context.fetch(request)) ?? []
    }

    private static func collectionSummary(from entity: NSManagedObject) -> CollectionSummary {
        let kind = collectionKind(from: stringValue(entity, "kindRaw", default: CollectionKind.bells.rawValue))

        return CollectionSummary(
            id: uuidValue(entity, "id"),
            homeID: collectionHomeID(from: entity),
            kind: kind,
            name: stringValue(entity, "title"),
            subtitle: stringValue(entity, "notes"),
            backgroundStyle: collectionBackgroundStyle(from: stringValue(entity, "backgroundStyleRaw", default: CollectionBackgroundStyle.amber.rawValue)),
            itemCount: kind == .bells ? relatedObjectCount(entity, "bells") : 0,
            status: kind == .bells ? .active : .planned,
            sharingSummary: "Invitation-only. Members join with Apple ID and receive a role inside the collection."
        )
    }

    private static func home(from entity: NSManagedObject) -> Home {
        Home(
            id: uuidValue(entity, "id"),
            name: stringValue(entity, "name"),
            iconName: stringValue(entity, "iconName", default: "house.fill"),
            notes: stringValue(entity, "notes")
        )
    }

    private static func collectionIDWithPlacedItems(from entity: NSManagedObject) -> UUID? {
        guard relatedObjects(entity, "bells").contains(where: { $0.value(forKey: "location") != nil }) else {
            return nil
        }

        return uuidValue(entity, "id")
    }

    private static func collectionKind(from rawValue: String) -> CollectionKind {
        CollectionKind(rawValue: rawValue) ?? .bells
    }

    private static func collectionBackgroundStyle(from rawValue: String) -> CollectionBackgroundStyle {
        CollectionBackgroundStyle(rawValue: rawValue) ?? .amber
    }

    private static func relatedObjectCount(_ entity: NSManagedObject, _ key: String) -> Int {
        relatedObjects(entity, key).count
    }

    private static func relatedObjects(_ entity: NSManagedObject, _ key: String) -> [NSManagedObject] {
        if let objects = entity.value(forKey: key) as? Set<NSManagedObject> {
            return Array(objects)
        }

        return (entity.value(forKey: key) as? NSSet)?.allObjects.compactMap { $0 as? NSManagedObject } ?? []
    }

    private static func uuidValue(_ entity: NSManagedObject, _ key: String) -> UUID {
        entity.value(forKey: key) as? UUID ?? UUID()
    }

    private static func collectionHomeID(from entity: NSManagedObject) -> UUID {
        (entity.value(forKey: "home") as? NSManagedObject).map { uuidValue($0, "id") }
            ?? entity.value(forKey: "homeID") as? UUID
            ?? UUID()
    }

    private static func stringValue(_ entity: NSManagedObject, _ key: String, default defaultValue: String = "") -> String {
        entity.value(forKey: key) as? String ?? defaultValue
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
        ContentUnavailableView {
            Label(String(localized: "collection.sharing.load_failed.title"), systemImage: "icloud.slash")
        } description: {
            Text(String(localized: "collection.sharing.load_failed.message"))
        } actions: {
            Button(String(localized: "common.retry")) {
                Task {
                    await loadSharingState()
                }
            }
        }
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
        isShared: false,
        currentUserRole: .owner,
        participants: []
    )
}

private struct CollectionShellToolbar: ToolbarContent {
    @Binding var selectedOrder: BellOrderMode
    @Binding var selectedLayoutMode: BellGridLayoutMode
    @Binding var isPresentingAddBellOptions: Bool
    let onEdit: () -> Void
    let onOpenMap: () -> Void
    let onLibrary: () -> Void
    let onCamera: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: onEdit) {
                floatingToolbarIcon(systemName: "square.and.pencil")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section(String(localized: "bell_catalog.sort.menu")) {
                    Button {
                        selectedOrder = .newestFirst
                    } label: {
                        if selectedOrder == .newestFirst {
                            Label(String(localized: "bell_catalog.sort.recently_added"), systemImage: "checkmark")
                        } else {
                            Text(String(localized: "bell_catalog.sort.recently_added"))
                        }
                    }

                    ForEach(listedOrderModes, id: \.self) { option in
                        Button {
                            selectedOrder = option
                        } label: {
                            if selectedOrder == option {
                                Label(String(localized: option.title), systemImage: "checkmark")
                            } else {
                                Text(String(localized: option.title))
                            }
                        }
                    }
                }

                Section(String(localized: "bell_catalog.layout.menu")) {
                    ControlGroup {
                        Button {
                            zoomOutLayout()
                        } label: {
                            Image(systemName: "minus")
                        }
                        .disabled(!canZoomOut)

                        Text(String(localized: selectedLayoutMode.title))

                        Button {
                            zoomInLayout()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(!canZoomIn)
                    } label: {
                        Label(String(localized: "bell_catalog.layout.menu"), systemImage: "square.grid.2x2")
                    }
                    .menuActionDismissBehavior(.disabled)
                }
            } label: {
                floatingToolbarIcon(systemName: "line.3.horizontal.decrease")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            AddBellMenu(
                isPresented: $isPresentingAddBellOptions,
                onCamera: onCamera,
                onLibrary: onLibrary
            )
        }
    }

    private var orderedLayoutModes: [BellGridLayoutMode] {
        [.covers, .mini, .compact, .wide, .showcase]
    }

    private var listedOrderModes: [BellOrderMode] {
        [.title, .geography, .acquisitionYear, .storage]
    }

    private var canZoomOut: Bool {
        guard let currentIndex = orderedLayoutModes.firstIndex(of: selectedLayoutMode) else { return false }
        return currentIndex > 0
    }

    private var canZoomIn: Bool {
        guard let currentIndex = orderedLayoutModes.firstIndex(of: selectedLayoutMode) else { return false }
        return currentIndex < orderedLayoutModes.count - 1
    }

    private func zoomOutLayout() {
        guard let currentIndex = orderedLayoutModes.firstIndex(of: selectedLayoutMode), currentIndex > 0 else {
            return
        }

        selectedLayoutMode = orderedLayoutModes[currentIndex - 1]
    }

    private func zoomInLayout() {
        guard let currentIndex = orderedLayoutModes.firstIndex(of: selectedLayoutMode), currentIndex < orderedLayoutModes.count - 1 else {
            return
        }

        selectedLayoutMode = orderedLayoutModes[currentIndex + 1]
    }
}

private extension BellGridLayoutMode {
    var title: LocalizedStringResource {
        switch self {
        case .covers:
            return "bell_catalog.layout.covers"
        case .mini:
            return "bell_catalog.layout.mini"
        case .compact:
            return "bell_catalog.layout.compact"
        case .wide:
            return "bell_catalog.layout.wide"
        case .showcase:
            return "bell_catalog.layout.showcase"
        }
    }
}

private struct CollectionMapButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "map.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(20)
                .background(.bar, in: Circle())
                .shadow(color: .black.opacity(0.05), radius: 8)
        }
        .buttonStyle(.plain)
    }
}

private struct AddBellMenu: View {
    @Binding var isPresented: Bool
    let onCamera: () -> Void
    let onLibrary: () -> Void

    var body: some View {
        Button {
            isPresented = true
        } label: {
            floatingToolbarIcon(systemName: "plus")
        }
        .confirmationDialog(String(localized: "editor.bell.add"), isPresented: $isPresented, titleVisibility: .visible) {
            Button(String(localized: "editor.media.photo_library"), action: onLibrary)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(String(localized: "editor.media.camera"), action: onCamera)
            }

            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
    }
}

private func floatingToolbarIcon(systemName: String) -> some View {
    Image(systemName: systemName)
        .font(.system(size: 17, weight: .semibold))
        .frame(width: 30, height: 30)
}
