import SwiftUI
import DesignSystem

struct HomeDetailView: View {
    @Binding var home: Home
    @Binding var locations: [Location]
    let collectionCount: Int
    let onSave: (Home, [Location]) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingEditor = false
    @State private var isPresentingDeleteConfirmation = false

    var body: some View {
        List {
            Section {
                HomeIdentityHeader(home: home)
            } header: {
                Text(String(localized: "home.details"))
            }

            Section(String(localized: "home.metric.collections")) {
                if collectionCount == 0 {
                    Text(String(localized: "home.list.collections.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString("home.list.collections.count", comment: "Home detail collection count"),
                            collectionCount
                        )
                    )
                }
            }

            Section(String(localized: "home.storage_map")) {
                StorageMapCard(locations: locations)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(home.name)
        .navigationBarTitleDisplayMode(.large)
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

struct HomeListCard: View {
    let home: Home
    let locations: [Location]
    let collectionCount: Int

    private var hasStorageLocations: Bool {
        !locations.isEmpty
    }

    private var subtitle: String {
        let collectionsSummary: String
        if collectionCount == 0 {
            collectionsSummary = String(localized: "home.list.collections.empty")
        } else {
            collectionsSummary = String.localizedStringWithFormat(
                NSLocalizedString("home.list.collections.count", comment: "Home list collection count"),
                collectionCount
            )
        }

        guard !hasStorageLocations else {
            return collectionsSummary
        }

        return [
            collectionsSummary,
            String(localized: "home.list.storage.empty")
        ].joined(separator: " · ")
    }

    var body: some View {
        CatalogListRowCard(
            systemImage: home.iconName,
            title: home.name,
            subtitle: subtitle
        )
    }
}

struct HomeIdentityHeader: View {
    let home: Home

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: home.iconName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(home.name)
                    .font(.headline)

                if home.notes.isEmpty {
                    Text(String(localized: "home.notes.empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(home.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}
