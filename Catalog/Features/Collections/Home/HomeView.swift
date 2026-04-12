import SwiftUI

enum RootTab: String, CaseIterable, Identifiable {
    case collections
    case homes
    case search
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collections:
            return "Коллекции"
        case .homes:
            return "Дома"
        case .search:
            return "Поиск"
        case .settings:
            return "Настройки"
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
            Tab("Коллекции", systemImage: RootTab.collections.systemImage) {
                CollectionsView(repository: repository)
            }

            Tab("Дома", systemImage: RootTab.homes.systemImage) {
                HomeView(repository: repository)
            }

            Tab(role: .search) {
                SearchTabView()
            }

            Tab("Настройки", systemImage: RootTab.settings.systemImage) {
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
            .navigationTitle("Дома")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let newHome = Home(id: UUID(), name: "New Home", notes: "")
                        homes.append(newHome)
                        locationsByHomeID[newHome.id] = []
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
                            onDelete: {
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
                            "Home Not Found",
                            systemImage: "house.slash",
                            description: Text("This home is no longer available.")
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
                    "No Homes",
                    systemImage: "house.slash",
                    description: Text("Create a home to organize rooms, shelves, and collections.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 80)

                Button {
                    let newHome = Home(id: UUID(), name: "New Home", notes: "")
                    homes.append(newHome)
                    locationsByHomeID[newHome.id] = []
                    path.append(.home(newHome.id))
                } label: {
                    Label("Add Home", systemImage: "plus.circle.fill")
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

                Text("Details")
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
                locations: $locations
            )
        }
        .confirmationDialog(
            "Delete Home?",
            isPresented: $isPresentingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Home", role: .destructive) {
                onDelete()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the home and its location structure from the current session.")
        }
    }
}

private struct HomeEditorView: View {
    @Binding var home: Home
    @Binding var locations: [Location]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Home") {
                    TextField(
                        "Name",
                        text: $home.name
                    )

                    TextField(
                        "Notes",
                        text: $home.notes,
                        axis: .vertical
                    )
                    .lineLimit(3, reservesSpace: true)
                }

                Section("Locations") {
                    if locations.isEmpty {
                        ContentUnavailableView(
                            "No Locations Yet",
                            systemImage: "square.stack.3d.up.slash",
                            description: Text("Add floors, rooms, cabinets, and shelves for this home.")
                        )
                    } else {
                        ForEach($locations) { $location in
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("Location name", text: $location.name)

                                Picker("Kind", selection: $location.kind) {
                                    ForEach(LocationKind.allCases) { kind in
                                        Text(kind.displayName).tag(kind)
                                    }
                                }

                                Picker(
                                    "Parent",
                                    selection: Binding(
                                        get: { location.parentLocationID },
                                        set: { newValue in
                                            location.parentLocationID = newValue
                                        }
                                    )
                                ) {
                                    Text("None").tag(Optional<UUID>.none)
                                    ForEach(parentCandidates(for: location)) { candidate in
                                        Text(candidate.name).tag(Optional(candidate.id))
                                    }
                                }

                                TextField("Notes", text: $location.notes, axis: .vertical)
                                    .lineLimit(2, reservesSpace: true)
                            }
                            .padding(.vertical, 6)
                        }
                        .onDelete(perform: deleteLocations)
                    }

                    Button {
                        addLocation()
                    } label: {
                        Label("Add Location", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Edit Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
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
                name: "New Location",
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

                    Text(home.notes.isEmpty ? "No notes yet." : home.notes)
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
                listMetric(title: "Collections", value: "\(collectionCount)")
                listMetric(title: "Locations", value: "\(locations.count)")
                listMetric(title: "Floors", value: "\(floors)")
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

    private var collections: [CollectionSummary] {
        repository.fetchCollections()
    }

    var body: some View {
        NavigationStack(path: $path) {
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
            .navigationTitle("Коллекции")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case .collection(let collection):
                    switch collection.kind {
                    case .bells:
                        BellCatalogView(
                            collection: collection,
                            repository: repository,
                            collaborators: repository.fetchCollaborators(for: collection.id)
                        )
                    case .books:
                        BookLibraryPlaceholderView(collection: collection)
                    }
                case .home:
                    EmptyView()
                }
            }
        }
    }
}

private struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    settingsCard(
                        title: "Appearance",
                        subtitle: "Liquid Glass tab bar and collection-first layout are enabled in the current build.",
                        systemImage: "sparkles.rectangle.stack"
                    )

                    settingsCard(
                        title: "Sharing",
                        subtitle: "Collections stay invitation-only and use role-based access.",
                        systemImage: "person.2.badge.gearshape"
                    )

                    settingsCard(
                        title: "Storage",
                        subtitle: "Homes, locations, items, and media are already represented in the domain model.",
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
            .navigationTitle("Настройки")
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
            prompt: "Search collections"
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
                homeMetric(title: "Collections", value: "\(collectionCount)")
                homeMetric(title: "Locations", value: "\(locations.count)")
                homeMetric(title: "Floors", value: "\(floors.count)")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .swipeActions {
            Button("Delete", role: .destructive) {
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
            Text("Storage Map")
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
