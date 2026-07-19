import CoreData
import SwiftUI
import MapKit
import PhotosUI
import UIKit


struct HomeView: View {
    let repository: any CatalogRepository
    let embedsNavigation: Bool
    let navigate: ((AppDestination) -> Void)?
    let navigationSnapshot: CatalogSnapshot?
    let reloadNavigationSnapshot: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var draftHome = Home(id: UUID(), name: "", iconName: "house.fill", notes: "")
    @State private var draftLocations: [Location] = []
    @State private var isPresentingCreateHomeEditor = false
    @State private var homeIDPendingDeletion: UUID?

    init(
        repository: any CatalogRepository,
        embedsNavigation: Bool = true,
        navigate: ((AppDestination) -> Void)? = nil,
        navigationSnapshot: CatalogSnapshot?,
        reloadNavigationSnapshot: @escaping () -> Void
    ) {
        self.repository = repository
        self.embedsNavigation = embedsNavigation
        self.navigate = navigate
        self.navigationSnapshot = navigationSnapshot
        self.reloadNavigationSnapshot = reloadNavigationSnapshot
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
    }

    private var homes: [Home] {
        navigationSnapshot?.homes ?? []
    }

    private var locationsByHomeID: [UUID: [Location]] {
        navigationSnapshot?.locationsByHomeID ?? [:]
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
            }
        }
        .background {
            CatalogBackgrounds.app(scheme: colorScheme)
                .ignoresSafeArea()
        }
        .navigationTitle(String(localized: "home.screen.title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentEditorForNewHome()
                } label: {
                    Image(systemName: "plus")
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
        ForEach(homes) { home in
            homeRow(for: home)
        }
    }

    private func homeRow(for home: Home) -> some View {
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
                homeIDPendingDeletion = home.id
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

    private func collectionCount(in homeID: UUID) -> Int {
        navigationSnapshot?.collectionCountsByHomeID[homeID] ?? 0
    }

    private func presentEditorForNewHome() {
        draftHome = Home(id: UUID(), name: "", iconName: "house.fill", notes: "")
        draftLocations = []
        isPresentingCreateHomeEditor = true
    }

    private func saveDraftHome() {
        repository.saveHome(draftHome)
        repository.saveLocations(draftLocations, in: draftHome.id)
        reloadNavigationSnapshot()
    }

    private func deleteHome(_ homeID: UUID) {
        repository.deleteHome(homeID: homeID)
        reloadNavigationSnapshot()
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
    NavigationStack {
        HomeView(
            repository: HomeViewPreviewData.repository,
            navigationSnapshot: HomeViewPreviewData.snapshot,
            reloadNavigationSnapshot: {}
        )
        .environment(\.managedObjectContext, HomeViewPreviewData.context)
    }
}

@MainActor
private enum HomeViewPreviewData {
    static let homeID = UUID()

    static let context: NSManagedObjectContext = {
        do {
            let modelURL = Bundle.main.url(forResource: FolioraCoreDataStack.modelName, withExtension: "momd")
                ?? Bundle(for: CoreDataCatalogRepository.self)
                    .url(forResource: FolioraCoreDataStack.modelName, withExtension: "momd")
            guard let modelURL, let model = NSManagedObjectModel(contentsOf: modelURL) else {
                fatalError("Failed to load Foliora Core Data model for HomeView preview.")
            }

            let container = NSPersistentCloudKitContainer(
                name: FolioraCoreDataStack.modelName,
                managedObjectModel: model
            )
            let storeDescription = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null/Shared.sqlite"))
            storeDescription.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [storeDescription]

            var loadError: Error?
            container.loadPersistentStores { _, error in
                loadError = error
            }
            if let loadError {
                throw loadError
            }

            let context = container.viewContext
            let home = NSEntityDescription.insertNewObject(forEntityName: "HomeEntity", into: context)
            home.setValue(homeID, forKey: "id")
            home.setValue("Lake House", forKey: "name")
            home.setValue("house.fill", forKey: "iconName")
            home.setValue("Summer storage and display shelves.", forKey: "notes")

            let location = NSEntityDescription.insertNewObject(forEntityName: "LocationEntity", into: context)
            location.setValue(UUID(), forKey: "id")
            location.setValue("room", forKey: "kindRaw")
            location.setValue("Study", forKey: "name")
            location.setValue("", forKey: "notes")
            location.setValue(home, forKey: "home")

            let collection = NSEntityDescription.insertNewObject(forEntityName: "CollectionEntity", into: context)
            collection.setValue(UUID(), forKey: "id")
            collection.setValue("bells", forKey: "kindRaw")
            collection.setValue("Travel Bells", forKey: "title")
            collection.setValue("", forKey: "notes")
            collection.setValue("amber", forKey: "backgroundStyleRaw")
            collection.setValue(home, forKey: "home")

            try context.save()
            return context
        } catch {
            fatalError("Failed to create HomeView preview data: \(error)")
        }
    }()

    static let snapshot = CatalogSnapshot.load(from: context)
    static let repository = HomeViewPreviewRepository()
}

@MainActor
private final class HomeViewPreviewRepository: CatalogRepository {
    func saveHome(_ home: Home) {}
    func saveLocations(_ locations: [Location], in homeID: UUID) {}
    func deleteHome(homeID: UUID) {}
    func saveCollection(_ collection: Collection) {}
    func deleteResolution(for collectionID: UUID) -> CollectionDeleteResolution { .deletePrivateCollection }
    func deleteCollection(collectionID: UUID) {}
    func saveBellRecord(_ bell: BellRecord) {}
    func deleteBellRecord(bellID: UUID) {}
}
#endif
