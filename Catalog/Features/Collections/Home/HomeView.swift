import SwiftUI

private func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

enum RootTab: String, CaseIterable, Identifiable {
    case collections
    case homes
    case search
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collections:
            return L("root_tab.collections")
        case .homes:
            return L("root_tab.homes")
        case .search:
            return L("root_tab.search")
        case .settings:
            return L("root_tab.settings")
        }
    }

    var systemImage: String {
        switch self {
        case .collections:
            return "square.grid.2x2"
        case .homes:
            return "house"
        case .search:
            return "magnifyingglass"
        case .settings:
            return "gearshape"
        }
    }
}

enum CollectionTab: String, CaseIterable, Identifiable {
    case summary
    case items
    case map
    case participants
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary:
            return L("collection_tab.summary")
        case .items:
            return L("collection_tab.items")
        case .map:
            return L("collection_tab.map")
        case .participants:
            return L("collection_tab.participants")
        case .search:
            return L("collection_tab.search")
        }
    }

    var systemImage: String {
        switch self {
        case .summary:
            return "rectangle.grid.2x2"
        case .items:
            return "bell.fill"
        case .map:
            return "map"
        case .participants:
            return "person.2.fill"
        case .search:
            return "magnifyingglass"
        }
    }
}

struct AppShellView: View {
    let repository: any CatalogRepository

    var body: some View {
        ModernAppShellView(repository: repository)
    }
}

private struct ModernAppShellView: View {
    let repository: any CatalogRepository

    var body: some View {
        TabView {
            Tab(RootTab.collections.title, systemImage: RootTab.collections.systemImage) {
                CollectionsView(repository: repository)
            }

            Tab(RootTab.homes.title, systemImage: RootTab.homes.systemImage) {
                HomeView(repository: repository)
            }

            Tab(role: .search) {
                SearchTabView()
            }

            Tab(RootTab.settings.title, systemImage: RootTab.settings.systemImage) {
                SettingsView()
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
    @State private var path: [AppDestination] = []
    @State private var homes: [Home]
    @State private var locationsByHomeID: [UUID: [Location]]

    init(repository: any CatalogRepository) {
        self.repository = repository
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
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    homesSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 120)
            }
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
            .navigationTitle(L("home.screen.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let newHome = Home(id: UUID(), name: L("home.new.default_name"), notes: "")
                        homes.append(newHome)
                        locationsByHomeID[newHome.id] = []
                        repository.saveHome(newHome)
                        repository.saveLocations([], in: newHome.id)
                        path.append(.home(newHome.id))
                    } label: {
                        Image(systemName: "plus")
                    }
                }
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
                            L("home.not_found.title"),
                            systemImage: "house.slash",
                            description: Text(L("home.not_found.description"))
                        )
                    }
                }
            }
        }
    }

    private var homesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if homes.isEmpty {
                ContentUnavailableView(
                    L("home.empty.title"),
                    systemImage: "house.slash",
                    description: Text(L("home.empty.description"))
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 80)

                Button {
                    let newHome = Home(id: UUID(), name: L("home.new.default_name"), notes: "")
                    homes.append(newHome)
                    locationsByHomeID[newHome.id] = []
                    repository.saveHome(newHome)
                    repository.saveLocations([], in: newHome.id)
                    path.append(.home(newHome.id))
                } label: {
                    Label(L("home.add"), systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.20, green: 0.42, blue: 0.34))
            } else {
                ForEach(homes) { home in
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
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView(repository: InMemoryCatalogRepository())
    }
}

private struct HomeDetailView: View {
    @Binding var home: Home
    @Binding var locations: [Location]
    let collectionCount: Int
    let onSave: (Home, [Location]) -> Void
    let onDelete: () -> Void
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

                Text(L("home.details"))
                    .font(.headline)
                    .padding(.horizontal, 4)

                StorageMapCard(locations: locations)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 120)
        }
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
                }
            )
        }
        .confirmationDialog(
            L("home.delete.title"),
            isPresented: $isPresentingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(L("home.delete.confirm"), role: .destructive) {
                onDelete()
            }

            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(L("home.delete.message"))
        }
    }
}

private struct HomeEditorView: View {
    @Binding var home: Home
    @Binding var locations: [Location]
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(L("home.editor.section_home")) {
                    TextField(
                        L("common.name"),
                        text: $home.name
                    )

                    TextField(
                        L("common.notes"),
                        text: $home.notes,
                        axis: .vertical
                    )
                    .lineLimit(3, reservesSpace: true)
                }

