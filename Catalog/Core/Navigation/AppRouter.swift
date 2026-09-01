import SwiftUI
import CoreData

private typealias BatchCompletionHandler = (Any) -> Void

/// Defines the supported app destination values.
enum AppDestination: Hashable {
    case collection(UUID)
    case home(UUID)
    case editHome(UUID)
}

/// Groups root tab values and behavior.
enum RootTab: String, CaseIterable, Identifiable, Hashable {
    case collections
    case homes
    case settings
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collections:
            return String(localized: "root_tab.collections")
        case .homes:
            return String(localized: "root_tab.homes")
        case .settings:
            return String(localized: "root_tab.settings")
        case .search:
            return String(localized: "common.ui.search")
        }
    }

    var systemImage: String {
        switch self {
        case .collections:
            return "rectangle.stack.fill"
        case .homes:
            return "house"
        case .settings:
            return "gearshape"
        case .search:
            return "magnifyingglass"
        }
    }
}

/// Displays the app shell view interface.
struct AppShellView: View {
    let repository: any CatalogRepository
    let coreDataContainer: NSPersistentCloudKitContainer
    @Environment(\.managedObjectContext) private var managedObjectContext
    @State private var catalogSnapshot: CatalogSnapshot?
    @State private var collectionsPath = NavigationPath()
    @State private var homesPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var selectedRootTab: RootTab = .collections
    @State private var displayName: String?
    @State private var shareInvitationFailureMessage: String?
    @ObservedObject private var shareInvitationController = CloudKitShareInvitationAcceptanceController.shared

    var body: some View {
        RootShellView(
            repository: repository,
            catalogSnapshot: catalogSnapshot,
            selectedRootTab: $selectedRootTab,
            collectionsPath: $collectionsPath,
            homesPath: $homesPath,
            settingsPath: $settingsPath,
            searchPath: $searchPath,
            displayName: $displayName,
            destination: { destination, layoutMode, onItemSelected, onBatchAddComplete, popNavigation in
                destinationView(
                    for: destination,
                    layoutMode: layoutMode,
                    onItemSelected: onItemSelected,
                    onBatchAddComplete: onBatchAddComplete,
                    popNavigation: popNavigation
                )
            }
        )
        .onAppear {
            reloadCatalogSnapshot()
            loadDisplayName()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: managedObjectContext
        )) { _ in
            reloadCatalogSnapshot()
        }
        .onChange(of: shareInvitationController.state) { _, state in
            handleShareInvitationState(state)
        }
        .overlay {
            ShareInvitationStatusOverlay(state: shareInvitationController.state)
        }
        .alert(
            "collection.sharing.accept_failed",
            isPresented: shareInvitationFailureAlertBinding
        ) {
            Button("common.ok") {
                shareInvitationFailureMessage = nil
                shareInvitationController.reset()
            }
        } message: {
            Text(shareInvitationFailureMessage ?? "")
        }
    }

    @ViewBuilder
    private func destinationView(
        for destination: AppDestination,
        layoutMode: Binding<CatalogCardLayoutMode>,
        onItemSelected: ((UUID) -> Void)?,
        onBatchAddComplete: @escaping BatchCompletionHandler,
        popNavigation: @escaping () -> Void
    ) -> some View {
        switch destination {
        case .collection(let collectionID):
            if let collection = collectionSummary(for: collectionID) {
                makeCollectionDestinationContent(
                    collection: collection,
                    catalogSnapshot: catalogSnapshot,
                    repository: repository,
                    coreDataContainer: coreDataContainer,
                    layoutMode: layoutMode,
                    onItemSelected: onItemSelected,
                    onBatchAddComplete: onBatchAddComplete
                )
            } else {
                CatalogEmptyStateView(
                    systemImage: "square.grid.2x2",
                    title: "collection.not_found.title",
                    message: "collection.not_found.message"
                )
            }
        case .home(let homeID):
            if let homeBinding = binding(for: homeID) {
                HomeDetailView(
                    home: homeBinding,
                    locations: locationsBinding(for: homeID),
                    collectionCount: collectionCount(in: homeID),
                    catalogSnapshot: catalogSnapshot,
                    onSave: { updatedHome, updatedLocations in
                        repository.saveHome(updatedHome)
                        repository.saveLocations(updatedLocations, in: updatedHome.id)
                    },
                    onDelete: {
                        repository.deleteHome(homeID: homeID)
                        popNavigation()
                    }
                )
            } else {
                CatalogEmptyStateView(
                    systemImage: "house.slash",
                    title: LocalizedStringKey(String(localized: "home.not_found.title")),
                    message: LocalizedStringKey(String(localized: "home.not_found.description"))
                )
            }
        case .editHome(let homeID):
            if let homeBinding = binding(for: homeID) {
                HomeEditorView(
                    home: homeBinding,
                    locations: locationsBinding(for: homeID),
                    onSave: {
                        saveHome(homeID)
                    },
                    onDelete: {
                        repository.deleteHome(homeID: homeID)
                        popNavigation()
                    },
                    embedsNavigation: false,
                    focusesNameOnAppear: true
                )
            } else {
                CatalogEmptyStateView(
                    systemImage: "house.slash",
                    title: LocalizedStringKey(String(localized: "home.not_found.title")),
                    message: LocalizedStringKey(String(localized: "home.not_found.description"))
                )
            }
        }
    }

    private var homes: [Home] {
        catalogSnapshot?.homes ?? []
    }

    private var locationsByHomeID: [UUID: [Location]] {
        catalogSnapshot?.locationsByHomeID ?? [:]
    }

    private func binding(for homeID: UUID) -> Binding<Home>? {
        guard homes.contains(where: { $0.id == homeID }) else { return nil }
        return Binding(
            get: { homes.first(where: { $0.id == homeID }) ?? Home(id: homeID, name: "", notes: "") },
            set: {
                repository.saveHome($0)
            }
        )
    }

    private func locationsBinding(for homeID: UUID) -> Binding<[Location]> {
        Binding(
            get: { locationsByHomeID[homeID] ?? [] },
            set: {
                repository.saveLocations($0, in: homeID)
            }
        )
    }

    private func collectionCount(in homeID: UUID) -> Int {
        catalogSnapshot?.collectionCountsByHomeID[homeID] ?? 0
    }

    private func collectionSummary(for collectionID: UUID) -> CollectionSummary? {
        catalogSnapshot?.collectionSummary(id: collectionID)
    }

    private func saveHome(_ homeID: UUID) {
        guard let home = homes.first(where: { $0.id == homeID }) else { return }
        repository.saveHome(home)
        repository.saveLocations(locationsByHomeID[homeID] ?? [], in: homeID)
    }

    private func reloadCatalogSnapshot() {
        catalogSnapshot = CatalogSnapshot.load(from: managedObjectContext)
    }

    private func loadDisplayName() {
        displayName = NSUbiquitousKeyValueStore.default.string(forKey: "foliora.profile.displayName")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shareInvitationFailureAlertBinding: Binding<Bool> {
        Binding(
            get: { shareInvitationFailureMessage != nil },
            set: { isPresented in
                guard !isPresented else { return }
                shareInvitationFailureMessage = nil
                shareInvitationController.reset()
            }
        )
    }

    private func handleShareInvitationState(_ state: CloudKitShareInvitationAcceptanceState) {
        switch state {
        case .idle, .accepting:
            break
        case .accepted:
            managedObjectContext.refreshAllObjects()
            reloadCatalogSnapshot()
            selectedRootTab = .collections
            collectionsPath = NavigationPath()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                if shareInvitationController.state == .accepted {
                    shareInvitationController.reset()
                }
            }
        case .failed(let message):
            shareInvitationFailureMessage = message
        }
    }
}

