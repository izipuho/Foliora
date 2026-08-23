import SwiftUI
import CloudKit

/// Displays the collections view interface.
struct CollectionsView: View {
    let repository: any CatalogRepository
    let catalogSnapshot: CatalogSnapshot?
    let onCollectionSelected: ((UUID) -> Void)?
    let navigate: ((AppDestination) -> Void)?
    let onOpenHomes: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var collectionSharingStatuses: [UUID: CollectionCardSharingStatus] = [:]
    @State private var collectionBackgroundBellIDs: [UUID: UUID] = [:]
    @State private var isPresentingAddCollectionEditor = false
    @State private var didAutoOpenSingleCollection = false
    @State private var collectionIDPendingDeletion: UUID?
    @State private var collectionPendingSharing: CollectionSummary?
    @State private var collectionPendingEdit: CollectionSummary?
    @State private var isSortingCollections = false
    @State private var sortingCollections: [CollectionSummary] = []

    init(
        repository: any CatalogRepository,
        catalogSnapshot: CatalogSnapshot?,
        onCollectionSelected: ((UUID) -> Void)? = nil,
        navigate: ((AppDestination) -> Void)? = nil,
        onOpenHomes: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.catalogSnapshot = catalogSnapshot
        self.onCollectionSelected = onCollectionSelected
        self.navigate = navigate
        self.onOpenHomes = onOpenHomes
    }

    private var collections: [CollectionSummary] {
        catalogSnapshot?.collections.compactMap { collection in
            catalogSnapshot?.collectionSummary(id: collection.id)
        } ?? []
    }

    private var displayedCollections: [CollectionSummary] {
        isSortingCollections ? sortingCollections : collections
    }

    private var homes: [Home] {
        catalogSnapshot?.homes.filter { !$0.isShared } ?? []
    }

