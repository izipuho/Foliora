import SwiftUI
import CoreData

struct HomeDetailView: View {
    @Binding var home: Home
    @Binding var locations: [Location]
    let collectionCount: Int
    let onSave: (Home, [Location]) -> Void
    let onDelete: () -> Void
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) private var dismiss
    @State private var catalogSnapshot: CatalogSnapshot?
    @State private var isPresentingEditor = false
    @State private var isPresentingDeleteConfirmation = false

    private var homeCollections: [Collection] {
        (catalogSnapshot?.collections ?? [])
            .filter { $0.homeID == home.id }
    }

    private var collectionCountText: LocalizedStringResource {
        if collectionCount == 0 {
            return "home.list.collections.empty"
        }

        return LocalizedStringResource(
            "home.list.collections.count",
            defaultValue: "\(collectionCount, specifier: "%d")"
        )
    }

    var body: some View {
        List {
            Section {
                HomeIdentityHeader(home: home)
            } header: {
                Text(String(localized: "home.details"))
            }

            Section(String(localized: "home.storage_map")) {
                if locations.isEmpty {
                    CatalogEmptyStateView(
                        systemImage: "square.stack.3d.up.slash",
                        title: LocalizedStringKey(String(localized: "home.location.empty.title")),
                        message: LocalizedStringKey(String(localized: "home.location.empty.description")),
                        primaryActionTitle: LocalizedStringKey(String(localized: "home.location.add")),
                        primaryActionSystemImage: "plus.circle.fill",
                        primaryAction: {
                            isPresentingEditor = true
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, CatalogMetrics.Spacing.xl)
                } else {
                    StorageMapCard(locations: locations)
                }
            }

            Section {
                if homeCollections.isEmpty {
                    Text(String(localized: "home.list.collections.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(homeCollections) { collection in
                        NavigationLink(value: AppDestination.collection(collection.id)) {
                            Label(collection.title, systemImage: collection.kind.systemImage)
                        }
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                    Text(String(localized: "home.metric.collections"))
                    Text(collectionCountText)
                        .font(.caption)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(home.name)
        .navigationBarTitleDisplayMode(.large)
        .onAppear(perform: reloadCatalogSnapshot)
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: managedObjectContext
        )) { _ in
            reloadCatalogSnapshot()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingEditor = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
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
            Button(String(localized: "common.delete"), role: .destructive) {
                onDelete()
                dismiss()
            }

            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "home.delete.message"))
        }
    }

    private func reloadCatalogSnapshot() {
        catalogSnapshot = CatalogSnapshot.load(from: managedObjectContext)
    }
}

struct HomeIdentityHeader: View {
    let home: Home

    var body: some View {
        HStack(alignment: .top, spacing: CatalogMetrics.Spacing.lg) {
            Image(systemName: home.iconName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                Text(home.name)
                    .font(CatalogTypography.sectionTitle)

                if home.notes.isEmpty {
                    Text(String(localized: "home.notes.empty"))
                        .font(CatalogTypography.cardSubtitle)
                        .foregroundStyle(.secondary)
                } else {
                    Text(home.notes)
                        .font(CatalogTypography.cardSubtitle)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, CatalogMetrics.Spacing.xs)
    }
}

#Preview {
    NavigationStack {
        HomeDetailView(
            home: .constant(HomeDetailPreviewData.home),
            locations: .constant(HomeDetailPreviewData.locations),
            collectionCount: HomeDetailPreviewData.collectionCount,
            onSave: { _, _ in },
            onDelete: {}
        )
        .environment(\.managedObjectContext, HomeDetailPreviewData.context)
    }
}

private enum HomeDetailPreviewData {
    static let home = Home(
        id: UUID(),
        name: "Lake House",
        iconName: "house.fill",
        notes: "Summer storage and display shelves."
    )

    static let locations = [
        Location(
            id: UUID(),
            homeID: home.id,
            parentLocationID: nil,
            kind: .floor,
            name: "First Floor",
            notes: ""
        ),
        Location(
            id: UUID(),
            homeID: home.id,
            parentLocationID: nil,
            kind: .room,
            name: "Study",
            notes: ""
        )
    ]

    static let collectionCount = 3

    @MainActor
    static let context: NSManagedObjectContext = {
        do {
            let container = try FolioraCoreDataStack.makeContainer(inMemory: true)
            let repository = CoreDataCatalogRepository(
                context: container.viewContext,
                persistentContainer: nil
            )

            repository.saveHome(home)
            repository.saveLocations(locations, in: home.id)
            repository.saveCollection(Collection(
                id: UUID(),
                homeID: home.id,
                kind: .bells,
                title: "Travel Bells",
                notes: "",
                backgroundStyle: .amber
            ))
            repository.saveCollection(Collection(
                id: UUID(),
                homeID: home.id,
                kind: .bells,
                title: "Family Gifts",
                notes: "",
                backgroundStyle: .mint
            ))
            repository.saveCollection(Collection(
                id: UUID(),
                homeID: home.id,
                kind: .books,
                title: "Reference Books",
                notes: "",
                backgroundStyle: .slate
            ))

            return container.viewContext
        } catch {
            fatalError("Failed to create HomeDetailView preview data: \(error)")
        }
    }()
}