private struct RootShellView<Destination: View>: View {
    let repository: any CatalogRepository
    let catalogSnapshot: CatalogSnapshot?
    @Binding var selectedRootTab: RootTab
    @Binding var collectionsPath: NavigationPath
    @Binding var homesPath: NavigationPath
    @Binding var settingsPath: NavigationPath
    @Binding var searchPath: NavigationPath
    @Binding var displayName: String?
    let destination: (AppDestination, Binding<CatalogCardLayoutMode>, ((UUID) -> Void)?, @escaping BatchCompletionHandler, @escaping () -> Void) -> Destination
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("bellCatalog.layoutMode") private var layoutModeRawValue = CatalogCardLayoutMode.mini.rawValue
    @State private var searchInitialQuery: String?
    @State private var searchResetID = UUID()
    @State private var selectedItemID: UUID?

    private var layoutMode: CatalogCardLayoutMode {
        get {
            CatalogCardLayoutMode(rawValue: layoutModeRawValue) ?? .mini
        }
        nonmutating set {
            layoutModeRawValue = newValue.rawValue
        }
    }

    private var layoutModeBinding: Binding<CatalogCardLayoutMode> {
        Binding(
            get: { layoutMode },
            set: { layoutMode = $0 }
        )
    }

    private var isItemDetailPresented: Binding<Bool> {
        Binding(
            get: { selectedItemID != nil },
            set: { isPresented in
                if !isPresented {
                    selectedItemID = nil
                }
            }
        )
    }

