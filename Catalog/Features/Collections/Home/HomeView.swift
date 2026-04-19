import SwiftUI
import MapKit
import PhotosUI
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

enum CollectionContentMode: String, CaseIterable, Identifiable {
    case summary
    case items
    case map

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary:
            return String(localized: "collection_tab.summary")
        case .items:
            return String(localized: "collection_tab.items")
        case .map:
            return String(localized: "collection_tab.map")
        }
    }
}

struct AppShellView: View {
    let repository: any CatalogRepository

    var body: some View {
        RootShellView(repository: repository)
    }
}

private struct RootShellView: View {
    let repository: any CatalogRepository

    var body: some View {
        TabView {
            Tab(RootTab.collections.title, systemImage: RootTab.collections.systemImage) {
                CollectionsView(repository: repository)
            }

            Tab(RootTab.settings.title, systemImage: RootTab.settings.systemImage) {
                SettingsView(repository: repository)
            }

            Tab(role: .search) {
                SearchTabView(repository: repository)
            }
        }
        .modifier(ModernTabBarBehavior())
        .tabViewSearchActivation(.searchTabSelection)
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
    @State private var path: [AppDestination] = []
    @State private var homes: [Home]
    @State private var locationsByHomeID: [UUID: [Location]]
    @State private var pendingDeleteHomeID: UUID?
    @State private var isPresentingDeleteConfirmation = false

    init(repository: any CatalogRepository, embedsNavigation: Bool = true) {
        self.repository = repository
        self.embedsNavigation = embedsNavigation
        let initialHomes = repository.fetchHomes()
        _homes = State(initialValue: initialHomes)
        _locationsByHomeID = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: initialHomes.map { home in
                    (home.id, repository.fetchLocations(in: home.id))
                }
            )
        )
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
                    .listRowBackground(Color.clear)
                    .listRowInsets(.top, 0)
                    .listRowInsets(.bottom, 0)
                }
                .listStyle(.plain)
                .contentMargins(.horizontal, nil, for: .scrollContent)
                .contentMargins(.top, nil, for: .scrollContent)
                .contentMargins(.bottom, scrollContentBottomInset, for: .scrollContent)
                .scrollContentBackground(.hidden)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let newHome = Home(id: UUID(), name: String(localized: "home.new.default_name"), notes: "")
                    homes.append(newHome)
                    locationsByHomeID[newHome.id] = []
                    repository.saveHome(newHome)
                    repository.saveLocations([], in: newHome.id)
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
                        collectionCount: repository.fetchCollections().count,
                        onSave: { updatedHome, updatedLocations in
                            repository.saveHome(updatedHome)
                            repository.saveLocations(updatedLocations, in: updatedHome.id)
                        },
                        onDelete: {
                            repository.deleteHome(homeID: homeID)
                            homes.removeAll { $0.id == homeID }
                            locationsByHomeID[homeID] = nil
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
                    let newHome = Home(id: UUID(), name: String(localized: "home.new.default_name"), notes: "")
                    homes.append(newHome)
                    locationsByHomeID[newHome.id] = []
                    repository.saveHome(newHome)
                    repository.saveLocations([], in: newHome.id)
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
                        collectionCount: repository.fetchCollections().count
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
                        collectionCount: repository.fetchCollections().count,
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
                        collectionCount: repository.fetchCollections().count
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
                    collectionCount: repository.fetchCollections().count
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
        guard let index = homes.firstIndex(where: { $0.id == homeID }) else { return nil }
        return $homes[index]
    }

    private func locationsBinding(for homeID: UUID) -> Binding<[Location]> {
        Binding(
            get: { locationsByHomeID[homeID] ?? [] },
            set: { locationsByHomeID[homeID] = $0 }
        )
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
        homes.removeAll { $0.id == homeID }
        locationsByHomeID[homeID] = nil
        path.removeAll { destination in
            if case .home(let id) = destination { return id == homeID }
            return false
        }
    }
}

private struct HomeDetailView: View {
    @Binding var home: Home
    @Binding var locations: [Location]
    let collectionCount: Int
    let onSave: (Home, [Location]) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingEditor = false
    @State private var isPresentingDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HomeCard(
                    home: home,
                    locations: locations,
                    collectionCount: collectionCount,
                    onEdit: {
                        isPresentingEditor = true
                    },
                    onDelete: {
                        isPresentingDeleteConfirmation = true
                    }
                )

                Text(String(localized: "home.details"))
                    .font(.headline)
                    .padding(.horizontal, CatalogSpacing.micro)

                StorageMapCard(locations: locations)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentMargins(.horizontal, nil, for: .scrollContent)
        .contentMargins(.top, nil, for: .scrollContent)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
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
        .navigationTitle(home.name)
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isPresentingEditor) {
            HomeEditorView(
                home: $home,
                locations: $locations,
                onSave: {
                    onSave(home, locations)
                },
                onDelete: {
                    onDelete()
                    dismiss()
                }
            )
        }
        .confirmationDialog(
            String(localized: "home.delete.title"),
            isPresented: $isPresentingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "home.delete.confirm"), role: .destructive) {
                onDelete()
                dismiss()
            }

            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "home.delete.message"))
        }
    }
}

