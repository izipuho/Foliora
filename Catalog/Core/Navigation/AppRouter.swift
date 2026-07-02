import SwiftUI
import CoreData

enum AppDestination: Hashable {
    case collection(CollectionSummary)
    case home(UUID)
    case editHome(UUID)
}

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
            return "square.grid.2x2"
        case .homes:
            return "house"
        case .settings:
            return "gearshape"
        case .search:
            return "magnifyingglass"
        }
    }
}

struct AppShellView: View {
    let repository: any CatalogRepository
    let coreDataContainer: NSPersistentCloudKitContainer
    @Environment(\.managedObjectContext) private var managedObjectContext
    @State private var navigationSnapshot: CatalogSnapshot?
    @State private var collectionsPath = NavigationPath()
    @State private var homesPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var selectedRootTab: RootTab = .collections
    @State private var shareInvitationFailureMessage: String?
    @ObservedObject private var shareInvitationController = CloudKitShareInvitationAcceptanceController.shared

    var body: some View {
        RootShellView(
            repository: repository,
            navigationSnapshot: navigationSnapshot,
            reloadNavigationSnapshot: reloadNavigationSnapshot,
            selectedRootTab: $selectedRootTab,
            collectionsPath: $collectionsPath,
            homesPath: $homesPath,
            settingsPath: $settingsPath,
            searchPath: $searchPath,
            destination: { destination, layoutMode, onBellSelected, onBatchAddComplete, popNavigation in
                destinationView(
                    for: destination,
                    layoutMode: layoutMode,
                    onBellSelected: onBellSelected,
                    onBatchAddComplete: onBatchAddComplete,
                    popNavigation: popNavigation
                )
            }
        )
        .onAppear(perform: reloadNavigationSnapshot)
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: managedObjectContext
        )) { _ in
            reloadNavigationSnapshot()
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
            Button("OK") {
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
        layoutMode: Binding<BellGridLayoutMode>,
        onBellSelected: ((UUID) -> Void)?,
        onBatchAddComplete: @escaping (BatchAddCompletionAction) -> Void,
        popNavigation: @escaping () -> Void
    ) -> some View {
        switch destination {
        case .collection(let collection):
            CollectionShellView(
                collection: collection,
                repository: repository,
                coreDataContainer: coreDataContainer,
                layoutMode: layoutMode,
                onBellSelected: onBellSelected,
                onBatchAddComplete: onBatchAddComplete
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
                        reloadNavigationSnapshot()
                    },
                    onDelete: {
                        repository.deleteHome(homeID: homeID)
                        reloadNavigationSnapshot()
                        popNavigation()
                    }
                )
            } else {
                ContentUnavailableView(
                    String(localized: "home.not_found.title"),
                    systemImage: "house.slash",
                    description: Text(String(localized: "home.not_found.description"))
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
                        reloadNavigationSnapshot()
                        popNavigation()
                    },
                    embedsNavigation: false,
                    focusesNameOnAppear: true
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
        navigationSnapshot?.homes ?? []
    }

    private var locationsByHomeID: [UUID: [Location]] {
        navigationSnapshot?.locationsByHomeID ?? [:]
    }

    private func binding(for homeID: UUID) -> Binding<Home>? {
        guard homes.contains(where: { $0.id == homeID }) else { return nil }
        return Binding(
            get: { homes.first(where: { $0.id == homeID }) ?? Home(id: homeID, name: "", notes: "") },
            set: {
                repository.saveHome($0)
                reloadNavigationSnapshot()
            }
        )
    }

    private func locationsBinding(for homeID: UUID) -> Binding<[Location]> {
        Binding(
            get: { locationsByHomeID[homeID] ?? [] },
            set: {
                repository.saveLocations($0, in: homeID)
                reloadNavigationSnapshot()
            }
        )
    }

    private func collectionCount(in homeID: UUID) -> Int {
        navigationSnapshot?.collectionCountsByHomeID[homeID] ?? 0
    }

    private func saveHome(_ homeID: UUID) {
        guard let home = homes.first(where: { $0.id == homeID }) else { return }
        repository.saveHome(home)
        repository.saveLocations(locationsByHomeID[homeID] ?? [], in: homeID)
        reloadNavigationSnapshot()
    }

    private func reloadNavigationSnapshot() {
        navigationSnapshot = CatalogSnapshot.load(from: managedObjectContext)
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
            reloadNavigationSnapshot()
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

private struct ShareInvitationStatusOverlay: View {
    let state: CloudKitShareInvitationAcceptanceState

    var body: some View {
        switch state {
        case .accepting:
            statusCard {
                ProgressView()
                Text("collection.sharing.accepting")
                    .font(.headline)
            }
        case .accepted:
            statusCard {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                Text("collection.sharing.access_granted")
                    .font(.headline)
            }
        case .idle, .failed:
            EmptyView()
        }
    }

    private func statusCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: CatalogMetrics.Spacing.md) {
            content()
        }
        .padding(.horizontal, CatalogMetrics.Spacing.xl)
        .padding(.vertical, CatalogMetrics.Spacing.lg)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.thumbnail, style: .continuous))
        .shadow(radius: 18)
    }
}

private struct RootShellView<Destination: View>: View {
    let repository: any CatalogRepository
    let navigationSnapshot: CatalogSnapshot?
    let reloadNavigationSnapshot: () -> Void
    @Binding var selectedRootTab: RootTab
    @Binding var collectionsPath: NavigationPath
    @Binding var homesPath: NavigationPath
    @Binding var settingsPath: NavigationPath
    @Binding var searchPath: NavigationPath
    let destination: (AppDestination, Binding<BellGridLayoutMode>, ((UUID) -> Void)?, @escaping (BatchAddCompletionAction) -> Void, @escaping () -> Void) -> Destination
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("bellCatalog.layoutMode") private var layoutModeRawValue = BellGridLayoutMode.mini.rawValue
    @State private var searchInitialQuery: String?
    @State private var searchResetID = UUID()
    @State private var selectedBellID: UUID?

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