    private var selectedRootTabSelection: Binding<RootTab?> {
        Binding(
            get: { selectedRootTab },
            set: { tab in
                if let tab {
                    selectedRootTab = tab
                }
            }
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
        TabView(selection: $selectedRootTab) {
            Tab(RootTab.collections.title, image: "ProductSymbol", value: RootTab.collections) {
                collectionsStack(path: $collectionsPath, onItemSelected: openItemDetail)
            }

            Tab(RootTab.homes.title, systemImage: RootTab.homes.systemImage, value: RootTab.homes) {
                homesStack(path: $homesPath, onItemSelected: openItemDetail)
            }

            Tab(RootTab.settings.title, systemImage: RootTab.settings.systemImage, value: RootTab.settings) {
                settingsStack(path: $settingsPath, onItemSelected: openItemDetail)
            }

            Tab(value: RootTab.search, role: .search) {
                NavigationStack(path: $searchPath) {
                    SearchView(
                        repository: repository,
                        layoutMode: layoutModeBinding,
                        catalogSnapshot: catalogSnapshot,
                        initialQuery: searchInitialQuery,
                        onItemSelected: openItemDetail
                    )
                    .id(searchResetID)
                }
            }
        }
        .modifier(ModernTabBarBehavior())
        .sheet(isPresented: isItemDetailPresented) {
            if let selectedItemID {
                makeItemDetailContent(
                    itemID: selectedItemID,
                    repository: repository,
                    catalogSnapshot: catalogSnapshot,
                    onClose: nil
                )
                .id(selectedItemID)
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var iPadRootContainer: some View {
        iPadSplitView
            .navigationSplitViewStyle(.balanced)
            .inspector(isPresented: isItemDetailPresented) {
                if let selectedItemID {
                    makeItemDetailContent(
                        itemID: selectedItemID,
                        repository: repository,
                        catalogSnapshot: catalogSnapshot,
                        onClose: closeItemDetail
                    )
                    .id(selectedItemID)
                    .inspectorColumnWidth(min: 320, ideal: 360, max: 420)
                } else {
                    EmptyView()
                }
            }
    }

    private var iPadSplitView: some View {
        NavigationSplitView {
            List(RootTab.allCases, selection: selectedRootTabSelection) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .navigationTitle(RootTab.collections.title)
            .onChange(of: selectedRootTab) { _, _ in
                closeItemDetail()
            }
        } detail: {
            iPadContent(for: selectedRootTab)
        }
    }

    @ViewBuilder
    private func iPadContent(for tab: RootTab) -> some View {
        switch tab {
        case .collections:
            collectionsStack(path: $collectionsPath, onItemSelected: openItemDetail)
        case .homes:
            homesStack(path: $homesPath, onItemSelected: openItemDetail)
        case .search:
            NavigationStack(path: $searchPath) {
                SearchView(
                    repository: repository,
                    layoutMode: layoutModeBinding,
                    catalogSnapshot: catalogSnapshot,
                    initialQuery: searchInitialQuery,
                    onItemSelected: openItemDetail
                )
                .id(searchResetID)
            }
        case .settings:
            settingsStack(path: $settingsPath, onItemSelected: openItemDetail)
        }
    }

    private func homesStack(
        path: Binding<NavigationPath>,
        onItemSelected: ((UUID) -> Void)?
    ) -> some View {
        NavigationStack(path: path) {
            HomeView(
                repository: repository,
                embedsNavigation: false,
                navigate: { path.wrappedValue.append($0) },
                catalogSnapshot: catalogSnapshot
            )
            .navigationDestination(for: AppDestination.self) { destination in
                self.destination(destination, layoutModeBinding, onItemSelected, handleBatchAddCompletion, popHomesNavigation)
            }
        }
    }

    private func collectionsStack(
        path: Binding<NavigationPath>,
        onItemSelected: ((UUID) -> Void)?
    ) -> some View {
        NavigationStack(path: path) {
            CollectionsView(
                repository: repository,
                catalogSnapshot: catalogSnapshot,
                navigate: { path.wrappedValue.append($0) },
                onOpenHomes: openHomesTab
            )
            .navigationDestination(for: AppDestination.self) { destination in
                self.destination(destination, layoutModeBinding, onItemSelected, handleBatchAddCompletion, popCollectionsNavigation)
            }
        }
    }

    private func settingsStack(
        path: Binding<NavigationPath>,
        onItemSelected: ((UUID) -> Void)?
    ) -> some View {
        NavigationStack(path: path) {
            SettingsView(
                repository: repository,
                navigate: { path.wrappedValue.append($0) },
                displayName: $displayName
            )
            .navigationDestination(for: AppDestination.self) { destination in
                self.destination(destination, layoutModeBinding, onItemSelected, handleBatchAddCompletion, popSettingsNavigation)
            }
        }
    }

    private func handleBatchAddCompletion(_ action: Any) {
        guard let query = reviewResultsQuery(from: action) else { return }
        searchInitialQuery = query
        searchResetID = UUID()
        selectedRootTab = .search
        closeItemDetail()
        searchPath = NavigationPath()
    }

    private func reviewResultsQuery(from action: Any) -> String? {
        guard case "reviewResults" = String(describing: action).split(separator: "(").first else {
            return nil
        }
        return Mirror(reflecting: action).children.first?.value as? String
    }

    private func popCollectionsNavigation() {
        if !collectionsPath.isEmpty {
            collectionsPath.removeLast()
        }
    }

    private func popHomesNavigation() {
        if !homesPath.isEmpty {
            homesPath.removeLast()
        }
    }

    private func popSettingsNavigation() {
        if !settingsPath.isEmpty {
            settingsPath.removeLast()
        }
    }

    private func openHomesTab() {
        selectedRootTab = .homes
    }

    private func openItemDetail(_ itemID: UUID) {
        selectedItemID = itemID
    }

    private func closeItemDetail() {
        selectedItemID = nil
    }
}

private struct ModernTabBarBehavior: ViewModifier {
    func body(content: Content) -> some View {
        content.tabBarMinimizeBehavior(.onScrollDown)
    }
}
