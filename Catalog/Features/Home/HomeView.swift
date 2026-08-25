import CoreData
import SwiftUI
import MapKit
import PhotosUI
import UIKit


/// Displays the home view interface.
struct HomeView: View {
    let repository: any CatalogRepository
    let embedsNavigation: Bool
    let navigate: ((AppDestination) -> Void)?
    let catalogSnapshot: CatalogSnapshot?
    @Environment(\.colorScheme) private var colorScheme
    @State private var draftHome = Home(id: UUID(), name: "", iconName: "house.fill", notes: "")
    @State private var draftLocations: [Location] = []
    @State private var isPresentingCreateHomeEditor = false
    @State private var homeIDPendingDeletion: UUID?
    @State private var homeIDBlockedFromDeletion: UUID?
    @State private var homeDeletionTransferRequest: HomeDeletionTransferRequest?
    @State private var isSortingHomes = false
    @State private var sortingHomes: [Home] = []

    init(
        repository: any CatalogRepository,
        embedsNavigation: Bool = true,
        navigate: ((AppDestination) -> Void)? = nil,
        catalogSnapshot: CatalogSnapshot?
    ) {
        self.repository = repository
        self.embedsNavigation = embedsNavigation
        self.navigate = navigate
        self.catalogSnapshot = catalogSnapshot
    }

    var body: some View {
        homeContent
            .alert(
                String(localized: "home.delete.title"),
                isPresented: Binding(
                    get: { homeIDPendingDeletion != nil },
                    set: { isPresented in
                        if !isPresented {
                            homeIDPendingDeletion = nil
                        }
                    }
                )
            ) {
                Button(String(localized: "common.delete"), role: .destructive) {
                    if let homeID = homeIDPendingDeletion {
                        deleteHome(homeID)
                    }
                    homeIDPendingDeletion = nil
                }

                Button(String(localized: "common.cancel"), role: .cancel) {
                    homeIDPendingDeletion = nil
                }
            } message: {
                Text(String(localized: "home.delete.message"))
            }
            .alert(
                String(localized: "home.delete.title"),
                isPresented: Binding(
                    get: { homeIDBlockedFromDeletion != nil },
                    set: { isPresented in
                        if !isPresented {
                            homeIDBlockedFromDeletion = nil
                        }
                    }
                )
            ) {
                Button(String(localized: "home.add")) {
                    homeIDBlockedFromDeletion = nil
                    presentEditorForNewHome()
                }

                Button(String(localized: "common.cancel"), role: .cancel) {
                    homeIDBlockedFromDeletion = nil
                }
            } message: {
                Text(String(localized: "collections.empty.requires_home.message"))
            }
            .sheet(item: $homeDeletionTransferRequest) { request in
                HomeDeletionTransferView(
                    collectionCount: request.collectionCount,
                    destinationHomes: request.destinationHomes
                ) { destinationHomeID in
                    transferCollectionsAndDeleteHome(
                        from: request.homeID,
                        to: destinationHomeID
                    )
                }
            }
    }

    private var homes: [Home] {
        catalogSnapshot?.homes ?? []
    }

    private var privateHomes: [Home] {
        homes.filter { !$0.isShared }
    }

    private var displayedHomes: [Home] {
        isSortingHomes ? sortingHomes : homes
    }

    private var locationsByHomeID: [UUID: [Location]] {
        catalogSnapshot?.locationsByHomeID ?? [:]
    }