                Section(L("home.editor.section_locations")) {
                    if locations.isEmpty {
                        ContentUnavailableView(
                            L("home.location.empty.title"),
                            systemImage: "square.stack.3d.up.slash",
                            description: Text(L("home.location.empty.description"))
                        )
                    } else {
                        ForEach($locations) { $location in
                            VStack(alignment: .leading, spacing: 10) {
                                TextField(L("home.location.name"), text: $location.name)

                                Picker(L("home.location.kind"), selection: $location.kind) {
                                    ForEach(LocationKind.allCases) { kind in
                                        Text(kind.displayName).tag(kind)
                                    }
                                }

                                Picker(
                                    L("home.location.parent"),
                                    selection: Binding(
                                        get: { location.parentLocationID },
                                        set: { newValue in
                                            location.parentLocationID = newValue
                                        }
                                    )
                                ) {
                                    Text(L("common.none")).tag(Optional<UUID>.none)
                                    ForEach(parentCandidates(for: location)) { candidate in
                                        Text(candidate.name).tag(Optional(candidate.id))
                                    }
                                }

                                TextField(L("common.notes"), text: $location.notes, axis: .vertical)
                                    .lineLimit(2, reservesSpace: true)
                            }
                            .padding(.vertical, 6)
                        }
                        .onDelete(perform: deleteLocations)
                    }

                    Button {
                        addLocation()
                    } label: {
                        Label(L("home.location.add"), systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle(L("home.editor.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common.done")) {
                        onSave()
                        dismiss()
                    }
                }
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
                name: L("home.location.new_default_name"),
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
        locations.filter { candidate in
            candidate.id != location.id && candidate.homeID == location.homeID
        }
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
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.20, green: 0.42, blue: 0.34).opacity(0.12))
                        .frame(width: 54, height: 54)

