import Foundation

final class LocalCatalogRepository: CatalogRepository {
    private let store: CatalogJSONStore
    private let mediaStore: LocalMediaFileStore

    init(
        baseURL: URL? = nil,
        seedRepository: any CatalogRepository = InMemoryCatalogRepository()
    ) {
        self.store = CatalogJSONStore(baseURL: baseURL)
        self.mediaStore = LocalMediaFileStore()
        store.bootstrapIfNeeded(using: seedRepository)
        removeHiddenCollectionsFromLocalStore()
    }

    func fetchHomes() -> [Home] {
        store.loadSnapshot().homes
    }

    func fetchLocations(in homeID: UUID) -> [Location] {
        store.loadSnapshot().locations.filter { $0.homeID == homeID }
    }

    func fetchDomainCollections(in homeID: UUID) -> [Collection] {
        store.loadSnapshot().collections.filter { $0.homeID == homeID }
    }

    func fetchMemberships(for collectionID: UUID) -> [Membership] {
        store.loadSnapshot().memberships.filter { $0.collectionID == collectionID }
    }

    func fetchCollections() -> [CollectionSummary] {
        let snapshot = store.loadSnapshot()

        return snapshot.collections.map { collection in
            let memberships = snapshot.memberships.filter { $0.collectionID == collection.id && $0.status == .active }

            return CollectionSummary(
                id: collection.id,
                kind: collection.kind,
                name: collection.title,
                subtitle: collection.notes,
                itemCount: collection.kind == .bells ? snapshot.bellItems.filter { $0.item.collectionID == collection.id }.count : 0,
                collaboratorCount: memberships.count,
                role: memberships.first(where: { $0.userID == "me" })?.role ?? .viewer,
                status: collection.kind == .bells ? .active : .planned,
                sharingSummary: "Invitation-only. Members join with Apple ID and receive a role inside the collection."
            )
        }
    }

    func fetchBellRecords(for collectionID: UUID) -> [BellRecord] {
        let snapshot = store.loadSnapshot()
        let placesByID = Dictionary(uniqueKeysWithValues: snapshot.places.map { ($0.id, $0) })
        let locationsByID = Dictionary(uniqueKeysWithValues: snapshot.locations.map { ($0.id, $0) })

        return snapshot.bellItems
            .filter { $0.item.collectionID == collectionID }
            .map { entry in
                let location = entry.item.locationID.flatMap { locationsByID[$0] }

                return BellRecord(
                    item: entry.item,
                    details: entry.details,
                    originPlace: entry.details.originPlaceID.flatMap { placesByID[$0] },
                    storageLocation: location,
                    storagePath: location.map { locationPath(for: $0, locationsByID: locationsByID) } ?? "Unassigned",
                    mediaAssets: entry.mediaAssets.sorted { $0.sortOrder < $1.sortOrder },
                    createdBy: entry.createdBy,
                    tags: entry.tags
                )
            }
    }

    func fetchCollaborators(for collectionID: UUID) -> [Collaborator] {
        let users = store.loadSnapshot().userDirectory

        return fetchMemberships(for: collectionID)
            .filter { $0.status == .active }
            .map { membership in
                Collaborator(
                    id: membership.id,
                    displayName: users[membership.userID] ?? membership.userID,
                    role: membership.role,
                    isCurrentUser: membership.userID == "me"
                )
            }
    }

    func saveHome(_ home: Home) {
        store.updateSnapshot { snapshot in
            if let index = snapshot.homes.firstIndex(where: { $0.id == home.id }) {
                snapshot.homes[index] = home
            } else {
                snapshot.homes.append(home)
            }
        }
    }

    func saveLocations(_ locations: [Location], in homeID: UUID) {
        store.updateSnapshot { snapshot in
            snapshot.locations.removeAll { $0.homeID == homeID }
            snapshot.locations.append(contentsOf: locations)
        }
    }

    func deleteHome(homeID: UUID) {
        store.updateSnapshot { snapshot in
            let collectionIDs = snapshot.collections
                .filter { $0.homeID == homeID }
                .map(\.id)
            let removedBellItems = snapshot.bellItems
                .filter { collectionIDs.contains($0.item.collectionID) }
            let itemIDs = removedBellItems.map(\.item.id)

            removedBellItems
                .flatMap(\.mediaAssets)
                .forEach { mediaStore.deleteFile(for: $0.localIdentifier) }

            snapshot.homes.removeAll { $0.id == homeID }
            snapshot.locations.removeAll { $0.homeID == homeID }
            snapshot.collections.removeAll { $0.homeID == homeID }
            snapshot.memberships.removeAll { collectionIDs.contains($0.collectionID) }
            snapshot.bellItems.removeAll { itemIDs.contains($0.item.id) }
        }
    }

