import SwiftUI
import SwiftData
import PhotosUI

private struct CollectionShellView: View {
    let repository: any CatalogRepository
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
    @State private var selectedOrder: BellOrderMode = .newestFirst
    @State private var selectedLayoutMode: BellGridLayoutMode = .mini
    @State private var selectedSummaryFilter = BellFilters()
    private let imageMediaBuilder = ImageMediaBuilder(store: .shared)

    init(collection: CollectionSummary, repository: any CatalogRepository) {
        self.repository = repository
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

    var body: some View {
        content
            .toolbar { collectionToolbar }
            .overlay(alignment: .bottomTrailing) { mapButton }
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
            .onChange(of: collectionEntities.map(\.id)) { _, _ in
                refreshContent()
            }
    }

    private var content: some View {
        BellCatalogView(
            collection: collection,
            repository: repository,
            collaborators: collaborators,
            layoutMode: $selectedLayoutMode,
            orderMode: $selectedOrder,
            filters: $selectedSummaryFilter
        )
        .id("collection-\(refreshID.uuidString)")
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    @ToolbarContentBuilder
    private var collectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isPresentingEditCollection = true
            } label: {
                floatingToolbarIcon(systemName: "square.and.pencil")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker(String(localized: "bell_catalog.order.menu"), selection: $selectedOrder) {
                    ForEach(BellOrderMode.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                floatingToolbarIcon(systemName: "line.3.horizontal.decrease")
            }
        }

        addBellToolbarItem
    }

    private var mapButton: some View {
        Button {
            isPresentingMap = true
        } label: {
            Image(systemName: "map.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(20)
                .background(.bar, in: Circle())
                .shadow(color: .black.opacity(0.05), radius: 8)
        }
        .buttonStyle(.plain)
        .padding(.trailing, CatalogLayoutInsets.screen)
        .padding(.bottom, 16)
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
            allowsHomeSelection: false,
            allowsDeletion: true
        ) { title, notes, _, backgroundStyle in
            saveCollectionEdits(title: title, notes: notes, backgroundStyle: backgroundStyle)
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

    @ToolbarContentBuilder
    private var addBellToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isPresentingAddBellOptions = true
            } label: {
                floatingToolbarIcon(systemName: "plus")
            }
            .confirmationDialog(String(localized: "editor.media.add"), isPresented: $isPresentingAddBellOptions, titleVisibility: .visible) {
                Button(String(localized: "editor.media.photo_library")) {
                    isPresentingPhotoPicker = true
                }

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button(String(localized: "editor.media.camera")) {
                        isPresentingCamera = true
                    }
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

    private func clearDraftBell() {
        draftMediaAssets = []
        draftAnalysisImage = nil
    }

    private func saveCollectionEdits(title: String, notes: String, backgroundStyle: CollectionBackgroundStyle) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedCollection = Collection(
            id: collection.id,
            homeID: collection.homeID,
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

    @MainActor
    private func addDraftPhotosAndPresentEditor(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        var newAssets: [MediaAsset] = []
        var firstImage: UIImage?

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            guard let image = UIImage(data: data) else { continue }
            guard let media = try? await imageMediaBuilder.build(from: image) else { continue }

            if firstImage == nil {
                firstImage = media.uiImage
            }

            newAssets.append(
                MediaAsset(
                    id: media.asset.id,
                    itemID: media.asset.itemID,
                    kind: media.asset.kind,
                    localIdentifier: media.asset.localIdentifier,
                    displayName: media.asset.displayName,
                    sortOrder: newAssets.count
                )
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
        guard let media = try? await imageMediaBuilder.build(from: image) else { return }

        draftMediaAssets = [
            MediaAsset(
                id: media.asset.id,
                itemID: media.asset.itemID,
                kind: media.asset.kind,
                localIdentifier: media.asset.localIdentifier,
                displayName: media.asset.displayName,
                sortOrder: 0
            )
        ]
        draftAnalysisImage = media.uiImage
        shouldPresentEditorAfterCamera = true
    }
}

struct CollectionsView: View {
    let repository: any CatalogRepository
    @Query(sort: \CollectionEntity.title) private var collectionEntities: [CollectionEntity]
    @Query(sort: \HomeEntity.name) private var homeEntities: [HomeEntity]
    @Query private var membershipEntities: [MembershipEntity]
    @State private var path: [AppDestination] = []
    @State private var isPresentingAddCollectionEditor = false
    @State private var didAutoOpenSingleCollection = false

    init(repository: any CatalogRepository) {
        self.repository = repository
    }

    private var collections: [CollectionSummary] {
        collectionEntities.map(\.summarySnapshot)
    }

    private var homes: [Home] {
        homeEntities.map(\.homeSnapshot)
    }

    var body: some View {
        NavigationStack(path: $path) {
            collectionsRoot
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.99, green: 0.97, blue: 0.93),
                            Color(red: 0.94, green: 0.92, blue: 0.86)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                )
                .onAppear {
                    autoOpenSingleCollectionIfNeeded()
                }
                .onChange(of: collections.map(\.id)) { _, _ in
                    didAutoOpenSingleCollection = false
                    autoOpenSingleCollectionIfNeeded()
                }
                .navigationTitle(RootTab.collections.title)
                .sheet(isPresented: $isPresentingAddCollectionEditor) {
                    CollectionEditorView(
                        homes: homes,
                        initialHomeID: homes.first?.id
                    ) { title, notes, homeID, backgroundStyle in
                        addCollection(title: title, notes: notes, homeID: homeID, backgroundStyle: backgroundStyle)
                    }
                }
                .navigationDestination(for: AppDestination.self) { destination in
                    switch destination {
                    case .collection(let collection):
                        CollectionShellView(collection: collection, repository: repository)
                    case .home:
                        EmptyView()
                    }
                }
        }
    }

    @ViewBuilder
    private var collectionsRoot: some View {
        if collections.isEmpty {
            emptyCollectionsView
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(collections) { collection in
                        Button {
                            path.append(.collection(collection))
                        } label: {
                            CollectionCard(collection: collection)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.horizontal, nil, for: .scrollContent)
            .contentMargins(.top, nil, for: .scrollContent)
            .contentMargins(.bottom, 120, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingAddCollectionEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    private var emptyCollectionsView: some View {
        VStack(spacing: 24) {
            ContentUnavailableView(
                String(localized: "collections.empty.title"),
                systemImage: "square.grid.2x2",
                description: Text(String(localized: "collections.empty.description"))
            )
            .frame(maxWidth: .infinity)

            Button {
                isPresentingAddCollectionEditor = true
            } label: {
                Label(String(localized: "collections.add"), systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.53, green: 0.31, blue: 0.14))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal)
        .padding(.bottom, 80)
    }

    private func addCollection(title: String, notes: String, homeID: UUID, backgroundStyle: CollectionBackgroundStyle) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let collection = Collection(
            id: UUID(),
            homeID: homeID,
            kind: .bells,
            title: trimmedTitle.isEmpty ? String(localized: "collection.editor.default_title") : trimmedTitle,
            notes: trimmedNotes,
            backgroundStyle: backgroundStyle
        )

        repository.saveCollection(collection)
        didAutoOpenSingleCollection = true
        path.append(
            .collection(
                CollectionSummary(
                    id: collection.id,
                    homeID: collection.homeID,
                    kind: collection.kind,
                    name: collection.title,
                    subtitle: collection.notes,
                    backgroundStyle: collection.backgroundStyle,
                    itemCount: 0,
                    collaboratorCount: 0,
                    role: .owner,
                    status: .active,
                    sharingSummary: ""
                )
            )
        )
    }

    private func autoOpenSingleCollectionIfNeeded() {
        guard collections.count == 1 else { return }
        guard !didAutoOpenSingleCollection else { return }
        guard let collection = collections.first else { return }

        didAutoOpenSingleCollection = true
        path.append(.collection(collection))
    }
}
