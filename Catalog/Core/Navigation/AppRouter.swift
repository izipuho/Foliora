import SwiftUI
import SwiftData

enum AppDestination: Hashable {
    case collection(CollectionSummary)
    case home(UUID)
}

enum RootTab: String, CaseIterable, Identifiable {
    case collections
    case settings
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collections:
            return String(localized: "root_tab.collections")
        case .settings:
            return String(localized: "root_tab.settings")
        case .search:
            return String(localized: "root_tab.search")
        }
    }

    var systemImage: String {
        switch self {
        case .collections:
            return "square.grid.2x2"
        case .settings:
            return "gearshape"
        case .search:
            return "magnifyingglass"
        }
    }
}

struct AppShellView: View {
    let repository: any CatalogRepository
    @Query(sort: \HomeEntity.name) private var homeEntities: [HomeEntity]
    @Query(sort: \LocationEntity.name) private var locationEntities: [LocationEntity]
    @Query(sort: \CollectionEntity.title) private var collectionEntities: [CollectionEntity]
    @State private var path = NavigationPath()

    var body: some View {
        RootShellView(
            repository: repository,
            path: $path,
            navigate: { path.append($0) },
            destination: destinationView
        )
    }

    @ViewBuilder
    private func destinationView(for destination: AppDestination) -> some View {
        switch destination {
        case .collection(let collection):
            CollectionShellView(
                collection: collection,
                repository: repository
            )
        case .home(let homeID):
            if let homeBinding = binding(for: homeID) {
                HomeDetailView(
                    home: homeBinding,
                    locations: locationsBinding(for: homeID),
                    collectionCount: collectionCount(in: homeID),
                    onSave: { updatedHome, updatedLocations in
                        repository.saveHome(updatedHome)
                        repository.saveLocations(updatedLocations, in: updatedHome.id)
                    },
                    onDelete: {
                        repository.deleteHome(homeID: homeID)
                        if !path.isEmpty {
                            path.removeLast()
                        }
                    }
                )
            } else {
                ContentUnavailableView(
                    String(localized: "home.not_found.title"),
                    systemImage: "house.slash",
                    description: Text(String(localized: "home.not_found.description"))
                )
            }
        }
    }

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
}

private struct RootShellView<Destination: View>: View {
    let repository: any CatalogRepository
    @Binding var path: NavigationPath
    let navigate: (AppDestination) -> Void
    let destination: (AppDestination) -> Destination

    var body: some View {
        TabView {
            Tab(RootTab.collections.title, systemImage: RootTab.collections.systemImage) {
                NavigationStack(path: $path) {
                    CollectionsView(
                        repository: repository,
                        navigate: navigate
                    )
                    .navigationDestination(for: AppDestination.self, destination: destination)
                }
            }

            Tab(RootTab.settings.title, systemImage: RootTab.settings.systemImage) {
                NavigationStack(path: $path) {
                    SettingsView(
                        repository: repository,
                        navigate: navigate
                    )
                    .navigationDestination(for: AppDestination.self, destination: destination)
                }
            }

            Tab(role: .search) {
                NavigationStack {
                    SearchTabView(repository: repository)
                }
            }
        }
        .modifier(ModernTabBarBehavior())
    }
}
private struct ModernTabBarBehavior: ViewModifier {
    func body(content: Content) -> some View {
        content.tabBarMinimizeBehavior(.onScrollDown)
    }
}
