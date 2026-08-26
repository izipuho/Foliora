import SwiftUI

/// Resolves a bell by identifier and owns the navigation container used for item detail presentation.
struct BellItemDetailContainer: View {
    let bellID: UUID
    let repository: any CatalogRepository
    let catalogSnapshot: CatalogSnapshot?
    let onClose: (() -> Void)?

    @State private var bell: BellRecord?
    @State private var collectionSharingState: CollectionSharingState?
    @State private var collectionSharingLoadError: Error?

    init(
        bellID: UUID,
        repository: any CatalogRepository,
        catalogSnapshot: CatalogSnapshot?,
        onClose: (() -> Void)? = nil
    ) {
        self.bellID = bellID
        self.repository = repository
        self.catalogSnapshot = catalogSnapshot
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            Group {
                if let bellBinding {
                    BellDetailView(
                        bell: bellBinding,
                        repository: repository,
                        catalogSnapshot: catalogSnapshot,
                        canEditCollection: canEditCollection,
                        canChangeFavorite: canChangeFavorite
                    )
                } else {
                    CatalogEmptyStateView(
                        systemImage: "bell.slash",
                        title: "bell.not_found"
                    )
                }
            }
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
        }
        .task(id: bellID) {
            syncBellFromCatalogSnapshot()
        }
        .task(id: currentCollectionID) {
            await loadCollectionSharingState()
        }
        .onChange(of: catalogSnapshot?.recordsByID[bellID]) { _, _ in
            syncBellFromCatalogSnapshot()
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

    private func syncBellFromCatalogSnapshot() {
        bell = catalogSnapshot?.recordsByID[bellID]
    }

    @MainActor
    private func loadCollectionSharingState() async {
        collectionSharingState = nil
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