    private var backgroundCandidateIDs: [UUID] {
        catalogSnapshot?.bells
            .filter {
                $0.isFavorite
                    && ($0.coverPhotoIdentifier != nil || $0.coverPhotoOriginalData != nil)
            }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString } ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            collectionsRoot
        }
            .background {
                CatalogBackgrounds.app(scheme: colorScheme)
                    .ignoresSafeArea()
            }
            .onAppear {
                autoOpenSingleCollectionIfNeeded()
                refreshCollectionBackgroundBells()
            }
            .task(id: collections.map(\.id)) {
                await loadCollectionSharingStatuses(for: collections.map(\.id))
            }
            .onChange(of: collections.map(\.id)) { _, _ in
                autoOpenSingleCollectionIfNeeded()
                refreshCollectionBackgroundBells()
            }
            .onChange(of: backgroundCandidateIDs) { _, _ in
                refreshCollectionBackgroundBells()
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
            .sheet(item: $collectionPendingSharing) { collection in
                NavigationStack {
                    CollectionSharingSheetLoaderView(collection: collection) {
                        Task {
                            await loadCollectionSharingStatuses(for: collections.map(\.id))
                        }
                    }
                }
            }
            .sheet(item: $collectionPendingEdit) { collection in
                CollectionEditorView(
                    homes: homes,
                    screenTitle: String(localized: "collection.editor.edit_title"),
                    initialTitle: collection.name,
                    initialNotes: collection.subtitle,
                    initialHomeID: collection.homeID,
                    initialBackgroundStyle: collection.backgroundStyle
                ) { title, notes, homeID, backgroundStyle in
                    saveCollectionEdits(
                        collection,
                        title: title,
                        notes: notes,
                        homeID: homeID,
                        backgroundStyle: backgroundStyle
                    )
                }
            }
            .alert(
                Text(deleteConfirmationTitle(for: collectionIDPendingDeletion)),
                isPresented: Binding(
                    get: { collectionIDPendingDeletion != nil },
                    set: { isPresented in
                        if !isPresented {
                            collectionIDPendingDeletion = nil
                        }
                    }
                )
            ) {
                if let collectionID = collectionIDPendingDeletion {
                    let action = deleteActionPresentation(for: collectionID)

                    Button(action.title, role: .destructive) {
                        guard let collectionID = collectionIDPendingDeletion else { return }
                        deleteCollection(collectionID)
                        collectionIDPendingDeletion = nil
                    }
                }

                Button("common.cancel", role: .cancel) {
                    collectionIDPendingDeletion = nil
                }
            } message: {
                if let collectionID = collectionIDPendingDeletion {
                    Text(deleteConfirmationMessage(for: collectionID))
                }
            }
    }

    private func deleteConfirmationTitle(for collectionID: UUID?) -> String {
        switch collectionID.map(repository.deleteResolution(for:)) {
        case .deletePrivateCollection:
            return String(localized: "collection.delete_private.title")
        case .deleteSharedCollectionAsOwner:
            return String(localized: "collection.delete_shared_owner.title")
        case .leaveSharedCollectionAsParticipant:
            return String(localized: "collection.leave_shared.title")
        case nil:
            return ""
        }
    }

    @ViewBuilder
    private var collectionsRoot: some View {
        if collections.isEmpty {
            emptyCollectionsView
        } else {
            CatalogContainerList {
                Section {
                    ForEach(displayedCollections) { collection in
                        collectionRow(for: collection)
                    }
                    .onMove(perform: moveCollections)
                }
            }
            .environment(\.editMode, .constant(isSortingCollections ? .active : .inactive))
            .contentMargins(.horizontal, nil, for: .scrollContent)
            .contentMargins(.top, nil, for: .scrollContent)
            .contentMargins(.bottom, 120, for: .scrollContent)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if isSortingCollections {
                            stopSortingCollections()
                        } else {
                            startSortingCollections()
                        }
                    } label: {
                        if isSortingCollections {
                            Image(systemName: "checkmark")
                        } else {
                            Image(systemName: "line.3.horizontal.decrease")
                        }
                    }
                }

                if !isSortingCollections {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            presentAddCollectionEditor()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func collectionRow(for collection: CollectionSummary) -> some View {
        if isSortingCollections {
            CollectionCard(
                collection: collection,
                sharingStatus: sharingStatus(for: collection.id),
                backgroundBell: backgroundBell(for: collection.id)
            )
            .catalogContainerListRow()
        } else {
            Button {
                selectCollection(collection)
            } label: {
                CollectionCard(
                    collection: collection,
                    sharingStatus: sharingStatus(for: collection.id),
                    backgroundBell: backgroundBell(for: collection.id)
                )
            }
            .buttonStyle(.plain)
            .catalogContainerListRow()
            .swipeActions {
                Button(role: .destructive) {
                    collectionIDPendingDeletion = collection.id
                } label: {
                    let action = deleteActionPresentation(for: collection.id)
                    Label(action.title, systemImage: action.systemImage)
                }

                if canManageCollection(collection.id) {
                    Button {
                        collectionPendingEdit = collection
                    } label: {
                        Label(String(localized: "common.edit"), systemImage: "pencil")
                    }
                    .tint(CatalogSemanticColors.info)
                }

                if canManageCollection(collection.id) {
                    Button {
                        collectionPendingSharing = collection
                    } label: {
                        Label(String(localized: "collection.sharing.swipe_action"), systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func backgroundCandidates(for collectionID: UUID) -> [BellListItem] {
        catalogSnapshot?.bells.filter {
            $0.collectionID == collectionID
                && $0.isFavorite
                && ($0.coverPhotoIdentifier != nil || $0.coverPhotoOriginalData != nil)
        } ?? []
    }

    private func backgroundBell(for collectionID: UUID) -> BellListItem? {
        let candidates = backgroundCandidates(for: collectionID)
        guard !candidates.isEmpty else { return nil }

        if let selectedID = collectionBackgroundBellIDs[collectionID],
           let selectedBell = candidates.first(where: { $0.id == selectedID }) {
            return selectedBell
        }

        return candidates.first
    }

    private func refreshCollectionBackgroundBells() {
        var updatedIDs = collectionBackgroundBellIDs
        let collectionIDs = Set(collections.map(\.id))
        updatedIDs = updatedIDs.filter { collectionIDs.contains($0.key) }

        for collection in collections {
            let candidates = backgroundCandidates(for: collection.id)

            if let selectedID = updatedIDs[collection.id],
               candidates.contains(where: { $0.id == selectedID }) {
                continue
            }

            updatedIDs[collection.id] = candidates.randomElement()?.id
        }

        collectionBackgroundBellIDs = updatedIDs
    }

    @ViewBuilder
    private var emptyCollectionsView: some View {
        if homes.isEmpty {
            requiresHomeEmptyView
        } else {
            CatalogEmptyStateView(
                systemImage: "rectangle.stack.slash",
                title: "collections.empty.title",
                message: "collections.empty.description",
                primaryActionTitle: "collections.add",
                primaryActionSystemImage: "plus.circle.fill",
                primaryTint: Color(red: 0.53, green: 0.31, blue: 0.14),
                primaryAction: presentAddCollectionEditor
            )
        }
    }

    private var requiresHomeEmptyView: some View {
        CatalogEmptyStateView(
            systemImage: "house",
            title: LocalizedStringKey(String(localized: "collections.empty.requires_home.title")),
            message: LocalizedStringKey(String(localized: "collections.empty.requires_home.message")),
            primaryActionTitle: LocalizedStringKey(String(localized: "collections.empty.requires_home.action")),
            primaryActionSystemImage: "house.fill",
            primaryTint: Color(red: 0.20, green: 0.42, blue: 0.34),
            primaryAction: onOpenHomes
        )
    }

    private func presentAddCollectionEditor() {
        guard !homes.isEmpty else {
            onOpenHomes()
            return
        }
        isPresentingAddCollectionEditor = true
    }

    private func startSortingCollections() {
        sortingCollections = collections
        isSortingCollections = true
    }

    private func stopSortingCollections() {
        isSortingCollections = false
        sortingCollections = []
    }

    private func moveCollections(from source: IndexSet, to destination: Int) {
        guard isSortingCollections else { return }

        sortingCollections.move(fromOffsets: source, toOffset: destination)
        repository.saveUserSortOrder(itemIDs: sortingCollections.map(\.id), scope: "Collection")
    }

    private func addCollection(title: String, notes: String, homeID: UUID, backgroundStyle: CollectionBackgroundStyle) {
        guard !homes.isEmpty else {
            onOpenHomes()
            return
        }

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
        navigate?(.collection(collection.id))
    }

    private func selectCollection(_ collection: CollectionSummary) {
        if let onCollectionSelected {
            onCollectionSelected(collection.id)
            return
        }

        navigate?(.collection(collection.id))
    }

    private func deleteCollection(_ collectionID: UUID) {
        repository.deleteCollection(collectionID: collectionID)
    }

    private func canManageCollection(_ collectionID: UUID) -> Bool {
        switch repository.deleteResolution(for: collectionID) {
        case .deletePrivateCollection, .deleteSharedCollectionAsOwner:
            return true
        case .leaveSharedCollectionAsParticipant:
            return false
        }
    }

    private func deleteActionPresentation(for collectionID: UUID) -> CollectionDeleteActionPresentation {
        switch repository.deleteResolution(for: collectionID) {
        case .deletePrivateCollection, .deleteSharedCollectionAsOwner:
            return CollectionDeleteActionPresentation(
                title: String(localized: "common.delete"),
                systemImage: "trash"
            )
        case .leaveSharedCollectionAsParticipant:
            return CollectionDeleteActionPresentation(
                title: String(localized: "collection.leave"),
                systemImage: "icloud.slash"
            )
        }
    }

    private func saveCollectionEdits(
        _ collection: CollectionSummary,
        title: String,
        notes: String,
        homeID: UUID,
        backgroundStyle: CollectionBackgroundStyle
    ) {
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

    private func deleteConfirmationMessage(for collectionID: UUID) -> String {
        switch repository.deleteResolution(for: collectionID) {
        case .deletePrivateCollection:
            return String(localized: "collection.delete_private.message")
        case .deleteSharedCollectionAsOwner:
            return String(localized: "collection.delete_shared_owner.message")
        case .leaveSharedCollectionAsParticipant:
            return String(localized: "collection.leave_shared.message")
        }
    }

    private func autoOpenSingleCollectionIfNeeded() {
        guard onCollectionSelected == nil else { return }
        guard !didAutoOpenSingleCollection else { return }
        guard collections.count == 1 else { return }
        guard let collection = collections.first else { return }

        didAutoOpenSingleCollection = true
        navigate?(.collection(collection.id))
    }

    private func sharingStatus(for collectionID: UUID) -> CollectionCardSharingStatus {
        collectionSharingStatuses[collectionID] ?? .unknown
    }

    @MainActor
    private func loadCollectionSharingStatuses(for collectionIDs: [UUID]) async {
        guard let persistentContainer = FolioraAppDelegate.coreDataContainer else {
            collectionSharingStatuses = Dictionary(
                uniqueKeysWithValues: collectionIDs.map { ($0, .privateOwner) }
            )
            return
        }

        let sharingService = CloudKitCollectionSharingService(persistentContainer: persistentContainer)
        var statuses: [UUID: CollectionCardSharingStatus] = [:]

        for collectionID in collectionIDs {
            do {
                let state = try await sharingService.sharingState(for: collectionID)
                statuses[collectionID] = collectionSharingStatus(from: state)
            } catch {
                statuses[collectionID] = .unknown
            }
        }

        collectionSharingStatuses = statuses
    }

    private func collectionSharingStatus(from state: CollectionSharingState) -> CollectionCardSharingStatus {
        switch state.currentUserRole {
        case .owner:
            if state.isShared {
                return .sharedOwner(participantsCount: state.acceptedParticipantsCount)
            }
            return .privateOwner
        case .contributor:
            return .sharedContributor
        case .viewer:
            return .sharedViewer
        }
    }
}

private struct CollectionDeleteActionPresentation {
    let title: String
    let systemImage: String
}

private struct CollectionSharingSheetLoaderView: View {
    let collection: CollectionSummary
    let onSharingChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var state = CollectionSharingState.placeholder
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView(String(localized: "collection.sharing.loading"))
            } else if errorMessage != nil {
                sharingLoadFailedView
            } else if let sharingService {
                CollectionSharingView(collection: collection, state: state, sharingService: sharingService) {
                    onSharingChanged()
                    Task {
                        await loadSharingState()
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
            }
        }
        .task(id: collection.id) {
            await loadSharingState()
        }
    }

    private var sharingService: CloudKitCollectionSharingService? {
        guard let persistentContainer = FolioraAppDelegate.coreDataContainer else {
            return nil
        }

        return CloudKitCollectionSharingService(persistentContainer: persistentContainer)
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
        guard let sharingService else {
            errorMessage = String(localized: "collection.sharing.load_failed.message")
            isLoading = false
            return
        }

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

private enum CollectionCardSharingStatus {
    case privateOwner
    case sharedOwner(participantsCount: Int)
    case sharedContributor
    case sharedViewer
    case unknown
}

#if DEBUG
#Preview {
    let container = PreviewContainer.make(.minimal)
    let repository = CoreDataCatalogRepository(
        context: container.viewContext,
        persistentContainer: nil
    )
    let catalogSnapshot = CatalogSnapshot.load(from: container.viewContext)

    NavigationStack {
        CollectionsView(
            repository: repository,
            catalogSnapshot: catalogSnapshot
        )
    }
}
#endif

private struct CollectionCard: View {
    let collection: CollectionSummary
    let sharingStatus: CollectionCardSharingStatus
    let backgroundBell: BellListItem?

    var body: some View {
        HStack(alignment: .center, spacing: CatalogMetrics.Spacing.md) {
            leading

            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
                Text(collection.name)
                    .font(CatalogTypography.cardTitle)
                    .lineLimit(2)

                Text(collection.kind.countLabel(for: collection.itemCount))
                    .font(CatalogTypography.cardSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: CatalogMetrics.Spacing.md)

            trailingAccessory
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .contentShape(Rectangle())
        .padding(CatalogMetrics.Spacing.lg)
        .background {
            if let backgroundBell {
                CollectionPhotoBackground(bell: backgroundBell)
                    .clipShape(CatalogShapes.section)
            }
        }
        .glassEffect(.regular.interactive(), in: CatalogShapes.section)
    }

    private var leading: some View {
        let accentColor = collection.backgroundStyle.accentColor

        return ZStack {
            RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.medium, style: .continuous)
                .fill(accentColor.opacity(0.16))
                .frame(width: 60, height: 60)

            Image(systemName: collection.kind.systemImage)
                .font(.system(size: 30))
                .foregroundStyle(accentColor)
        }
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        switch sharingStatus {
        case .privateOwner, .unknown:
            EmptyView()
        case .sharedOwner(let participantsCount):
            Label("\(participantsCount)", systemImage: "person.2.fill")
                .font(.title2)
        case .sharedContributor:
            Label("collection.sharing.role.contributor", systemImage: "person.crop.circle.badge.checkmark")
                .labelStyle(.iconOnly)
                .font(.title2)
        case .sharedViewer:
            Label("collection.sharing.role.viewer", systemImage: "eye.fill")
                .labelStyle(.iconOnly)
                .font(.title2)
        }
    }
}

private struct CollectionPhotoBackground: View {
    let bell: BellListItem

    var body: some View {
        GeometryReader { proxy in
            let photoWidth = proxy.size.width * 0.62
            let photoSize = CGSize(width: photoWidth, height: proxy.size.height)

            MediaPreviewImage(
                identifier: bell.coverPhotoIdentifier,
                originalData: bell.coverPhotoOriginalData,
                size: photoSize
            )
            .frame(width: photoWidth, height: proxy.size.height)
            .blur(radius: 1)
            .opacity(0.52)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: .black.opacity(0.12), location: 0.12),
                        .init(color: .black.opacity(0.72), location: 0.32),
                        .init(color: .black, location: 0.48)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .allowsHitTesting(false)
    }
}