    func saveCollection(_ collection: Collection) {
        store.updateSnapshot { snapshot in
            if let index = snapshot.collections.firstIndex(where: { $0.id == collection.id }) {
                snapshot.collections[index] = collection
            } else {
                snapshot.collections.append(collection)
                snapshot.memberships.append(
                    Membership(
                        id: UUID(),
                        collectionID: collection.id,
                        userID: "me",
                        role: .owner,
                        status: .active
                    )
                )
            }
        }
    }

    func saveBellRecord(_ bell: BellRecord) {
        let entry = BellItemEntry(
            item: bell.item,
            details: bell.details,
            mediaAssets: bell.mediaAssets,
            createdBy: bell.createdBy,
            tags: bell.tags
        )

        store.updateSnapshot { snapshot in
            if let place = bell.originPlace,
               !snapshot.places.contains(where: { $0.id == place.id }) {
                snapshot.places.append(place)
            }

            if let index = snapshot.bellItems.firstIndex(where: { $0.item.id == bell.item.id }) {
                snapshot.bellItems[index] = entry
            } else {
                snapshot.bellItems.insert(entry, at: 0)
            }
        }
    }

    func deleteBellRecord(bellID: UUID) {
        store.updateSnapshot { snapshot in
            let assets = snapshot.bellItems.first(where: { $0.item.id == bellID })?.mediaAssets ?? []
            assets.forEach { mediaStore.deleteFile(for: $0.localIdentifier) }
            snapshot.bellItems.removeAll { $0.item.id == bellID }
        }
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

    private func removeHiddenCollectionsFromLocalStore() {
        store.updateSnapshot { snapshot in
            let removedCollectionIDs = snapshot.collections
                .filter { $0.kind == .books }
                .map(\.id)

            guard !removedCollectionIDs.isEmpty else { return }

            let removedBellItemIDs = snapshot.bellItems
                .filter { removedCollectionIDs.contains($0.item.collectionID) }
                .map(\.item.id)

            snapshot.collections.removeAll { $0.kind == .books }
            snapshot.memberships.removeAll { removedCollectionIDs.contains($0.collectionID) }
            snapshot.bellItems.removeAll { removedBellItemIDs.contains($0.item.id) }
        }
    }
}

private final class CatalogJSONStore {
    private let baseURL: URL
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL?) {
        let resolvedBaseURL = baseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Catalog", isDirectory: true)
        self.baseURL = resolvedBaseURL
        self.fileURL = resolvedBaseURL.appendingPathComponent("catalog-data.json")
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func bootstrapIfNeeded(using repository: any CatalogRepository) {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }

        let homes = repository.fetchHomes()
        let locations = homes.flatMap { repository.fetchLocations(in: $0.id) }
        let collections = homes.flatMap { repository.fetchDomainCollections(in: $0.id) }
        let memberships = collections.flatMap { repository.fetchMemberships(for: $0.id) }
        let bellItems = collections
            .filter { $0.kind == .bells }
            .flatMap { repository.fetchBellRecords(for: $0.id) }
            .map { bell in
                BellItemEntry(
                    item: bell.item,
                    details: bell.details,
                    mediaAssets: bell.mediaAssets,
                    createdBy: bell.createdBy,
                    tags: bell.tags
                )
            }
        let places = Array(Set(collections
            .filter { $0.kind == .bells }
            .flatMap { repository.fetchBellRecords(for: $0.id).compactMap(\.originPlace) }))
            .sorted { $0.displayName < $1.displayName }

        let snapshot = CatalogSnapshot(
            homes: homes,
            locations: locations,
            collections: collections,
            memberships: memberships,
            places: places,
            bellItems: bellItems,
            userDirectory: [
                "me": "Вы",
                "marina": "Марина",
                "alexey": "Алексей",
                "nina": "Нина"
            ]
        )

        saveSnapshot(snapshot)
    }

    func loadSnapshot() -> CatalogSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(CatalogSnapshot.self, from: data)
        else {
            return CatalogSnapshot.empty
        }

        return snapshot
    }

    func updateSnapshot(_ transform: (inout CatalogSnapshot) -> Void) {
        var snapshot = loadSnapshot()
        transform(&snapshot)
        saveSnapshot(snapshot)
    }

    private func saveSnapshot(_ snapshot: CatalogSnapshot) {
        do {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Failed to save local catalog snapshot: \(error)")
        }
    }
}

private struct CatalogSnapshot: Codable {
    var homes: [Home]
    var locations: [Location]
    var collections: [Collection]
    var memberships: [Membership]
    var places: [Place]
    var bellItems: [BellItemEntry]
    var userDirectory: [String: String]

    static let empty = CatalogSnapshot(
        homes: [],
        locations: [],
        collections: [],
        memberships: [],
        places: [],
        bellItems: [],
        userDirectory: [:]
    )
}

private struct BellItemEntry: Codable {
    var item: Item
    var details: BellDetails
    var mediaAssets: [MediaAsset]
    var createdBy: String
    var tags: [String]
}
