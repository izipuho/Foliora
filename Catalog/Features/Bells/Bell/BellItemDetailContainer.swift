import SwiftUI

/// Resolves a bell by identifier and owns the navigation container used for item detail presentation.
struct BellItemDetailContainer: View {
    let bellID: UUID
    let repository: any AppRepository
    let catalogSnapshot: CatalogSnapshot?
    let onClose: (() -> Void)?

    @Environment(\.mediaDataLoader) private var mediaDataLoader
    @State private var bell: BellRecord?
    @State private var collectionSharingState: CollectionSharingState?
    @State private var collectionSharingLoadError: Error?

    init(
        bellID: UUID,
        repository: any AppRepository,
        catalogSnapshot: CatalogSnapshot?,
        initialSharingState: CollectionSharingState? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.bellID = bellID
        self.repository = repository
        self.catalogSnapshot = catalogSnapshot
        _collectionSharingState = State(initialValue: initialSharingState)
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            if let bellBinding {
                BellDetailView(
                    bell: bellBinding,
                    repository: repository,
                    catalogSnapshot: catalogSnapshot,
                    canEditCollection: canEditCollection,
                    canChangeFavorite: canChangeFavorite,
                    onClose: onClose
                )
            } else {
                CatalogEmptyStateView(
                    systemImage: "bell.slash",
                    title: "bell.not_found"
                )
            }
        }
        .task(id: catalogSnapshot?.recordsByID[bellID]) {
            await syncBellFromCatalogSnapshot()
        }
        .task(id: currentCollectionID) {
            guard collectionSharingState == nil else { return }
            await loadCollectionSharingState()
        }
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

    private var canChangeFavorite: Bool {
        guard collectionSharingLoadError == nil else { return false }

        switch collectionSharingState?.currentUserRole {
        case .owner:
            return true
        case .contributor, .viewer, nil:
            return false
        }
    }

    private var bellBinding: Binding<BellRecord>? {
        guard let currentBell = bell else { return nil }

        return Binding(
            get: {
                bell ?? currentBell
            },
            set: {
                bell = $0
            }
        )
    }

    private var currentCollectionID: UUID? {
        bell?.item.collectionID ?? catalogSnapshot?.recordsByID[bellID]?.item.collectionID
    }

    /// Takes the bell from the snapshot and loads the media bytes the snapshot does not carry.
    ///
    /// The detail screen, its media section and the editor opened from it rely on `originalData`.
    @MainActor
    private func syncBellFromCatalogSnapshot() async {
        guard let snapshotBell = catalogSnapshot?.recordsByID[bellID] else {
            bell = nil
            return
        }

        var item = snapshotBell.item
        item.mediaAssets = MediaDataLoader.reusingData(item.mediaAssets, from: bell?.item.mediaAssets ?? [])
        bell = BellRecord(item: item, details: snapshotBell.details)

        guard let mediaDataLoader else { return }
        item.mediaAssets = await mediaDataLoader.hydrated(item.mediaAssets)
        guard !Task.isCancelled else { return }
        bell = BellRecord(item: item, details: snapshotBell.details)
    }

    @MainActor
    private func loadCollectionSharingState() async {
        collectionSharingLoadError = nil

        guard let collectionID = currentCollectionID,
              let persistentContainer = FolioraAppDelegate.coreDataContainer else {
            return
        }

        do {
            collectionSharingState = try await CloudKitCollectionSharingService(
                persistentContainer: persistentContainer
            ).sharingState(for: collectionID)
        } catch {
            collectionSharingLoadError = error
        }
    }
}
