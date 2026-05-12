import SwiftUI
import MapKit
import PhotosUI
import SwiftData
import UIKit

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
    @StateObject private var externalRouteRouter = AppExternalRouteRouter()

    var body: some View {
        RootShellView(repository: repository)
            .environmentObject(externalRouteRouter)
    }
}

private struct RootShellView: View {
    let repository: any CatalogRepository
    @EnvironmentObject private var externalRouteRouter: AppExternalRouteRouter
    @State private var selectedTab = RootTab.collections

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(RootTab.collections.title, systemImage: RootTab.collections.systemImage, value: RootTab.collections) {
                CollectionsView(repository: repository)
            }

            Tab(RootTab.settings.title, systemImage: RootTab.settings.systemImage, value: RootTab.settings) {
                SettingsView(repository: repository)
            }

            Tab(value: RootTab.search, role: .search) {
                SearchTabView(repository: repository)
            }
        }
        .modifier(ModernTabBarBehavior())
        .tabViewSearchActivation(.searchTabSelection)
        .onOpenURL { url in
            // Paid-account Universal Links can enter here later; downstream routing already uses ExternalRouteKey.
            if let routeKey = try? TagPayloadParser().parse(url: url) {
                selectedTab = .collections
                externalRouteRouter.open(routeKey)
            }
        }
    }
}
private struct ModernTabBarBehavior: ViewModifier {
    func body(content: Content) -> some View {
        content.tabBarMinimizeBehavior(.onScrollDown)
    }
}

struct HomeView: View {
    let repository: any CatalogRepository
    let embedsNavigation: Bool
    @Query(sort: \HomeEntity.name) private var homeEntities: [HomeEntity]
    @Query(sort: \LocationEntity.name) private var locationEntities: [LocationEntity]
    @Query(sort: \CollectionEntity.title) private var collectionEntities: [CollectionEntity]
    @State private var path: [AppDestination] = []
    @State private var pendingDeleteHomeID: UUID?
    @State private var isPresentingDeleteConfirmation = false

    init(repository: any CatalogRepository, embedsNavigation: Bool = true) {
        self.repository = repository
        self.embedsNavigation = embedsNavigation
    }

    var body: some View {
        Group {
            if embedsNavigation {
                NavigationStack(path: $path) {
                    homeContent
                }
            } else {
                homeContent
            }
        }
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        homesSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentMargins(.horizontal, nil, for: .scrollContent)
                .contentMargins(.top, nil, for: .scrollContent)
                .contentMargins(.bottom, scrollContentBottomInset, for: .scrollContent)
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
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
                    let newHome = createHome()
                    if embedsNavigation {
                        path.append(.home(newHome.id))
                    }
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
        .navigationDestination(for: AppDestination.self) { destination in
            switch destination {
            case .collection:
                EmptyView()
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
                            path.removeAll { destination in
                                if case .home(let id) = destination { return id == homeID }
                                return false
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
    }

    private var homesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if homes.isEmpty {
                ContentUnavailableView(
                    String(localized: "home.empty.title"),
                    systemImage: "house.slash",
                    description: Text(String(localized: "home.empty.description"))
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 80)

                Button {
                    let newHome = createHome()
                    if embedsNavigation {
                        path.append(.home(newHome.id))
                    }
                } label: {
                    Label(String(localized: "home.add"), systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.20, green: 0.42, blue: 0.34))
            }
        }
    }

    @ViewBuilder
    private var homesRows: some View {
        ForEach(homes) { home in
            if embedsNavigation {
                Button {
                    path.append(.home(home.id))
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
            } else if let homeBinding = binding(for: home.id) {
                NavigationLink {
                    HomeDetailView(
                        home: homeBinding,
                        locations: locationsBinding(for: home.id),
                        collectionCount: collectionCount(in: home.id),
                        onSave: { updatedHome, updatedLocations in
                            repository.saveHome(updatedHome)
                            repository.saveLocations(updatedLocations, in: updatedHome.id)
                        },
                        onDelete: {
                            deleteHome(home.id)
                        }
                    )
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
        let newHome = Home(id: UUID(), name: String(localized: "home.new.default_name"), iconName: "house.fill", notes: "")
        repository.saveHome(newHome)
        repository.saveLocations([], in: newHome.id)
        return newHome
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
        path.removeAll { destination in
            if case .home(let id) = destination { return id == homeID }
            return false
        }
    }
}

private struct SettingsView: View {
    let repository: any CatalogRepository

    @State private var exportDocument: CatalogTransferDocument?
    @State private var isExportingDocument = false
    @State private var isImportingDocument = false
    @State private var isImportExportRunning = false
    @State private var importErrorMessage: String?
    @State private var importWarningMessage: String?
    @State private var exportErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        HomeView(repository: repository, embedsNavigation: false)
                    } label: {
                        Label(String(localized: "root_tab.homes"), systemImage: "house")
                    }
                } footer: {
                    Text(String(localized: "settings.storage.subtitle"))
                }

                Section {
                    Button {
                        exportCurrentBackup()
                    } label: {
                        Label(String(localized: "settings.data.export"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(isImportExportRunning)

                    Button {
                        isImportingDocument = true
                    } label: {
                        Label(String(localized: "settings.data.import"), systemImage: "square.and.arrow.down")
                    }
                    .disabled(isImportExportRunning)
                } header: {
                    Text(String(localized: "settings.data.section_title"))
                } footer: {
                    Text(String(localized: "settings.data.footer"))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(RootTab.settings.title)
            .fileExporter(
                isPresented: $isExportingDocument,
                document: exportDocument,
                contentType: .zip,
                defaultFilename: "catalog-export"
            ) { result in
                if case .failure(let error) = result {
                    exportErrorMessage = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $isImportingDocument,
                allowedContentTypes: [.zip]
            ) { result in
                handleImport(result)
            }
            .alert(String(localized: "settings.export.error_title"), isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        exportErrorMessage = nil
                    }
                }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? "")
            }
            .alert(String(localized: "settings.import.error_title"), isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        importErrorMessage = nil
                    }
                }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "")
            }
            .alert(String(localized: "settings.import.warning_title"), isPresented: Binding(
                get: { importWarningMessage != nil },
                set: { newValue in
                    if !newValue {
                        importWarningMessage = nil
                    }
                }
            )) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(importWarningMessage ?? "")
            }
        }
    }

    private func exportCurrentBackup() {
        isImportExportRunning = true
        Task {
            do {
                let actor = CatalogImportExportActor(modelContainer: repository.modelContainer)
                let data = try await actor.exportArchiveData()
                await MainActor.run {
                    exportDocument = CatalogTransferDocument(data: data)
                    isExportingDocument = true
                    isImportExportRunning = false
                }
            } catch {
                await MainActor.run {
                    exportErrorMessage = error.localizedDescription
                    isImportExportRunning = false
                }
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            isImportExportRunning = true
            Task {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    let actor = CatalogImportExportActor(modelContainer: repository.modelContainer)
                    let importResult = try await actor.importArchive(from: url)

                    await MainActor.run {
                        if !importResult.missingMediaIdentifiers.isEmpty {
                            importWarningMessage = String(localized: "settings.import.warning.missing_media")
                        }
                        isImportExportRunning = false
                    }
                } catch {
                    await MainActor.run {
                        importErrorMessage = error.localizedDescription
                        isImportExportRunning = false
                    }
                }
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }
}