private struct HomeEditorView: View {
    @Binding var home: Home
    @Binding var locations: [Location]
    let onSave: () -> Void
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "home.editor.section_home")) {
                    TextField(
                        String(localized: "common.name"),
                        text: $home.name
                    )

                    TextField(
                        String(localized: "common.notes"),
                        text: $home.notes,
                        axis: .vertical
                    )
                    .lineLimit(3, reservesSpace: true)
                }

                Section(String(localized: "home.editor.section_locations")) {
                    if locations.isEmpty {
                        ContentUnavailableView(
                            String(localized: "home.location.empty.title"),
                            systemImage: "square.stack.3d.up.slash",
                            description: Text(String(localized: "home.location.empty.description"))
                        )
                    } else {
                        ForEach($locations) { $location in
                            VStack(alignment: .leading, spacing: 10) {
                                TextField(String(localized: "home.location.name"), text: $location.name)

                                Picker(
                                    String(localized: "home.location.kind"),
                                    selection: Binding(
                                        get: { location.kind },
                                        set: { newKind in
                                            location.kind = newKind
                                            if !hasValidParent(location) {
                                                location.parentLocationID = nil
                                            }
                                        }
                                    )
                                ) {
                                    ForEach(LocationKind.allCases) { kind in
                                        Text(kind.displayName).tag(kind)
                                    }
                                }

                                Picker(
                                    String(localized: "home.location.parent"),
                                    selection: Binding(
                                        get: { location.parentLocationID },
                                        set: { newValue in
                                            if let newValue,
                                               let candidate = locations.first(where: { $0.id == newValue }),
                                               isValidParent(candidate, for: location) {
                                                location.parentLocationID = newValue
                                            } else {
                                                location.parentLocationID = nil
                                            }
                                        }
                                    )
                                ) {
                                    Text(String(localized: "common.none")).tag(Optional<UUID>.none)
                                    ForEach(parentCandidates(for: location)) { candidate in
                                        Text(candidate.name).tag(Optional(candidate.id))
                                    }
                                }

                                TextField(String(localized: "common.notes"), text: $location.notes, axis: .vertical)
                                    .lineLimit(2, reservesSpace: true)
                            }
                            .padding(.vertical, CatalogSpacing.compact)
                        }
                        .onDelete(perform: deleteLocations)
                    }

                    Button {
                        addLocation()
                    } label: {
                        Label(String(localized: "home.location.add"), systemImage: "plus.circle.fill")
                    }
                }

                if onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            isPresentingDeleteConfirmation = true
                        } label: {
                            Label(String(localized: "common.delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "home.editor.title"))
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
                    Button {
                        locations = normalizedLocations()
                        onSave()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .confirmationDialog(
                String(localized: "home.delete.title"),
                isPresented: $isPresentingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "home.delete.confirm"), role: .destructive) {
                    onDelete?()
                    dismiss()
                }

                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "home.delete.message"))
            }
        }
    }

    private func addLocation() {
        locations.append(
            Location(
                id: UUID(),
                homeID: home.id,
                parentLocationID: nil,
                kind: .room,
                name: String(localized: "home.location.new_default_name"),
                notes: ""
            )
        )
    }

    private func deleteLocations(at offsets: IndexSet) {
        let removedIDs = Set(offsets.map { locations[$0].id })
        locations.remove(atOffsets: offsets)
        locations = locations.map { location in
            guard removedIDs.contains(location.parentLocationID ?? UUID()) else {
                return location
            }

            var copy = location
            copy.parentLocationID = nil
            return copy
        }
    }

    private func parentCandidates(for location: Location) -> [Location] {
        locations
            .filter { candidate in
                isValidParent(candidate, for: location)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func normalizedLocations() -> [Location] {
        locations.map { location in
            guard hasValidParent(location) else {
                var copy = location
                copy.parentLocationID = nil
                return copy
            }

            return location
        }
    }

    private func hasValidParent(_ location: Location) -> Bool {
        guard let parentID = location.parentLocationID else { return true }
        guard let parent = locations.first(where: { $0.id == parentID }) else { return false }
        return isValidParent(parent, for: location)
    }

    private func isValidParent(_ candidate: Location, for location: Location) -> Bool {
        guard candidate.id != location.id else { return false }
        guard candidate.homeID == location.homeID else { return false }
        guard location.kind.canBeChild(of: candidate.kind) else { return false }
        guard !isDescendant(candidateID: candidate.id, of: location.id) else { return false }
        return true
    }

    private func isDescendant(candidateID: UUID, of locationID: UUID) -> Bool {
        var currentParentID = locations.first(where: { $0.id == candidateID })?.parentLocationID

        while let parentID = currentParentID {
            if parentID == locationID {
                return true
            }

            currentParentID = locations.first(where: { $0.id == parentID })?.parentLocationID
        }

        return false
    }
}

private struct HomeListCard: View {
    let home: Home
    let locations: [Location]
    let collectionCount: Int

    private var floors: Int {
        locations.filter { $0.kind == .floor }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: CatalogCornerRadii.medium, style: .continuous)
                        .fill(Color(red: 0.20, green: 0.42, blue: 0.34).opacity(0.12))
                        .frame(width: 54, height: 54)

                    Image(systemName: "house.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(red: 0.20, green: 0.42, blue: 0.34))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(home.name)
                        .font(.title3.bold())

                    Text(home.notes.isEmpty ? String(localized: "common.no_notes") : home.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                listMetric(title: String(localized: "home.metric.collections"), value: "\(collectionCount)")
                listMetric(title: String(localized: "home.metric.locations"), value: "\(locations.count)")
                listMetric(title: String(localized: "home.metric.floors"), value: "\(floors)")
            }
        }
        .padding(CatalogLayoutInsets.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.hero, style: .continuous))
        .catalogShadow(CatalogElevation.floatingCard)
    }

    private func listMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: CatalogSpacing.micro) {
            Text(value)
                .font(.headline.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CatalogSpacing.regular)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous))
    }
}

