import SwiftUI

enum RootTab: String, CaseIterable, Identifiable {
    case homes
    case collections
    case search
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .homes:
            return "Дома"
        case .collections:
            return "Коллекции"
        case .search:
            return "Поиск"
        case .settings:
            return "Настройки"
        }
    }

    var systemImage: String {
        switch self {
        case .homes:
            return "house"
        case .collections:
            return "square.grid.2x2"
        case .search:
            return "magnifyingglass"
        case .settings:
            return "slider.horizontal.3"
        }
    }
}

struct AppShellView: View {
    let repository: any CatalogRepository
    @State private var selectedTab: RootTab = .homes

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .homes:
                    HomeView(repository: repository)
                case .collections:
                    CollectionsView(repository: repository)
                case .search:
                    SearchView(repository: repository)
                case .settings:
                    SettingsView()
                }
            }

            GlassTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
        }
    }
}

struct HomeView: View {
    let repository: any CatalogRepository

    private var home: Home? {
        repository.fetchHomes().first
    }

    private var locations: [Location] {
        guard let home else { return [] }
        return repository.fetchLocations(in: home.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    homeSection
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
            .navigationTitle("Дом")
        }
    }

    private var homeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let home {
                HomeCard(
                    home: home,
                    locations: locations,
                    collectionCount: repository.fetchCollections().count
                )
            }
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView(repository: InMemoryCatalogRepository())
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
                }
            }
        }
    }
}

private struct SearchView: View {
    let repository: any CatalogRepository
    @State private var query = ""

    private var collections: [CollectionSummary] {
        repository.fetchCollections().filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Search collections", text: $query)
                        .textInputAutocapitalization(.never)
                        .padding(14)
                        .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if collections.isEmpty {
                        ContentUnavailableView(
                            "Ничего не найдено",
                            systemImage: "magnifyingglass",
                            description: Text("Попробуй другой запрос.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        ForEach(collections) { collection in
                            CollectionCard(collection: collection)
                        }
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
                        Color(red: 0.96, green: 0.97, blue: 0.94),
                        Color(red: 0.92, green: 0.93, blue: 0.90)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Поиск")
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

private struct GlassTabBar: View {
    @Binding var selectedTab: RootTab

    var body: some View {
        HStack(spacing: 10) {
            ForEach(RootTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.black.opacity(0.82) : Color.black.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Group {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.42))
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
    }
}

private struct HomeCard: View {
    let home: Home
    let locations: [Location]
    let collectionCount: Int

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

                Spacer()
            }

            HStack(spacing: 12) {
                homeMetric(title: "Collections", value: "\(collectionCount)")
                homeMetric(title: "Locations", value: "\(locations.count)")
                homeMetric(title: "Floors", value: "\(floors.count)")
            }

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
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.94), Color.white.opacity(0.80)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 14, y: 8)
    }

    private func children(of location: Location) -> [Location] {
        locations.filter { $0.parentLocationID == location.id }
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
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
