import SwiftUI
import CoreData
import CloudKit

struct CollectionsView: View {
    let repository: any CatalogRepository
    let onCollectionSelected: ((UUID) -> Void)?
    let onBellSelected: ((UUID) -> Void)?
    let navigate: ((AppDestination) -> Void)?
    let onOpenHomes: () -> Void
    @Environment(\.managedObjectContext) private var managedObjectContext
    @State private var catalogSnapshot = CollectionsCatalogSnapshot()
    @State private var isPresentingAddCollectionEditor = false
    @State private var didAutoOpenSingleCollection = false
    @State private var isPresentingDeleteConfirmation = false
    @State private var collectionIDPendingDeletion: UUID?

    init(
        repository: any CatalogRepository,
        onCollectionSelected: ((UUID) -> Void)? = nil,
        onBellSelected: ((UUID) -> Void)? = nil,
        navigate: ((AppDestination) -> Void)? = nil,
        onOpenHomes: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.onCollectionSelected = onCollectionSelected
        self.onBellSelected = onBellSelected
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
                                deleteActionLabel(for: collection.id)
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

    private func deleteActionLabel(for collectionID: UUID) -> some View {
        let action = deleteActionPresentation(for: collectionID)
        return Label(action.title, systemImage: action.systemImage)
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
                    Self.collectionSharingStatus(from: sharesByObjectID[entity.objectID])
                )
            }
        )
    }

    func sharingStatus(for collectionID: UUID) -> CollectionCardSharingStatus {
        collectionSharingStatuses[collectionID] ?? .privateCollection
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

    private static func sharesByObjectID(for entities: [NSManagedObject]) -> [NSManagedObjectID: CKShare] {
        guard
            let persistentContainer = FolioraAppDelegate.coreDataContainer,
            !entities.isEmpty
        else {
            return [:]
        }

        return (try? persistentContainer.fetchShares(matching: entities.map(\.objectID))) ?? [:]
    }

    private static func collectionSharingStatus(from share: CKShare?) -> CollectionCardSharingStatus {
        guard let share else {
            return .privateCollection
        }

        let participantsCount = acceptedParticipantsCount(in: share)

        if participantsCount == 1, share.currentUserParticipant?.role == .owner {
            return .privateCollection
        }

        if share.currentUserParticipant?.role == .owner {
            return .sharedOwner(participantsCount: participantsCount)
        }

        return .sharedParticipant
    }

    private static func acceptedParticipantsCount(in share: CKShare) -> Int {
        share.participants.filter {
            $0.role == .owner || $0.acceptanceStatus == .accepted
        }.count
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
    case privateCollection
    case sharedOwner(participantsCount: Int)
    case sharedParticipant
}

private struct CollectionCard: View {
    let collection: CollectionSummary
    let sharingStatus: CollectionCardSharingStatus

    private var detailLines: [String] {
        [collection.kind.countLabel(for: collection.itemCount)]
    }

    private var subtitleTrailing: String? {
        switch sharingStatus {
        case .privateCollection:
            return nil
        case .sharedOwner(let participantsCount):
            return "\(participantsCount)"
        case .sharedParticipant:
            return nil
        }
    }

    private var subtitleTrailingIcon: String? {
        switch sharingStatus {
        case .privateCollection:
            return nil
        case .sharedOwner:
            return "person.2"
        case .sharedParticipant:
            return "link"
        }
    }

    var body: some View {
        CatalogContainerCard(
            title: collection.name,
            subtitle: collection.kind.countLabel(for: collection.itemCount),
            subtitleTrailing: subtitleTrailing,
            subtitleTrailingIcon: subtitleTrailingIcon,
            systemImage: collection.kind.systemImage
        )
    }
}