struct CollectionsView: View {
    let repository: any CatalogRepository
    @State private var collections: [CollectionSummary]
    @State private var path: [AppDestination] = []
    @State private var isPresentingAddCollectionEditor = false
    @State private var didAutoOpenSingleCollection = false

    init(repository: any CatalogRepository) {
        self.repository = repository
        _collections = State(initialValue: repository.fetchCollections())
    }

    var body: some View {
        NavigationStack(path: $path) {
            collectionsRoot
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
                .onAppear {
                    collections = repository.fetchCollections()
                    autoOpenSingleCollectionIfNeeded()
                }
                .onChange(of: collections.map(\.id)) { _, _ in
                    didAutoOpenSingleCollection = false
                    autoOpenSingleCollectionIfNeeded()
                }
                .navigationTitle(RootTab.collections.title)
                .sheet(isPresented: $isPresentingAddCollectionEditor) {
                    CollectionEditorView(
                        homes: repository.fetchHomes(),
                        initialHomeID: repository.fetchHomes().first?.id
                    ) { title, notes, homeID, backgroundStyle in
                        addCollection(title: title, notes: notes, homeID: homeID, backgroundStyle: backgroundStyle)
                    }
                }
                .navigationDestination(for: AppDestination.self) { destination in
                    switch destination {
                    case .collection(let collection):
                        CollectionShellView(collection: collection, repository: repository)
                    case .home:
                        EmptyView()
                    }
                }
        }
    }

