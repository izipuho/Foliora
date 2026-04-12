import SwiftUI

struct HomeView: View {
    let repository: any CatalogRepository
    @State private var path: [AppDestination] = []

    private var home: Home? {
        repository.fetchHomes().first
    }

    private var locations: [Location] {
        guard let home else { return [] }
        return repository.fetchLocations(in: home.id)
    }

    private var collections: [CollectionSummary] {
        repository.fetchCollections()
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    homeSection

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Коллекции")
                            .font(.title2.bold())

                        ForEach(collections) { collection in
                            Button {
                                path.append(.collection(collection))
                            } label: {
                                CollectionCard(collection: collection)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
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
            .navigationTitle("Мои коллекции")
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

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Универсальный каталог домашних коллекций")
                        .font(.largeTitle.bold())

                    Text("Фиксированные типы коллекций, отдельный UI для каждого раздела и совместный доступ только по приглашению через Apple ID.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Image(systemName: "house.lodge.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color(red: 0.55, green: 0.32, blue: 0.15))
                    .padding(14)
                    .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack(spacing: 12) {
                heroStat(title: "Collections", value: "\(collections.count)")
                heroStat(title: "Active", value: "\(collections.filter { $0.status == .active }.count)")
                heroStat(title: "Sharing", value: "invite-only")
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.98, blue: 0.94),
                    Color(red: 0.95, green: 0.92, blue: 0.84)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
        )
    }

    private func heroStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var homeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Дом")
                .font(.title2.bold())

            if let home {
                HomeCard(
                    home: home,
                    locations: locations,
                    collectionCount: collections.count
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
