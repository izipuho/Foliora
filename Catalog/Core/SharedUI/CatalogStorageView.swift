import SwiftUI

/// Displays how many items of a collection are stored in each of its locations.
struct CatalogStorageView<Item, ItemsContent: View>: View {
    let collection: CollectionSummary
    let tree: CatalogStorageTree
    let items: [Item]
    let itemLocationID: (Item) -> UUID?
    @ViewBuilder let itemsContent: ([Item], CatalogCardLayoutMode) -> ItemsContent

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if tree.isEmpty {
                CatalogEmptyStateView(
                    systemImage: "square.stack.3d.up.slash",
                    title: "storage.empty.title",
                    message: "storage.empty.message",
                    primaryTint: collection.backgroundStyle.accentColor
                )
            } else {
                List {
                    Section {
                        ForEach(tree.nodes) { node in
                            locationLink(node)
                        }
                    }

                    if tree.unassignedCount > 0 {
                        Section {
                            NavigationLink {
                                CatalogStorageItemsView(
                                    title: String(localized: "storage.unassigned"),
                                    collection: collection,
                                    items: unassignedItems,
                                    itemsContent: itemsContent
                                )
                            } label: {
                                row(title: String(localized: "storage.unassigned"), count: tree.unassignedCount)
                            }
                        }
                    }

                    if !tree.archivedNodes.isEmpty {
                        Section {
                            ForEach(tree.archivedNodes) { node in
                                locationLink(node)
                            }
                        } header: {
                            Text("storage.archived.header")
                        } footer: {
                            Text("storage.archived.footer")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background {
            CatalogBackgrounds.collection(
                collection.backgroundStyle.accentColor,
                scheme: colorScheme
            )
            .ignoresSafeArea()
        }
        .navigationTitle("storage.title")
        .navigationBarTitleDisplayMode(.large)
    }

    private var unassignedItems: [Item] {
        let knownIDs = Set((tree.nodes + tree.archivedNodes).map(\.id))
        return items.filter { item in
            guard let locationID = itemLocationID(item) else { return true }
            return !knownIDs.contains(locationID)
        }
    }

    private func items(in node: CatalogStorageTree.Node) -> [Item] {
        items.filter { item in
            itemLocationID(item).map(node.subtreeLocationIDs.contains) ?? false
        }
    }

    private func locationLink(_ node: CatalogStorageTree.Node) -> some View {
        NavigationLink {
            CatalogStorageItemsView(
                title: node.location.name,
                collection: collection,
                items: items(in: node),
                itemsContent: itemsContent
            )
        } label: {
            row(title: node.location.name, count: node.totalCount)
                .padding(.leading, CGFloat(node.depth) * CatalogMetrics.Spacing.lg)
        }
        .disabled(node.totalCount == 0)
    }

    private func row(title: String, count: Int) -> some View {
        LabeledContent {
            Text(count, format: .number)
                .monospacedDigit()
        } label: {
            Text(title)
        }
    }
}

/// Displays the items stored in one location, using the collection's card grid.
private struct CatalogStorageItemsView<Item, ItemsContent: View>: View {
    let title: String
    let collection: CollectionSummary
    let items: [Item]
    let itemsContent: ([Item], CatalogCardLayoutMode) -> ItemsContent

    @AppStorage("bellCatalog.layoutMode") private var layoutModeRawValue = CatalogCardLayoutMode.mini.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var layoutMode: CatalogCardLayoutMode {
        CatalogCardLayoutMode(rawValue: layoutModeRawValue) ?? .mini
    }

    var body: some View {
        itemsContent(items, layoutMode)
            .background {
                CatalogBackgrounds.collection(
                    collection.backgroundStyle.accentColor,
                    scheme: colorScheme
                )
                .ignoresSafeArea()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