    @ViewBuilder
    private var collectionsRoot: some View {
        if collections.isEmpty {
            emptyCollectionsView
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(collections) { collection in
                        Button {
                            path.append(.collection(collection))
                        } label: {
                            CollectionCard(collection: collection)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.horizontal, nil, for: .scrollContent)
            .contentMargins(.top, nil, for: .scrollContent)
            .contentMargins(.bottom, 120, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingAddCollectionEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    private var emptyCollectionsView: some View {
        VStack(spacing: 24) {
            ContentUnavailableView(
                String(localized: "collections.empty.title"),
                systemImage: "square.grid.2x2",
                description: Text(String(localized: "collections.empty.description"))
            )
            .frame(maxWidth: .infinity)

            Button {
                isPresentingAddCollectionEditor = true
            } label: {
                Label(String(localized: "collections.add"), systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.53, green: 0.31, blue: 0.14))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal)
        .padding(.bottom, 80)
    }

    private func addCollection(title: String, notes: String, homeID: UUID, backgroundStyle: CollectionBackgroundStyle) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let collection = Collection(
            id: UUID(),
            homeID: homeID,
            kind: .bells,
            title: trimmedTitle.isEmpty ? String(localized: "collection.editor.default_title") : trimmedTitle,
            notes: trimmedNotes,
            backgroundStyle: backgroundStyle
        )

        repository.saveCollection(collection)
        collections = repository.fetchCollections()
        if let createdCollection = collections.first(where: { $0.id == collection.id }) {
            didAutoOpenSingleCollection = true
            path.append(.collection(createdCollection))
        }
    }

    private func autoOpenSingleCollectionIfNeeded() {
        guard collections.count == 1 else { return }
        guard !didAutoOpenSingleCollection else { return }
        guard let collection = collections.first else { return }

        didAutoOpenSingleCollection = true
        path.append(.collection(collection))
    }
}

struct CollectionEditorView: View {
    let homes: [Home]
    let allowsHomeSelection: Bool
    let onSave: (String, String, UUID, CollectionBackgroundStyle) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var selectedHomeID: UUID?
    @State private var backgroundStyle: CollectionBackgroundStyle = .amber
    @State private var isPresentingDeleteConfirmation = false
    private let screenTitle: String
    private let allowsDeletion: Bool

    init(
        homes: [Home],
        screenTitle: String = "",
        initialTitle: String = "",
        initialNotes: String = "",
        initialHomeID: UUID? = nil,
        initialBackgroundStyle: CollectionBackgroundStyle = .amber,
        allowsHomeSelection: Bool = true,
        allowsDeletion: Bool = false,
        onSave: @escaping (String, String, UUID, CollectionBackgroundStyle) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.homes = homes
        self.allowsHomeSelection = allowsHomeSelection
        self.screenTitle = screenTitle
        self.allowsDeletion = allowsDeletion
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: initialTitle)
        _notes = State(initialValue: initialNotes)
        _selectedHomeID = State(initialValue: initialHomeID ?? homes.first?.id)
        _backgroundStyle = State(initialValue: initialBackgroundStyle)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedHomeID != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "collection.editor.section_type")) {
                    HStack {
                        Label(String(localized: "collection.editor.type_name_localized"), systemImage: "bell.fill")
                        Spacer()
                        Text(String(localized: "collection.editor.type_name_english"))
                            .foregroundStyle(.secondary)
                    }
                }

                Section(String(localized: "collection.editor.section_collection")) {
                    TextField(String(localized: "common.name"), text: $title)
                    TextField(String(localized: "common.notes"), text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                Section(String(localized: "collection.editor.section_home")) {
                    if homes.isEmpty {
                        Text(String(localized: "collection.editor.no_home"))
                            .foregroundStyle(.secondary)
                    } else if allowsHomeSelection {
                        Picker(String(localized: "home.screen.title"), selection: $selectedHomeID) {
                            ForEach(homes) { home in
                                Text(home.name).tag(Optional(home.id))
                            }
                        }
                    } else {
                        HStack {
                            Text(String(localized: "home.screen.title"))
                            Spacer()
                            Text(homes.first(where: { $0.id == selectedHomeID })?.name ?? String(localized: "common.unknown"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(String(localized: "collection.editor.section_background")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 74, maximum: 110), spacing: 12)], spacing: 12) {
                        ForEach(CollectionBackgroundStyle.allCases) { style in
                            Button {
                                backgroundStyle = style
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: style.colors,
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(height: 64)
                                        .overlay(alignment: .topTrailing) {
                                            if backgroundStyle == style {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.title3)
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, CatalogMediaContrast.iconPaletteShadowSoft)
                                                    .padding(CatalogSpacing.compact)
                                            }
                                        }

                                    Text(style.title)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if allowsDeletion {
                    Section {
                        Button(role: .destructive) {
                            isPresentingDeleteConfirmation = true
                        } label: {
                            Label(String(localized: "common.delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(screenTitle)
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
                    Button {
                        guard let selectedHomeID else { return }
                        onSave(title, notes, selectedHomeID, backgroundStyle)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave)
                }
            }
            .confirmationDialog(
                String(localized: "collection.delete.title"),
                isPresented: $isPresentingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "collection.delete.confirm"), role: .destructive) {
                    onDelete?()
                    dismiss()
                }

                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "collection.delete.message"))
            }
        }
    }
}

private struct CollectionShellView: View {
    let repository: any CatalogRepository
    @Environment(\.dismiss) private var dismiss
    @State private var collection: CollectionSummary
    @State private var selectedMode: CollectionContentMode = .summary
    @State private var refreshID = UUID()
    @State private var isPresentingAddBell = false
    @State private var isPresentingAddBellOptions = false
    @State private var isPresentingPhotoPicker = false
    @State private var isPresentingCamera = false
    @State private var shouldPresentEditorAfterCamera = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var draftMediaAssets: [MediaAsset] = []
    @State private var isPresentingEditCollection = false
    @State private var selectedOrder: BellOrderMode = .title
    @State private var selectedLayoutMode: BellGridLayoutMode = .compact
    @State private var selectedSummaryFilter: BellSummaryFilter?
    private let mediaStore = LocalMediaFileStore.shared

    init(collection: CollectionSummary, repository: any CatalogRepository) {
        self.repository = repository
        _collection = State(initialValue: collection)
    }

    var body: some View {
        Group {
            switch selectedMode {
            case .summary:
                BellCatalogView(
                    collection: collection,
                    repository: repository,
                    collaborators: repository.fetchCollaborators(for: collection.id),
                    mode: .summary,
                    layoutMode: .constant(.compact),
                    orderMode: .title,
                    onSelectSummaryFilter: { filter in
                        selectedSummaryFilter = filter
                        selectedMode = .items
                    }
                )
                .id("summary-\(refreshID.uuidString)")
            case .items:
                BellCatalogView(
                    collection: collection,
                    repository: repository,
                    collaborators: repository.fetchCollaborators(for: collection.id),
                    mode: .items,
                    layoutMode: $selectedLayoutMode,
                    orderMode: selectedOrder,
                    summaryFilter: selectedSummaryFilter,
                    onClearSummaryFilter: {
                        selectedSummaryFilter = nil
                    }
                )
                .id("items-\(refreshID.uuidString)")
            case .map:
                CollectionOriginMapView(
                    collection: collection,
                    repository: repository
                )
                .id("map-\(refreshID.uuidString)")
            }
        }
        .safeAreaInset(edge: .top) {
            collectionModePicker
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if selectedMode == .items {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker(String(localized: "bell_catalog.order.menu"), selection: $selectedOrder) {
                            ForEach(BellOrderMode.allCases, id: \.self) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    } label: {
                        floatingToolbarIcon(systemName: "line.3.horizontal.decrease")
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingEditCollection = true
                } label: {
                    floatingToolbarIcon(systemName: "slider.horizontal.3")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingAddBellOptions = true
                } label: {
                    floatingToolbarIcon(systemName: "plus")
                }
                .confirmationDialog(String(localized: "editor.media.add"), isPresented: $isPresentingAddBellOptions, titleVisibility: .visible) {
                    Button(String(localized: "editor.media.photo_library")) {
                        isPresentingPhotoPicker = true
                    }

                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button(String(localized: "editor.media.camera")) {
                            isPresentingCamera = true
                        }
                    }

                    Button(String(localized: "common.cancel"), role: .cancel) {}
                }
            }
        }
        .photosPicker(
            isPresented: $isPresentingPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 1,
            matching: .images,
            photoLibrary: .shared()
        )
        .fullScreenCover(isPresented: $isPresentingCamera) {
            CollectionAddBellCameraPicker { image in
                addCapturedPhotoAndPresentEditor(image)
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task {
                await addDraftPhotosAndPresentEditor(from: newItems)
            }
        }
        .onChange(of: isPresentingCamera) { _, isPresented in
            if !isPresented, shouldPresentEditorAfterCamera, !draftMediaAssets.isEmpty {
                shouldPresentEditorAfterCamera = false
                isPresentingAddBell = true
            }
        }
        .sheet(isPresented: $isPresentingAddBell, onDismiss: {
            draftMediaAssets = []
        }) {
            BellEditorView(
                collection: collection,
                repository: repository,
                initialMediaAssets: draftMediaAssets
            ) { newBell in
                repository.saveBellRecord(newBell)
                refreshContent()
                selectedMode = .items
            }
        }
        .sheet(isPresented: $isPresentingEditCollection) {
            CollectionEditorView(
                homes: repository.fetchHomes(),
                screenTitle: String(localized: "collection.editor.edit_title"),
                initialTitle: collection.name,
                initialNotes: collection.subtitle,
                initialHomeID: collection.homeID,
                initialBackgroundStyle: collection.backgroundStyle,
                allowsHomeSelection: false,
                allowsDeletion: true
            ) { title, notes, _, backgroundStyle in
                saveCollectionEdits(title: title, notes: notes, backgroundStyle: backgroundStyle)
            } onDelete: {
                repository.deleteCollection(collectionID: collection.id)
                dismiss()
            }
        }
    }

    private var collectionModePicker: some View {
        HStack {
            Spacer(minLength: 0)

            HStack {
                Picker("Collection Mode", selection: $selectedMode) {
                    ForEach(CollectionContentMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .pickerStyle(.segmented)
            }
            .padding(CatalogSpacing.micro)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(CatalogMediaContrast.glassStroke, lineWidth: 1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, CatalogLayoutInsets.screen)
        .padding(.top, CatalogSpacing.compact)
        .padding(.bottom, CatalogSpacing.micro)
    }

    private func floatingToolbarIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 34, height: 34)
    }

    private func saveCollectionEdits(title: String, notes: String, backgroundStyle: CollectionBackgroundStyle) {
        guard let domainCollection = repository
            .fetchHomes()
            .flatMap({ repository.fetchDomainCollections(in: $0.id) })
            .first(where: { $0.id == collection.id })
        else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedCollection = Collection(
            id: domainCollection.id,
            homeID: domainCollection.homeID,
            kind: domainCollection.kind,
            title: trimmedTitle.isEmpty ? domainCollection.title : trimmedTitle,
            notes: trimmedNotes,
            backgroundStyle: backgroundStyle
        )

        repository.saveCollection(updatedCollection)
        refreshContent()
    }

    private func refreshContent() {
        if let refreshed = repository.fetchCollections().first(where: { $0.id == collection.id }) {
            collection = refreshed
        }
        refreshID = UUID()
    }

    @MainActor
    private func addDraftPhotosAndPresentEditor(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        var newAssets: [MediaAsset] = []

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension
            guard let identifier = try? mediaStore.savePhoto(data: data, preferredFileExtension: fileExtension) else { continue }

            newAssets.append(
                MediaAsset(
                    id: UUID(),
                    itemID: UUID(),
                    kind: .photo,
                    localIdentifier: identifier,
                    displayName: nil,
                    sortOrder: newAssets.count
                )
            )
        }

        selectedPhotoItems = []

        guard !newAssets.isEmpty else { return }
        draftMediaAssets = newAssets
        isPresentingAddBell = true
    }

    private func addCapturedPhotoAndPresentEditor(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.92) else { return }
        guard let identifier = try? mediaStore.savePhoto(data: data, preferredFileExtension: "jpg") else { return }

        draftMediaAssets = [
            MediaAsset(
                id: UUID(),
                itemID: UUID(),
                kind: .photo,
                localIdentifier: identifier,
                displayName: nil,
                sortOrder: 0
            )
        ]
        shouldPresentEditorAfterCamera = true
    }
}

private struct CollectionAddBellCameraPicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CollectionAddBellCameraPicker

        init(parent: CollectionAddBellCameraPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }
    }
}

