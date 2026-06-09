import SwiftUI
import MapKit
import PhotosUI
import SwiftData
import UIKit


struct HomeView: View {
    let repository: any CatalogRepository
    let embedsNavigation: Bool
    let navigate: ((AppDestination) -> Void)?
    @Query(sort: \HomeEntity.name) private var homeEntities: [HomeEntity]
    @Query(sort: \LocationEntity.name) private var locationEntities: [LocationEntity]
    @Query(sort: \CollectionEntity.title) private var collectionEntities: [CollectionEntity]
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

    private var scrollContentBottomInset: CGFloat { 120 }

    private var homes: [Home] {
        homeEntities.map(\.homeSnapshot)
    }

    private var locationsByHomeID: [UUID: [Location]] {
        Dictionary(grouping: locationEntities.compactMap { location -> (UUID, Location)? in
            guard let homeID = location.home?.id else { return nil }
            return (homeID, location.locationSnapshot)
        }, by: \.0)
        .mapValues { rows in
            rows.map(\.1).sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private var homeContent: some View {
        Group {
            if homes.isEmpty {
                emptyHomesView
            } else {
                List {
                    Section {
                        homesRows
                    }
                }
                .listStyle(.insetGrouped)
                .contentMargins(.horizontal, nil, for: .scrollContent)
                .contentMargins(.top, nil, for: .scrollContent)
                .contentMargins(.bottom, scrollContentBottomInset, for: .scrollContent)
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
            if embedsNavigation {
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
                .listRowSeparator(.hidden)
                .swipeActions {
                    Button(String(localized: "common.delete"), role: .destructive) {
                        requestDeleteHome(home.id)
                    }
                }
            } else if binding(for: home.id) != nil {
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
                .listRowSeparator(.hidden)
                .swipeActions {
                    Button(String(localized: "common.delete"), role: .destructive) {
                        requestDeleteHome(home.id)
                    }
                }
            } else {
                HomeListCard(
                    home: home,
                    locations: locationsByHomeID[home.id] ?? [],
                    collectionCount: collectionCount(in: home.id)
                )
                .listRowSeparator(.hidden)
                .swipeActions {
                    Button(String(localized: "common.delete"), role: .destructive) {
                        requestDeleteHome(home.id)
                    }
                }
            }
        }
    }

    private func binding(for homeID: UUID) -> Binding<Home>? {
        guard homes.contains(where: { $0.id == homeID }) else { return nil }
        return Binding(
            get: { homeEntities.first(where: { $0.id == homeID })?.homeSnapshot ?? Home(id: homeID, name: "", notes: "") },
            set: { repository.saveHome($0) }
        )
    }

    private func locationsBinding(for homeID: UUID) -> Binding<[Location]> {
        Binding(
            get: { locationsByHomeID[homeID] ?? [] },
            set: { repository.saveLocations($0, in: homeID) }
        )
    }

    private func collectionCount(in homeID: UUID) -> Int {
        collectionEntities.filter { $0.home?.id == homeID }.count
    }

    private func createHome() -> Home {
        let newHome = Home(id: UUID(), name: "", iconName: "house.fill", notes: "")
        repository.saveHome(newHome)
        repository.saveLocations([], in: newHome.id)
        return newHome
    }

    private func presentEditorForNewHome() {
        let newHome = createHome()
        DispatchQueue.main.async {
            navigate?(.editHome(newHome.id))
        }
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
            detailLines: [],
            systemImage: home.iconName,
            accessorySystemImage: nil
        )
    }
}
