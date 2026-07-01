import SwiftUI
import CoreData
import CloudKit

struct CollectionsView: View {
    let repository: any CatalogRepository
    let onCollectionSelected: ((UUID) -> Void)?
    let navigate: ((AppDestination) -> Void)?
    let onOpenHomes: () -> Void
    @Environment(\.managedObjectContext) private var managedObjectContext
    @State private var catalogSnapshot = CollectionsCatalogSnapshot()
    @State private var isPresentingAddCollectionEditor = false
    @State private var didAutoOpenSingleCollection = false
    @State private var isPresentingDeleteConfirmation = false
    @State private var collectionIDPendingDeletion: UUID?
    @State private var collectionPendingSharing: CollectionSummary?
    @State private var collectionPendingEdit: CollectionSummary?

    init(
        repository: any CatalogRepository,
        onCollectionSelected: ((UUID) -> Void)? = nil,
        navigate: ((AppDestination) -> Void)? = nil,
        onOpenHomes: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.onCollectionSelected = onCollectionSelected
        self.navigate = navigate
        self.onOpenHomes = onOpenHomes
    }

    private var collections: [CollectionSummary] {
        catalogSnapshot.collections
    }

    private var homes: [Home] {
        catalogSnapshot.homes
    }

    var body: some View {
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
                reloadCatalogSnapshot()
                autoOpenSingleCollectionIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .NSManagedObjectContextObjectsDidChange,
                object: managedObjectContext
            )) { _ in
                reloadCatalogSnapshot()
            }
            .onChange(of: collections.map(\.id)) { _, _ in
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
            .sheet(item: $collectionPendingSharing) { collection in
                NavigationStack {
                    CollectionSharingSheetLoaderView(collection: collection) {
                        reloadCatalogSnapshot()
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
            .confirmationDialog(
                Text(deleteConfirmationTitle(for: collectionIDPendingDeletion)),
                isPresented: $isPresentingDeleteConfirmation,
                titleVisibility: .visible,
                presenting: collectionIDPendingDeletion
            ) { collectionID in
                let action = deleteActionPresentation(for: collectionID)

                Button(action.title, role: .destructive) {
                    deleteCollection(collectionID)
                    collectionIDPendingDeletion = nil
                }

                Button("Cancel", role: .cancel) {
                    collectionIDPendingDeletion = nil
                }
            } message: { collectionID in
                Text(deleteConfirmationMessage(for: collectionID))
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
                    ForEach(collections) { collection in
                        Button {
                            selectCollection(collection)
                        } label: {
                            CollectionCard(
                                collection: collection,
                                sharingStatus: catalogSnapshot.sharingStatus(for: collection.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .catalogContainerListRow()
                        .swipeActions {
                            Button(role: .destructive) {
                                confirmDeleteCollection(collection.id)
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
                                .tint(.blue)
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
            }
            .contentMargins(.horizontal, nil, for: .scrollContent)
            .contentMargins(.top, nil, for: .scrollContent)
            .contentMargins(.bottom, 120, for: .scrollContent)
            .toolbar {
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

    @ViewBuilder
    private var emptyCollectionsView: some View {
        if homes.isEmpty {
            requiresHomeEmptyView
        } else {
            CatalogEmptyStateView(
                systemImage: "square.grid.2x2",
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
        reloadCatalogSnapshot()
        navigate?(
            .collection(
                CollectionSummary(
                    id: collection.id,
                    homeID: collection.homeID,
                    kind: collection.kind,
                    name: collection.title,
                    subtitle: collection.notes,
                    backgroundStyle: collection.backgroundStyle,
                    itemCount: 0,
                    status: .active,
                    sharingSummary: ""
                )
            )
        )
    }

    private func selectCollection(_ collection: CollectionSummary) {
        if let onCollectionSelected {
            onCollectionSelected(collection.id)
            return
        }

        navigate?(.collection(collection))
    }

    private func deleteCollection(_ collectionID: UUID) {
        repository.deleteCollection(collectionID: collectionID)
        reloadCatalogSnapshot()
    }

    private func confirmDeleteCollection(_ collectionID: UUID) {
        collectionIDPendingDeletion = collectionID
        isPresentingDeleteConfirmation = true
    }

    private func canManageCollection(_ collectionID: UUID) -> Bool {
        switch catalogSnapshot.sharingStatus(for: collectionID) {
        case .privateOwner, .sharedOwner:
            return true
        case .sharedParticipant, .unknown:
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
        reloadCatalogSnapshot()
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
        navigate?(.collection(collection))
    }

    private func reloadCatalogSnapshot() {
        catalogSnapshot = CollectionsCatalogSnapshot(context: managedObjectContext)
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

@MainActor
private struct CollectionsCatalogSnapshot {
    var collections: [CollectionSummary] = []
    var homes: [Home] = []
    private var collectionSharingStatuses: [UUID: CollectionCardSharingStatus] = [:]

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

        let sharesByObjectID = Self.sharesByObjectID(for: collectionEntities)

        collections = collectionEntities.map(Self.collectionSummary)
        homes = homeEntities.map(Self.home)
        collectionSharingStatuses = Dictionary(
            uniqueKeysWithValues: collectionEntities.map { entity in
                (
                    Self.uuidValue(entity, "id"),
                    Self.collectionSharingStatus(
                        from: sharesByObjectID[entity.objectID],
                        collectionID: Self.uuidValue(entity, "id")
                    )
                )
            }
        )
    }

    func sharingStatus(for collectionID: UUID) -> CollectionCardSharingStatus {
        collectionSharingStatuses[collectionID] ?? .unknown
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

    private static func sharesByObjectID(for entities: [NSManagedObject]) -> [NSManagedObjectID: CKShare?] {
        guard
            let persistentContainer = FolioraAppDelegate.coreDataContainer,
            !entities.isEmpty
        else {
            return Dictionary(uniqueKeysWithValues: entities.map { ($0.objectID, nil) })
        }

        do {
            return try persistentContainer.fetchShares(matching: entities.map(\.objectID))
                .mapValues { Optional($0) }
        } catch {
            return Dictionary(uniqueKeysWithValues: entities.map { ($0.objectID, nil) })
        }
    }

    private static func collectionSharingStatus(
        from shareLookup: CKShare??,
        collectionID: UUID
    ) -> CollectionCardSharingStatus {
        guard let shareLookup else {
            return .privateOwner
        }

        guard let share = shareLookup else {
            return .unknown
        }

        let currentUserParticipant = share.currentUserParticipant
        let participants = share.participants.map {
            CloudKitSharingMapper.collectionParticipant(
                from: $0,
                collectionID: collectionID,
                isCurrentUser: $0 == currentUserParticipant
            )
        }
        let currentUserRole = CloudKitSharingMapper.currentUserRole(from: participants)
        let state = CollectionSharingState(
            currentUserRole: currentUserRole,
            participants: participants
        )

        switch state.currentUserRole {
        case .owner:
            if state.isShared {
                return .sharedOwner(participantsCount: state.visibleParticipantsCount)
            }
            return .privateOwner
        case .contributor, .viewer:
            return .sharedParticipant
        }
    }

    private static func home(from entity: NSManagedObject) -> Home {
        Home(
            id: uuidValue(entity, "id"),
            name: stringValue(entity, "name"),
            iconName: stringValue(entity, "iconName", default: "house.fill"),
            notes: stringValue(entity, "notes")
        )
    }

    private static func collectionKind(from rawValue: String) -> CollectionKind {
        CollectionKind(rawValue: rawValue) ?? .bells
    }

    private static func collectionBackgroundStyle(from rawValue: String) -> CollectionBackgroundStyle {
        CollectionBackgroundStyle(rawValue: rawValue) ?? .amber
    }

    private static func relatedObjectCount(_ entity: NSManagedObject, _ key: String) -> Int {
        if let objects = entity.value(forKey: key) as? Set<NSManagedObject> {
            return objects.count
        }

        return (entity.value(forKey: key) as? NSSet)?.count ?? 0
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

private enum CollectionCardSharingStatus {
    case privateOwner
    case sharedOwner(participantsCount: Int)
    case sharedParticipant
    case unknown
}

private struct CollectionCard: View {
    let collection: CollectionSummary
    let sharingStatus: CollectionCardSharingStatus

    private var accessory: CatalogContainerCard.Accessory? {
        switch sharingStatus {
        case .privateOwner, .unknown:
            return nil
        case .sharedOwner(let participantsCount):
            return .label(text: "\(participantsCount)", systemImage: "person.2")
        case .sharedParticipant:
            return .icon("link")
        }
    }

    var body: some View {
        CatalogContainerCard(
            title: collection.name,
            subtitle: collection.kind.countLabel(for: collection.itemCount),
            accessory: accessory,
            systemImage: collection.kind.systemImage
        )
    }
}