private struct SettingsView: View {
    let repository: any CatalogRepository

    @State private var exportDocument: CatalogTransferDocument?
    @State private var isExportingDocument = false
    @State private var isImportingDocument = false
    @State private var importErrorMessage: String?
    @State private var exportErrorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsCard(
                        title: String(localized: "settings.appearance.title"),
                        subtitle: String(localized: "settings.appearance.subtitle"),
                        systemImage: "sparkles.rectangle.stack"
                    )

                    settingsCard(
                        title: String(localized: "settings.sharing.title"),
                        subtitle: String(localized: "settings.sharing.subtitle"),
                        systemImage: "person.2.badge.gearshape"
                    )

                    settingsCard(
                        title: String(localized: "settings.storage.title"),
                        subtitle: String(localized: "settings.storage.subtitle"),
                        systemImage: "externaldrive.connected.to.line.below"
                    )

                    NavigationLink {
                        HomeView(repository: repository, embedsNavigation: false)
                    } label: {
                        settingsNavigationCard(
                            title: String(localized: "root_tab.homes"),
                            subtitle: String(localized: "settings.storage.subtitle"),
                            systemImage: "house"
                        )
                    }
                    .buttonStyle(.plain)

                    settingsActionCard(
                        title: "Data",
                        subtitle: "Import and export the current app JSON format.",
                        systemImage: "arrow.left.arrow.right.circle"
                    ) {
                        settingsButton(title: "Export JSON", systemImage: "square.and.arrow.up") {
                            exportCurrentJSON()
                        }

                        settingsButton(title: "Import JSON", systemImage: "square.and.arrow.down") {
                            isImportingDocument = true
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentMargins(.horizontal, nil, for: .scrollContent)
            .contentMargins(.top, nil, for: .scrollContent)
            .contentMargins(.bottom, 120, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.96, blue: 0.99),
                        Color(red: 0.90, green: 0.92, blue: 0.97)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle(RootTab.settings.title)
            .fileExporter(
                isPresented: $isExportingDocument,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "catalog-export"
            ) { result in
                if case .failure(let error) = result {
                    exportErrorMessage = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $isImportingDocument,
                allowedContentTypes: [.json]
            ) { result in
                handleImport(result)
            }
            .alert("Export Failed", isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        exportErrorMessage = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? "")
            }
            .alert("Import Failed", isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        importErrorMessage = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "")
            }
        }
    }

    private func settingsCard(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.34, blue: 0.64))
                .frame(width: 44, height: 44)
                .background(CatalogSemanticColors.groupedSurfaceElevated, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CatalogSemanticColors.groupedSurface, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.section, style: .continuous))
    }

    private func settingsNavigationCard(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            settingsCard(title: title, subtitle: subtitle, systemImage: systemImage)

            Image(systemName: "chevron.right")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.trailing, 18)
        }
        .contentShape(RoundedRectangle(cornerRadius: CatalogCornerRadii.section, style: .continuous))
    }

    private func settingsActionCard<Content: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsCard(title: title, subtitle: subtitle, systemImage: systemImage)
            content()
        }
    }

    private func settingsButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                Text(title)
                Spacer()
            }
            .font(.headline)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(CatalogSemanticColors.groupedSurface, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.medium, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func exportCurrentJSON() {
        do {
            let data = try CatalogJSONPort.exportData(from: repository)
            exportDocument = CatalogTransferDocument(data: data)
            isExportingDocument = true
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: url)
                let container = try CatalogSwiftDataStack.makeContainer()
                let swiftDataRepository = SwiftDataCatalogRepository(container: container)
                try CatalogJSONPort.import(data: data, into: swiftDataRepository)
            } catch {
                importErrorMessage = error.localizedDescription
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }
}

