import SwiftUI

struct HomeView: View {
    let repository: any CatalogRepository
    @State private var path: [AppDestination] = []

    private var collections: [CollectionSummary] {
        repository.fetchCollections()
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero

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
        VStack(alignment: .leading, spacing: 12) {
            Text("Универсальный каталог домашних коллекций")
                .font(.largeTitle.bold())

            Text("Фиксированные типы коллекций, отдельный UI для каждого раздела и совместный доступ только по приглашению через Apple ID.")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                heroStat(title: "Коллекций", value: "\(collections.count)")
                heroStat(title: "Активных", value: "\(collections.filter { $0.status == .active }.count)")
                heroStat(title: "Шаринг", value: "invite-only")
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView(repository: InMemoryCatalogRepository())
    }
}
