import SwiftUI
import SwiftData
import PhotosUI

struct CollectionShellView: View {
    let repository: any CatalogRepository
    private let onBellSelected: ((BellEntity) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CollectionEntity.title) private var collectionEntities: [CollectionEntity]
    @Query(sort: \HomeEntity.name) private var homeEntities: [HomeEntity]
    @Query private var membershipEntities: [MembershipEntity]
    @State private var collection: CollectionSummary
    @State private var refreshID = UUID()
    @State private var isPresentingAddBell = false
    @State private var isPresentingAddBellOptions = false
    @State private var isPresentingPhotoPicker = false
    @State private var isPresentingCamera = false
    @State private var shouldPresentEditorAfterCamera = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var draftMediaAssets: [MediaAsset] = []
    @State private var draftAnalysisImage: UIImage?
    @State private var isPresentingEditCollection = false
    @State private var isPresentingMap = false
    @State private var selectedBell: BellEntity?
    @AppStorage("bellCatalog.orderMode") private var selectedOrderRawValue = BellOrderMode.newestFirst.rawValue
    private let layoutMode: Binding<BellGridLayoutMode>
    @State private var selectedSummaryFilter = BellFilters()
    @State private var isBellCatalogSelectionMode = false
    private let imageMediaBuilder = ImageMediaBuilder(store: .shared)

    init(
        collection: CollectionSummary,
        repository: any CatalogRepository,
        layoutMode: Binding<BellGridLayoutMode>,
        onBellSelected: ((BellEntity) -> Void)? = nil
    ) {
        self.repository = repository
        self.onBellSelected = onBellSelected
        self.layoutMode = layoutMode
        _collection = State(initialValue: collection)
    }

    private var homes: [Home] {
        homeEntities.map(\.homeSnapshot)
    }

    private var collaborators: [Collaborator] {
        membershipEntities
            .filter { $0.collection?.id == collection.id && $0.status == .active }
            .map { membership in
                Collaborator(
                    id: membership.id,
                    displayName: membership.userID == "me" ? "Вы" : membership.userID,
                    role: membership.role,
                    isCurrentUser: membership.userID == "me"
                )
            }
    }

    private var hasPlacedItems: Bool {
        (collectionEntities
            .first { $0.id == collection.id }?
            .bells ?? [])
            .contains { $0.location != nil }
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
                maxSelectionCount: 1,
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
            .sheet(isPresented: $isPresentingEditCollection) {
                editCollectionSheet
            }
            .sheet(isPresented: $isPresentingMap) {
                mapSheet
            }
            .sheet(item: $selectedBell) { bell in
                BellEntityDetailSheetContainer(bell: bell, repository: repository)
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: collectionEntities.map(\.id)) { _, _ in
                refreshContent()
            }
    }

    private var content: some View {
        BellCatalogView(
            collection: collection,
            repository: repository,
            collaborators: collaborators,
            layoutMode: selectedLayoutModeBinding,
            orderMode: selectedOrderBinding,
            filters: $selectedSummaryFilter,
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

    private var editCollectionSheet: some View {
        CollectionEditorView(
            homes: homes,
            screenTitle: String(localized: "collection.editor.edit_title"),
            initialTitle: collection.name,
            initialNotes: collection.subtitle,
            initialHomeID: collection.homeID,
            initialBackgroundStyle: collection.backgroundStyle,
            hasPlacedItems: hasPlacedItems,
            allowsDeletion: true
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
        collection = collectionEntities.first(where: { $0.id == collection.id })?.summarySnapshot ?? collection
        refreshID = UUID()
    }

    private func openBell(_ bell: BellEntity) {
        if let onBellSelected {
            onBellSelected(bell)
        } else {
            selectedBell = bell
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
        isPresentingAddBell = true
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