private struct SearchTabView: View {
    private enum SearchScope: String, CaseIterable, Identifiable {
        case all
        case title
        case collection
        case origin
        case tags
        case notes
        case incomplete

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return String(localized: "search.scope.all")
            case .title:
                return String(localized: "search.scope.title")
            case .collection:
                return String(localized: "search.scope.collection")
            case .origin:
                return String(localized: "search.scope.origin")
            case .tags:
                return String(localized: "search.scope.tags")
            case .notes:
                return String(localized: "search.scope.notes")
            case .incomplete:
                return String(localized: "search.scope.incomplete")
            }
        }
    }

    let repository: any CatalogRepository
    @AppStorage("search.tab.scope") private var selectedScopeRawValue = SearchScope.all.rawValue
    @State private var query = ""
    @State private var isSearchPresented = true
    @FocusState private var isSearchFocused: Bool

    private var selectedScope: SearchScope {
        get { SearchScope(rawValue: selectedScopeRawValue) ?? .all }
        nonmutating set { selectedScopeRawValue = newValue.rawValue }
    }

    private var allBellCollections: [CollectionSummary] {
        repository.fetchCollections().filter { $0.kind == .bells }
    }

    private var searchResults: [BellRecord] {
        let allBells = allBellCollections.flatMap { collection in
            repository.fetchBellRecords(for: collection.id)
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return allBells
            .filter { bell in
                matchesSearchScope(for: bell, query: trimmedQuery)
            }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var showsEmptySearchState: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedScope != .incomplete
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !showsEmptySearchState {
                        Text(searchResultsCountText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)
                    }

                    if showsEmptySearchState {
                        ContentUnavailableView.search
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    } else if searchResults.isEmpty {
                        ContentUnavailableView(
                            String(localized: "bell_catalog.search.empty.title"),
                            systemImage: "magnifyingglass",
                            description: Text(String(localized: "bell_catalog.search.empty.description"))
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 16
                        ) {
                            ForEach(searchResults) { bell in
                                NavigationLink {
                                    SearchBellDetailContainer(
                                        repository: repository,
                                        bell: bell
                                    )
                                } label: {
                                    BellSearchResultCard(
                                        bell: bell,
                                        collectionName: collectionName(for: bell)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .padding(.top, CatalogLayoutInsets.overlay)
            .contentMargins(.horizontal, nil, for: .scrollContent)
            .contentMargins(.bottom, 120, for: .scrollContent)
            .background(
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
            )
            .searchable(
                text: $query,
                isPresented: $isSearchPresented,
                prompt: String(localized: "collections.search.prompt")
            )
            .toolbar(.hidden, for: .navigationBar)
        }
        .searchFocused($isSearchFocused)
        .defaultFocus($isSearchFocused, true)
        .onAppear {
            isSearchPresented = true
            isSearchFocused = true
        }
    }

    private var searchResultsCountText: String {
        String.localizedStringWithFormat(
            String(localized: "search.results.count"),
            searchResults.count
        )
    }

    private func matchesSearchScope(for bell: BellRecord, query: String) -> Bool {
        if selectedScope == .incomplete {
            return matchesIncomplete(bell) && (query.isEmpty || searchableText(for: bell, scope: .all).localizedCaseInsensitiveContains(query))
        }

        guard !query.isEmpty else { return false }
        return searchableText(for: bell, scope: selectedScope).localizedCaseInsensitiveContains(query)
    }

    private func searchableText(for bell: BellRecord, scope: SearchScope) -> String {
        switch scope {
        case .all:
            return [
                bell.title,
                bell.notes,
                bell.placeDisplayName,
                bell.storageDisplayPath,
                bell.condition.displayName,
                bell.acquisitionMethod.displayName,
                bell.details.material.displayName,
                collectionName(for: bell),
                bell.tags.joined(separator: " ")
            ]
            .joined(separator: "\n")
        case .title:
            return bell.title
        case .collection:
            return collectionName(for: bell)
        case .origin:
            return [bell.placeDisplayName, bell.storageDisplayPath]
                .joined(separator: "\n")
        case .tags:
            return bell.tags.joined(separator: " ")
        case .notes:
            return bell.notes
        case .incomplete:
            return searchableText(for: bell, scope: .all)
        }
    }

    private func matchesIncomplete(_ bell: BellRecord) -> Bool {
        bell.originPlace == nil ||
        bell.item.locationID == nil ||
        bell.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        bell.tags.isEmpty
    }

    private func collectionName(for bell: BellRecord) -> String {
        allBellCollections.first(where: { $0.id == bell.item.collectionID })?.name ?? ""
    }
}

private struct SearchBellDetailContainer: View {
    let repository: any CatalogRepository
    @State var bell: BellRecord

    var body: some View {
        BellDetailView(bell: $bell, repository: repository)
    }
}

private struct BellSearchResultCard: View {
    let bell: BellRecord
    let collectionName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BellCardView(bell: bell, layoutMode: .compact)
                .allowsHitTesting(false)

            if !collectionName.isEmpty {
                Text(collectionName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, CatalogSpacing.micro)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}



private struct HomeCard: View {
    let home: Home
    let locations: [Location]
    let collectionCount: Int
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var floors: [Location] {
        locations.filter { $0.kind == .floor }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: CatalogCornerRadii.medium, style: .continuous)
                        .fill(Color(red: 0.20, green: 0.42, blue: 0.34).opacity(0.12))
                        .frame(width: 54, height: 54)

                    Image(systemName: "house.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(red: 0.20, green: 0.42, blue: 0.34))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(home.name)
                        .font(.title3.bold())

                    Text(home.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                homeMetric(title: String(localized: "home.metric.collections"), value: "\(collectionCount)")
                homeMetric(title: String(localized: "home.metric.locations"), value: "\(locations.count)")
                homeMetric(title: String(localized: "home.metric.floors"), value: "\(floors.count)")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: CatalogCornerRadii.hero, style: .continuous))
        .swipeActions {
            Button(String(localized: "common.delete"), role: .destructive) {
                onDelete()
            }
        }
        .padding(CatalogLayoutInsets.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.hero, style: .continuous))
        .catalogShadow(CatalogElevation.floatingCard)
    }

    private func homeMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: CatalogSpacing.micro) {
            Text(value)
                .font(.headline.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CatalogSpacing.regular)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous))
    }
}

