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
