import SwiftUI
import MapKit
import PhotosUI
import CoreData
import UIKit


struct HomeView: View {
    let repository: any CatalogRepository
    let embedsNavigation: Bool
    let navigate: ((AppDestination) -> Void)?
    @Environment(\.managedObjectContext) private var managedObjectContext
    @State private var catalogSnapshot: CatalogSnapshot?
    @State private var draftHome = Home(id: UUID(), name: "", iconName: "house.fill", notes: "")
    @State private var draftLocations: [Location] = []
    @State private var isPresentingCreateHomeEditor = false
    @State private var pendingDeleteHomeID: UUID?
    @State private var isPresentingDeleteConfirmation = false

    init(
        repository: any CatalogRepository,
        embedsNavigation: Bool = true,
        navigate: ((AppDestination) -> Void)? = nil
    ) {
        self.repository = repository
        self.embedsNavigation = embedsNavigation
        self.navigate = navigate
    }

    var body: some View {
        homeContent
    }

    private var homes: [Home] {
        catalogSnapshot?.homes ?? []
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
            }
        }
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
        .confirmationDialog(
            String(localized: "home.delete.title"),
            isPresented: $isPresentingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "home.delete.confirm"), role: .destructive) {
                confirmDeleteHome()
            }

            Button(String(localized: "common.cancel"), role: .cancel) {
                pendingDeleteHomeID = nil
            }
        } message: {
            Text(String(localized: "home.delete.message"))
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
        .onAppear(perform: reloadCatalogSnapshot)
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: managedObjectContext
        )) { _ in
            reloadCatalogSnapshot()
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
                requestDeleteHome(home.id)
            } label: {
                Label(String(localized: "common.delete"), systemImage: "trash")
            }

            Button {
                navigate?(.editHome(home.id))
            } label: {
                Label(String(localized: "common.edit"), systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private func collectionCount(in homeID: UUID) -> Int {
        catalogSnapshot?.collectionCountsByHomeID[homeID] ?? 0
    }

    private func presentEditorForNewHome() {
        draftHome = Home(id: UUID(), name: "", iconName: "house.fill", notes: "")
        draftLocations = []
        isPresentingCreateHomeEditor = true
    }

    private func saveDraftHome() {
        repository.saveHome(draftHome)
        repository.saveLocations(draftLocations, in: draftHome.id)
        reloadCatalogSnapshot()
    }

    private func requestDeleteHome(_ homeID: UUID) {
        pendingDeleteHomeID = homeID
        isPresentingDeleteConfirmation = true
    }

    private func confirmDeleteHome() {
        guard let homeID = pendingDeleteHomeID else { return }
        deleteHome(homeID)
        pendingDeleteHomeID = nil
    }

    private func deleteHome(_ homeID: UUID) {
        repository.deleteHome(homeID: homeID)
        reloadCatalogSnapshot()
    }

    private func reloadCatalogSnapshot() {
        catalogSnapshot = CatalogSnapshot.load(from: managedObjectContext)
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
            systemImage: home.iconName
        )
    }
}