private struct StorageMapCard: View {
    let locations: [Location]

    private var floors: [Location] {
        locations.filter { $0.kind == .floor }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "home.storage_map"))
                .font(.headline)

            ForEach(floors) { floor in
                VStack(alignment: .leading, spacing: 8) {
                    locationRow(location: floor, depth: 0)

                    ForEach(children(of: floor), id: \.id) { room in
                        VStack(alignment: .leading, spacing: 8) {
                            locationRow(location: room, depth: 1)

                            ForEach(children(of: room), id: \.id) { container in
                                VStack(alignment: .leading, spacing: 8) {
                                    locationRow(location: container, depth: 2)

                                    ForEach(children(of: container), id: \.id) { shelf in
                                        locationRow(location: shelf, depth: 3)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(14)
                .background(CatalogSemanticColors.groupedSurface, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.medium, style: .continuous))
            }
        }
        .padding(CatalogLayoutInsets.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.hero, style: .continuous))
        .catalogShadow(CatalogElevation.floatingCard)
    }

    private func children(of location: Location) -> [Location] {
        locations.filter { $0.parentLocationID == location.id }
    }

    private func locationRow(location: Location, depth: Int) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(depthColor(depth))
                .frame(width: 8, height: 8)

            Text(location.name)
                .font(.subheadline.weight(.semibold))

                Text(location.kind.displayName)
                    .font(.caption.weight(.medium))
                    .catalogPillPadding(.compact)
                    .background(CatalogSemanticColors.groupedSurfaceElevated, in: Capsule())
                    .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.leading, CGFloat(depth) * 18)
    }

    private func depthColor(_ depth: Int) -> Color {
        switch depth {
        case 0:
            return Color(red: 0.20, green: 0.42, blue: 0.34)
        case 1:
            return Color(red: 0.36, green: 0.52, blue: 0.24)
        case 2:
            return Color(red: 0.58, green: 0.44, blue: 0.18)
        default:
            return Color(red: 0.51, green: 0.31, blue: 0.14)
        }
    }
}

