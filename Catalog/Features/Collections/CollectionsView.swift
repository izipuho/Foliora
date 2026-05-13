import SwiftUI
import SwiftData

struct CollectionsView: View {
    let repository: any CatalogRepository
    let onCollectionSelected: ((CollectionEntity) -> Void)?
    let onBellSelected: ((BellEntity) -> Void)?
    @Query(sort: \CollectionEntity.title) private var collectionEntities: [CollectionEntity]
    @Query(sort: \HomeEntity.name) private var homeEntities: [HomeEntity]
    @State private var path: [AppDestination] = []
    @State private var isPresentingAddCollectionEditor = false

    init(
        repository: any CatalogRepository,
        onCollectionSelected: ((CollectionEntity) -> Void)? = nil,
        onBellSelected: ((BellEntity) -> Void)? = nil
    ) {
        self.repository = repository
        self.onCollectionSelected = onCollectionSelected
        self.onBellSelected = onBellSelected
    }

    private var collections: [CollectionSummary] {
        collectionEntities.map(\.summarySnapshot)
    }

    private var homes: [Home] {
        homeEntities.map(\.homeSnapshot)
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
                    autoOpenSingleCollectionIfNeeded()
                }
                .onChange(of: collections.map(\.id)) { _, _ in
                    autoOpenSingleCollectionIfNeeded()
                }
                .navigationTitle(RootTab.collections.title)
                .sheet(isPresented: $isPresentingAddCollectionEditor) {
                    CollectionEditorView(
                        homes: homes,
                        initialHomeID: homes.first?.id
                    ) { title, notes, homeID, backgroundStyle in
                        addCollection(title: title, notes: notes, homeID: homeID, backgroundStyle: backgroundStyle)
                    }
                }
                .navigationDestination(for: AppDestination.self) { destination in
                    switch destination {
                    case .collection(let collection):
                        CollectionShellView(
                            collection: collection,
                            repository: repository,
                            onBellSelected: onBellSelected
                        )
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
                            selectCollection(collection)
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
        path.append(
            .collection(
                CollectionSummary(
                    id: collection.id,
                    homeID: collection.homeID,
                    kind: collection.kind,
                    name: collection.title,
                    subtitle: collection.notes,
                    backgroundStyle: collection.backgroundStyle,
                    itemCount: 0,
                    collaboratorCount: 0,
                    role: .owner,
                    status: .active,
                    sharingSummary: ""
                )
            )
        )
    }

    private func selectCollection(_ collection: CollectionSummary) {
        if let onCollectionSelected {
            if let collectionEntity = collectionEntities.first(where: { $0.id == collection.id }) {
                onCollectionSelected(collectionEntity)
            }
            return
        }

        path.append(.collection(collection))
    }

    private func autoOpenSingleCollectionIfNeeded() {
        guard onCollectionSelected == nil else { return }
        guard path.isEmpty else { return }
        guard collections.count == 1 else { return }
        guard let collection = collections.first else { return }

        path.append(.collection(collection))
    }
}
