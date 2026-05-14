import SwiftUI
import SwiftData

enum AppDestination: Hashable {
    case collection(CollectionSummary)
    case home(UUID)
}

enum RootTab: String, CaseIterable, Identifiable, Hashable {
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
            destination: { destination, layoutMode in
                destinationView(for: destination, layoutMode: layoutMode)
            }
        )
    }

    @ViewBuilder
    private func destinationView(
        for destination: AppDestination,
        layoutMode: Binding<BellGridLayoutMode>
    ) -> some View {
        switch destination {
        case .collection(let collection):
            CollectionShellView(
                collection: collection,
                repository: repository,
                layoutMode: layoutMode
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
    let destination: (AppDestination, Binding<BellGridLayoutMode>) -> Destination
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("bellCatalog.layoutMode") private var layoutModeRawValue = BellGridLayoutMode.mini.rawValue
    @State private var selectedRootTab: RootTab = .collections

    private var layoutMode: BellGridLayoutMode {
        get {
            BellGridLayoutMode(rawValue: layoutModeRawValue) ?? .mini
        }
        nonmutating set {
            layoutModeRawValue = newValue.rawValue
        }
    }

    private var layoutModeBinding: Binding<BellGridLayoutMode> {
        Binding(
            get: { layoutMode },
            set: { layoutMode = $0 }
        )
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadRootContainer
        } else {
            iPhoneRootContainer
        }
    }

    private var iPhoneRootContainer: some View {
        TabView {
            Tab(RootTab.collections.title, systemImage: RootTab.collections.systemImage) {
                NavigationStack(path: $path) {
                    CollectionsView(
                        repository: repository,
                        navigate: navigate
                    )
                    .navigationDestination(for: AppDestination.self) { destination in
                        self.destination(destination, layoutModeBinding)
                    }
                }
            }

            Tab(RootTab.settings.title, systemImage: RootTab.settings.systemImage) {
                NavigationStack(path: $path) {
                    SettingsView(
                        repository: repository,
                        navigate: navigate
                    )
                    .navigationDestination(for: AppDestination.self) { destination in
                        self.destination(destination, layoutModeBinding)
                    }
                }
            }

            Tab(role: .search) {
                NavigationStack {
                    SearchTabView(repository: repository, layoutMode: layoutModeBinding)
                }
            }
        }
        .modifier(ModernTabBarBehavior())
    }

    private var iPadRootContainer: some View {
        NavigationSplitView {
            List {
                ForEach([RootTab.collections, .search, .settings]) { tab in
                    Button {
                        selectedRootTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedRootTab == tab ? Color.accentColor.opacity(0.14) : nil)
                }
            }
            .navigationTitle(RootTab.collections.title)
        } content: {
            iPadContent(for: selectedRootTab)
        } detail: {
            ContentUnavailableView(
                selectedRootTab.title,
                systemImage: "sidebar.right"
            )
        }
    }

    @ViewBuilder
    private func iPadContent(for tab: RootTab) -> some View {
        switch tab {
        case .collections:
            NavigationStack(path: $path) {
                CollectionsView(
                    repository: repository,
                    navigate: navigate
                )
                .navigationDestination(for: AppDestination.self) { destination in
                    self.destination(destination, layoutModeBinding)
                }
            }
        case .search:
            NavigationStack {
                SearchTabView(repository: repository, layoutMode: layoutModeBinding)
            }
        case .settings:
            NavigationStack(path: $path) {
                SettingsView(
                    repository: repository,
                    navigate: navigate
                )
                .navigationDestination(for: AppDestination.self) { destination in
                    self.destination(destination, layoutModeBinding)
                }
            }
        }
    }
}
private struct ModernTabBarBehavior: ViewModifier {
    func body(content: Content) -> some View {
        content.tabBarMinimizeBehavior(.onScrollDown)
    }
}