private struct CollectionPlaceholderView: View {
    let title: String
    let systemImage: String
    let description: String
    let backgroundStyle: CollectionBackgroundStyle

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(description)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: backgroundStyle.screenColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CollectionOriginMapView: View {
    let collection: CollectionSummary
    let repository: any CatalogRepository

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedGroupID: String?

    private var bells: [BellRecord] {
        repository.fetchBellRecords(for: collection.id)
    }

    private var mappedGroups: [MapBellGroup] {
        let grouped = Dictionary(grouping: bells.compactMap { bell -> (String, BellRecord, CLLocationCoordinate2D)? in
            guard let place = bell.originPlace,
                  let latitude = place.latitude,
                  let longitude = place.longitude else {
                return nil
            }

            let roundedLatitude = (latitude * 100).rounded() / 100
            let roundedLongitude = (longitude * 100).rounded() / 100
            let key = "\(roundedLatitude)|\(roundedLongitude)"
            return (key, bell, CLLocationCoordinate2D(latitude: roundedLatitude, longitude: roundedLongitude))
        }, by: \.0)

        return grouped.compactMap { key, entries in
            guard let coordinate = entries.first?.2 else { return nil }
            let groupedBells = entries.map(\.1)
            return MapBellGroup(
                id: key,
                coordinate: coordinate,
                bells: groupedBells
            )
        }
        .sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private var selectedGroup: MapBellGroup? {
        mappedGroups.first(where: { $0.id == selectedGroupID })
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position, interactionModes: .all) {
                ForEach(mappedGroups) { group in
                    Annotation("", coordinate: group.coordinate, anchor: .bottom) {
                        Button {
                            selectedGroupID = group.id
                        } label: {
                            MapBellAnnotationView(
                                bells: group.bells,
                                isSelected: selectedGroupID == group.id,
                                accentColor: collection.backgroundStyle.accentColor
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea()
            .onAppear {
                updateCameraIfNeeded()
            }
            .onChange(of: mappedGroups.map(\.id)) { _, _ in
                updateCameraIfNeeded()
            }
            .overlay(alignment: .bottom) {
                if let selectedGroup {
                    MapSelectionPanel(
                        bells: selectedGroup.bells,
                        repository: repository
                    )
                        .padding(.horizontal, CatalogLayoutInsets.overlay)
                        .padding(.bottom, CatalogSpacing.section)
                }
            }
        }
        .navigationTitle(String(localized: "collection.placeholder.map.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func updateCameraIfNeeded() {
        guard !mappedGroups.isEmpty else {
            position = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
                    span: MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 80)
                )
            )
            selectedGroupID = nil
            return
        }

        if mappedGroups.count == 1, let onlyGroup = mappedGroups.first {
            position = .region(
                MKCoordinateRegion(
                    center: onlyGroup.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.8)
                )
            )
            selectedGroupID = selectedGroupID ?? onlyGroup.id
            return
        }

        let coordinates = mappedGroups.map(\.coordinate)
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max() else {
            return
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLatitude - minLatitude) * 1.6, 8),
            longitudeDelta: max((maxLongitude - minLongitude) * 1.6, 8)
        )

        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}

private struct MapBellGroup: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D

    let bells: [BellRecord]

    var title: String {
        bells.first?.title ?? ""
    }
}

private struct MapBellAnnotationView: View {
    let bells: [BellRecord]
    let isSelected: Bool
    let accentColor: Color

    private var annotationSize: CGSize {
        let side = isSelected ? 56.0 : 48.0
        return CGSize(width: side, height: side)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            annotationImage
                .frame(width: annotationSize.width, height: annotationSize.height)
                .clipShape(RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous)
                        .stroke(isSelected ? accentColor : CatalogMediaContrast.mediaSelectionStroke, lineWidth: isSelected ? 3 : 2)
                )

            if bells.count > 1 {
                Text("\(bells.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .catalogPillPadding(.micro)
                    .background(accentColor, in: Capsule())
                    .offset(x: 6, y: -6)
            }
        }
    }

    @ViewBuilder
    private var annotationImage: some View {
        if let bell = bells.first, let coverAsset = coverPhotoAsset(for: bell) {
            BellCardCoverBackground(asset: coverAsset, size: annotationSize)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous)
                    .fill(.regularMaterial)
                Image(systemName: "bell.fill")
                    .foregroundStyle(accentColor)
            }
        }
    }

    private func coverPhotoAsset(for bell: BellRecord) -> MediaAsset? {
        bell.mediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first
    }
}

private struct MapSelectionPanel: View {
    let bells: [BellRecord]
    let repository: any CatalogRepository

    @State private var presentedBell: BellRecord?

    var body: some View {
        GeometryReader { proxy in
            Group {
                if bells.count == 1 {
                    BellCardStripView(
                        bells: bells,
                        layoutMode: .wide,
                        screenWidth: proxy.size.width + 32
                    ) { bell in
                        presentedBell = bell
                    }
                } else {
                    BellCardStripView(
                        bells: bells,
                        layoutMode: .mini,
                        screenWidth: proxy.size.width + 32
                    ) { bell in
                        presentedBell = bell
                    }
                }
            }
        }
        .frame(height: bells.count == 1 ? BellGridLayoutMode.wide.cardHeight : BellGridLayoutMode.mini.cardHeight)
        .sheet(item: $presentedBell) { bell in
            BellDetailSheetContainer(bell: bell, repository: repository)
                .presentationDragIndicator(.visible)
        }
    }
}

private struct BellDetailSheetContainer: View {
    @State var bell: BellRecord
    let repository: any CatalogRepository

    var body: some View {
        NavigationStack {
            BellDetailView(bell: $bell, repository: repository)
        }
        .presentationBackground(.clear)
    }
}