    private var isBellInspectorPresented: Binding<Bool> {
        Binding(
            get: { selectedBellID != nil },
            set: { isPresented in
                if !isPresented {
                    selectedBellID = nil
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
            Tab(RootTab.collections.title, systemImage: RootTab.collections.systemImage, value: RootTab.collections) {
                collectionsStack(path: $collectionsPath, onBellSelected: nil)
            }

            Tab(RootTab.homes.title, systemImage: RootTab.homes.systemImage, value: RootTab.homes) {
                homesStack(path: $homesPath, onBellSelected: nil)
            }

            Tab(RootTab.settings.title, systemImage: RootTab.settings.systemImage, value: RootTab.settings) {
                settingsStack(path: $settingsPath, onBellSelected: nil)
            }

            Tab(value: RootTab.search, role: .search) {
                NavigationStack(path: $searchPath) {
                    SearchTabView(
                        repository: repository,
                        layoutMode: layoutModeBinding,
                        initialQuery: searchInitialQuery
                    )
                    .id(searchResetID)
                }
            }
        }
        .modifier(ModernTabBarBehavior())
    }

    private var iPadRootContainer: some View {
        iPadSplitView
            .navigationSplitViewStyle(.balanced)
            .inspector(isPresented: isBellInspectorPresented) {
                if let selectedBellID {
                    BellDetailInspectorView(
                        bellID: selectedBellID,
                        repository: repository,
                        onClose: closeBellInspector
                    )
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
                closeBellInspector()
            }
        } detail: {
            iPadContent(for: selectedRootTab)
        }
    }

    @ViewBuilder
    private func iPadContent(for tab: RootTab) -> some View {
        switch tab {
        case .collections:
            collectionsStack(path: $collectionsPath, onBellSelected: openBellInspector)
        case .homes:
            homesStack(path: $homesPath, onBellSelected: openBellInspector)
        case .search:
            NavigationStack(path: $searchPath) {
                SearchTabView(
                    repository: repository,
                    layoutMode: layoutModeBinding,
                    initialQuery: searchInitialQuery,
                    onBellSelected: openBellInspector
                )
                .id(searchResetID)
            }
        case .settings:
            settingsStack(path: $settingsPath, onBellSelected: openBellInspector)
        }
    }

    private func homesStack(
        path: Binding<NavigationPath>,
        onBellSelected: ((UUID) -> Void)?
    ) -> some View {
        NavigationStack(path: path) {
            HomeView(
                repository: repository,
                embedsNavigation: false,
                navigate: { path.wrappedValue.append($0) },
                navigationSnapshot: navigationSnapshot,
                reloadNavigationSnapshot: reloadNavigationSnapshot
            )
            .navigationDestination(for: AppDestination.self) { destination in
                self.destination(destination, layoutModeBinding, onBellSelected, handleBatchAddCompletion, popHomesNavigation)
            }
        }
    }

    private func collectionsStack(
        path: Binding<NavigationPath>,
        onBellSelected: ((UUID) -> Void)?
    ) -> some View {
        NavigationStack(path: path) {
            CollectionsView(
                repository: repository,
                navigate: { path.wrappedValue.append($0) },
                onOpenHomes: openHomesTab
            )
            .navigationDestination(for: AppDestination.self) { destination in
                self.destination(destination, layoutModeBinding, onBellSelected, handleBatchAddCompletion, popCollectionsNavigation)
            }
        }
    }

    private func settingsStack(
        path: Binding<NavigationPath>,
        onBellSelected: ((UUID) -> Void)?
    ) -> some View {
        NavigationStack(path: path) {
            SettingsView(
                repository: repository,
                navigate: { path.wrappedValue.append($0) }
            )
            .navigationDestination(for: AppDestination.self) { destination in
                self.destination(destination, layoutModeBinding, onBellSelected, handleBatchAddCompletion, popSettingsNavigation)
            }
        }
    }

    private func handleBatchAddCompletion(_ action: BatchAddCompletionAction) {
        guard case .reviewResults(let query) = action else { return }
        searchInitialQuery = query
        searchResetID = UUID()
        selectedRootTab = .search
        closeBellInspector()
        searchPath = NavigationPath()
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

    private func openBellInspector(_ bellID: UUID) {
        selectedBellID = bellID
    }

    private func closeBellInspector() {
        selectedBellID = nil
    }
}

private struct BellDetailInspectorView: View {
    let bellID: UUID
    let repository: any CatalogRepository
    let onClose: () -> Void
    @Environment(\.managedObjectContext) private var managedObjectContext
    @State private var bell: BellRecord?

    init(
        bellID: UUID,
        repository: any CatalogRepository,
        onClose: @escaping () -> Void
    ) {
        self.bellID = bellID
        self.repository = repository
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            Group {
                if let bellBinding {
                    BellDetailView(
                        bell: bellBinding,
                        repository: repository,
                        canEditCollection: false
                    )
                } else {
                    ContentUnavailableView("bel.not_found", systemImage: "bell.slash")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .task(id: bellID) {
            reloadBell()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: managedObjectContext
        )) { _ in
            reloadBell()
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

    private func reloadBell() {
        let snapshot = CoreDataBellLookupSnapshotLoader(context: managedObjectContext).loadSnapshot()
        bell = snapshot.bells.first { $0.id == bellID }
    }
}

private struct ModernTabBarBehavior: ViewModifier {
    func body(content: Content) -> some View {
        content.tabBarMinimizeBehavior(.onScrollDown)
    }
}