                    Image(systemName: "house.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(red: 0.20, green: 0.42, blue: 0.34))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(home.name)
                        .font(.title3.bold())

                    Text(home.notes.isEmpty ? L("common.no_notes") : home.notes)
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
                listMetric(title: L("home.metric.collections"), value: "\(collectionCount)")
                listMetric(title: L("home.metric.locations"), value: "\(locations.count)")
                listMetric(title: L("home.metric.floors"), value: "\(floors)")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 14, y: 8)
    }

    private func listMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct CollectionsView: View {
    let repository: any CatalogRepository
    @State private var path: [AppDestination] = []
    @State private var collections: [CollectionSummary]
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
                .navigationDestination(for: AppDestination.self) { destination in
                    switch destination {
                    case .collection(let collection):
                        CollectionShellView(collection: collection, repository: repository)
                    case .home:
                        EmptyView()
                    }
                }
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
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 120)
            }
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
                L("collections.empty.title"),
                systemImage: "square.grid.2x2",
                description: Text(L("collections.empty.description"))
            )
            .frame(maxWidth: .infinity)

            Button {
                isPresentingAddCollectionEditor = true
            } label: {
                Label(L("collections.add"), systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.53, green: 0.31, blue: 0.14))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 20)
        .padding(.bottom, 80)
    }

    private func addCollection(title: String, notes: String, homeID: UUID, backgroundStyle: CollectionBackgroundStyle) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let collection = Collection(
            id: UUID(),
            homeID: homeID,
            kind: .bells,
            title: trimmedTitle.isEmpty ? L("collection.editor.default_title") : trimmedTitle,
            notes: trimmedNotes,
            backgroundStyle: backgroundStyle
        )

        repository.saveCollection(collection)
        collections = repository.fetchCollections()
        if let createdCollection = collections.first(where: { $0.id == collection.id }) {
            path = [.collection(createdCollection)]
            didAutoOpenSingleCollection = true
        }
    }

    private func autoOpenSingleCollectionIfNeeded() {
        guard collections.count == 1 else { return }
        guard path.isEmpty else { return }
        guard !didAutoOpenSingleCollection else { return }
        guard let collection = collections.first else { return }

        didAutoOpenSingleCollection = true
        path = [.collection(collection)]
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
                Section(L("collection.editor.section_type")) {
                    HStack {
                        Label(L("collection.editor.type_name_localized"), systemImage: "bell.fill")
                        Spacer()
                        Text(L("collection.editor.type_name_english"))
                            .foregroundStyle(.secondary)
                    }
                }

                Section(L("collection.editor.section_collection")) {
                    TextField(L("common.name"), text: $title)
                    TextField(L("common.notes"), text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                Section(L("collection.editor.section_home")) {
                    if homes.isEmpty {
                        Text(L("collection.editor.no_home"))
                            .foregroundStyle(.secondary)
                    } else if allowsHomeSelection {
                        Picker(L("home.screen.title"), selection: $selectedHomeID) {
                            ForEach(homes) { home in
                                Text(home.name).tag(Optional(home.id))
                            }
                        }
                    } else {
                        HStack {
                            Text(L("home.screen.title"))
                            Spacer()
                            Text(homes.first(where: { $0.id == selectedHomeID })?.name ?? L("common.unknown"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(L("collection.editor.section_background")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 74, maximum: 110), spacing: 12)], spacing: 12) {
                        ForEach(CollectionBackgroundStyle.allCases) { style in
                            Button {
                                backgroundStyle = style
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                                                    .foregroundStyle(.white, Color.black.opacity(0.25))
                                                    .padding(6)
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
                        Button(L("collection.delete.confirm"), role: .destructive) {
                            isPresentingDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common.save")) {
                        guard let selectedHomeID else { return }
                        onSave(title, notes, selectedHomeID, backgroundStyle)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .confirmationDialog(
                L("collection.delete.title"),
                isPresented: $isPresentingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(L("collection.delete.confirm"), role: .destructive) {
                    onDelete?()
                    dismiss()
                }

                Button(L("common.cancel"), role: .cancel) {}
            } message: {
                Text(L("collection.delete.message"))
            }
        }
    }
}

private struct CollectionShellView: View {
    let repository: any CatalogRepository
    @Environment(\.dismiss) private var dismiss
    @State private var collection: CollectionSummary
    @State private var selectedTab: CollectionTab = .summary
    @State private var refreshID = UUID()
    @State private var isPresentingAddBell = false
    @State private var isPresentingEditCollection = false

    init(collection: CollectionSummary, repository: any CatalogRepository) {
        self.repository = repository
        _collection = State(initialValue: collection)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(CollectionTab.summary.title, systemImage: CollectionTab.summary.systemImage, value: .summary) {
                BellCatalogView(
                    collection: collection,
                    repository: repository,
                    collaborators: repository.fetchCollaborators(for: collection.id),
                    mode: .summary
                )
                .id("summary-\(refreshID.uuidString)")
            }

            Tab(CollectionTab.items.title, systemImage: CollectionTab.items.systemImage, value: .items) {
                BellCatalogView(
                    collection: collection,
                    repository: repository,
                    collaborators: repository.fetchCollaborators(for: collection.id),
                    mode: .items
                )
                .id("items-\(refreshID.uuidString)")
            }

            Tab(CollectionTab.map.title, systemImage: CollectionTab.map.systemImage, value: .map) {
                CollectionPlaceholderView(
                    title: L("collection.placeholder.map.title"),
                    systemImage: "map",
                    description: L("collection.placeholder.map.description"),
                    backgroundStyle: collection.backgroundStyle
                )
            }

            Tab(CollectionTab.participants.title, systemImage: CollectionTab.participants.systemImage, value: .participants) {
                CollectionPlaceholderView(
                    title: L("collection.placeholder.participants.title"),
                    systemImage: "person.2.fill",
                    description: L("collection.placeholder.participants.description"),
                    backgroundStyle: collection.backgroundStyle
                )
            }

            Tab(CollectionTab.search.title, systemImage: CollectionTab.search.systemImage, value: .search) {
                BellCatalogView(
                    collection: collection,
                    repository: repository,
                    collaborators: repository.fetchCollaborators(for: collection.id),
                    mode: .search
                )
                .id("search-\(refreshID.uuidString)")
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingEditCollection = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingAddBell = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAddBell) {
            BellEditorView(
                collection: collection,
                repository: repository
            ) { newBell in
                repository.saveBellRecord(newBell)
                refreshContent()
                selectedTab = .items
            }
        }
        .sheet(isPresented: $isPresentingEditCollection) {
            CollectionEditorView(
                homes: repository.fetchHomes(),
                screenTitle: "Edit Collection",
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
}

private struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsCard(
                        title: L("settings.appearance.title"),
                        subtitle: L("settings.appearance.subtitle"),
                        systemImage: "sparkles.rectangle.stack"
                    )

                    settingsCard(
                        title: L("settings.sharing.title"),
                        subtitle: L("settings.sharing.subtitle"),
                        systemImage: "person.2.badge.gearshape"
                    )

                    settingsCard(
                        title: L("settings.storage.title"),
                        subtitle: L("settings.storage.subtitle"),
                        systemImage: "externaldrive.connected.to.line.below"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 120)
            }
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                    } label: {
                        Image(systemName: "gearshape.2")
                    }
                }
            }
        }
    }

    private func settingsCard(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.34, blue: 0.64))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct SearchTabView: View {
    @State private var query = ""
    @State private var isSearchPresented = true
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            Color.clear
                .ignoresSafeArea()
                .toolbar(.hidden, for: .navigationBar)
        }
        .searchable(
            text: $query,
            isPresented: $isSearchPresented,
            prompt: L("collections.search.prompt")
        )
        .searchFocused($isSearchFocused)
        .defaultFocus($isSearchFocused, true)
        .onAppear {
            isSearchPresented = true
            isSearchFocused = true
        }
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
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                homeMetric(title: L("home.metric.collections"), value: "\(collectionCount)")
                homeMetric(title: L("home.metric.locations"), value: "\(locations.count)")
                homeMetric(title: L("home.metric.floors"), value: "\(floors.count)")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .swipeActions {
            Button(L("common.delete"), role: .destructive) {
                onDelete()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 14, y: 8)
    }

    private func homeMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct StorageMapCard: View {
    let locations: [Location]

    private var floors: [Location] {
        locations.filter { $0.kind == .floor }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("home.storage_map"))
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
                .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 14, y: 8)
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
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(Color.black.opacity(0.05), in: Capsule())
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