    private var homeContent: some View {
        Group {
            if homes.isEmpty {
                emptyHomesView
            } else {
                CatalogContainerList {
                    Section {
                        homesRows
                    }
                }
                .environment(\.editMode, .constant(isSortingHomes ? .active : .inactive))
            }
        }
        .background {
            CatalogBackgrounds.app(scheme: colorScheme)
                .ignoresSafeArea()
        }
        .navigationTitle(String(localized: "home.screen.title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !homes.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if isSortingHomes {
                            stopSortingHomes()
                        } else {
                            startSortingHomes()
                        }
                    } label: {
                        if isSortingHomes {
                            Image(systemName: "checkmark")
                        } else {
                            Image(systemName: "line.3.horizontal.decrease")
                        }
                    }
                }
            }

            if !isSortingHomes {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentEditorForNewHome()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingCreateHomeEditor) {
            HomeEditorView(
                home: $draftHome,
                locations: $draftLocations,
                onSave: saveDraftHome,
                onDelete: nil,
                focusesNameOnAppear: true
            )
        }
    }

    private var emptyHomesView: some View {
        CatalogEmptyStateView(
            systemImage: "house.slash",
            title: "home.empty.title",
            message: "home.empty.description",
            primaryActionTitle: "home.add",
            primaryActionSystemImage: "plus.circle.fill",
            primaryTint: Color(red: 0.20, green: 0.42, blue: 0.34),
            primaryAction: presentEditorForNewHome
        )
    }

    @ViewBuilder
    private var homesRows: some View {
        ForEach(displayedHomes) { home in
            homeRow(for: home)
        }
        .onMove(perform: moveHomes)
    }

    @ViewBuilder
    private func homeRow(for home: Home) -> some View {
        if isSortingHomes {
            HomeListCard(
                home: home,
                locations: locationsByHomeID[home.id] ?? [],
                collectionCount: collectionCount(in: home.id)
            )
            .catalogContainerListRow()
        } else {
            Button {
                navigate?(.home(home.id))
            } label: {
                HomeListCard(
                    home: home,
                    locations: locationsByHomeID[home.id] ?? [],
                    collectionCount: collectionCount(in: home.id)
                )
            }
            .buttonStyle(.plain)
            .catalogContainerListRow()
            .swipeActions {
                Button(role: .destructive) {
                    requestDeleteHome(home)
                } label: {
                    Label(String(localized: "common.delete"), systemImage: "trash")
                }

                Button {
                    navigate?(.editHome(home.id))
                } label: {
                    Label(String(localized: "common.edit"), systemImage: "pencil")
                }
                .tint(CatalogSemanticColors.info)
            }
        }
    }

    private func collectionCount(in homeID: UUID) -> Int {
        catalogSnapshot?.collectionCountsByHomeID[homeID] ?? 0
    }

    private func collections(in homeID: UUID) -> [Collection] {
        catalogSnapshot?.collections.filter { $0.homeID == homeID } ?? []
    }

    private func requestDeleteHome(_ home: Home) {
        let homeCollections = collections(in: home.id)
        guard !homeCollections.isEmpty else {
            homeIDPendingDeletion = home.id
            return
        }

        guard !home.isShared else {
            homeIDPendingDeletion = home.id
            return
        }

        let destinationHomes = privateHomes.filter { $0.id != home.id }
        guard !destinationHomes.isEmpty else {
            homeIDBlockedFromDeletion = home.id
            return
        }

        homeDeletionTransferRequest = HomeDeletionTransferRequest(
            homeID: home.id,
            collectionCount: homeCollections.count,
            destinationHomes: destinationHomes
        )
    }

    private func transferCollectionsAndDeleteHome(from homeID: UUID, to destinationHomeID: UUID) {
        guard privateHomes.contains(where: { $0.id == destinationHomeID && $0.id != homeID }) else { return }

        for collection in collections(in: homeID) {
            repository.saveCollection(
                Collection(
                    id: collection.id,
                    homeID: destinationHomeID,
                    kind: collection.kind,
                    title: collection.title,
                    notes: collection.notes,
                    backgroundStyle: collection.backgroundStyle
                )
            )
        }

        deleteHome(homeID)
    }

    private func presentEditorForNewHome() {
        draftHome = Home(id: UUID(), name: "", iconName: "house.fill", notes: "")
        draftLocations = []
        isPresentingCreateHomeEditor = true
    }

    private func saveDraftHome() {
        repository.saveHome(draftHome)
        repository.saveLocations(draftLocations, in: draftHome.id)
    }

    private func startSortingHomes() {
        sortingHomes = homes
        isSortingHomes = true
    }

    private func stopSortingHomes() {
        isSortingHomes = false
        sortingHomes = []
    }

    private func moveHomes(from source: IndexSet, to destination: Int) {
        guard isSortingHomes else { return }

        sortingHomes.move(fromOffsets: source, toOffset: destination)
        repository.saveUserSortOrder(itemIDs: sortingHomes.map(\.id), scope: "Home")
    }

    private func deleteHome(_ homeID: UUID) {
        repository.deleteHome(homeID: homeID)
    }
}

private struct HomeDeletionTransferRequest: Identifiable {
    let homeID: UUID
    let collectionCount: Int
    let destinationHomes: [Home]

    var id: UUID { homeID }
}

private struct HomeDeletionTransferView: View {
    let collectionCount: Int
    let destinationHomes: [Home]
    let onConfirm: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedHomeID: UUID

    init(
        collectionCount: Int,
        destinationHomes: [Home],
        onConfirm: @escaping (UUID) -> Void
    ) {
        self.collectionCount = collectionCount
        self.destinationHomes = destinationHomes
        self.onConfirm = onConfirm
        _selectedHomeID = State(initialValue: destinationHomes.first?.id ?? UUID())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString("home.list.collections.count", comment: "Home list collection count"),
                            collectionCount
                        )
                    )

                    Picker(String(localized: "home.screen.single_title"), selection: $selectedHomeID) {
                        ForEach(destinationHomes) { home in
                            Text(home.name).tag(home.id)
                        }
                    }
                }

                Section {
                    Text(String(localized: "collection.home_change.message"))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "home.delete.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.delete"), role: .destructive) {
                        onConfirm(selectedHomeID)
                        dismiss()
                    }
                    .disabled(!destinationHomes.contains(where: { $0.id == selectedHomeID }))
                }
            }
        }
    }
}

private struct HomeListCard: View {
    let home: Home
    let locations: [Location]
    let collectionCount: Int

    private var hasStorageLocations: Bool {
        !locations.isEmpty
    }

    private var subtitle: String {
        let collectionsSummary: String
        if collectionCount == 0 {
            collectionsSummary = String(localized: "home.list.collections.empty")
        } else {
            collectionsSummary = String.localizedStringWithFormat(
                NSLocalizedString("home.list.collections.count", comment: "Home list collection count"),
                collectionCount
            )
        }

        guard !hasStorageLocations else {
            return collectionsSummary
        }

        return [
            collectionsSummary,
            String(localized: "home.list.storage.empty")
        ].joined(separator: " · ")
    }

    var body: some View {
        CatalogContainerCard(
            title: home.name,
            subtitle: subtitle,
            accessory: home.isShared ? .icon("link") : nil,
            systemImage: home.iconName
        )
    }
}

#if DEBUG
#Preview {
    let container = PreviewContainer.make(.collectionsMinimal)
    let repository = CoreDataCatalogRepository(
        context: container.viewContext,
        persistentContainer: nil
    )
    let snapshot = CatalogSnapshot.load(from: container.viewContext)

    NavigationStack {
        HomeView(
            repository: repository,
            catalogSnapshot: snapshot
        )
        .environment(\.managedObjectContext, container.viewContext)
    }
}
#endif
