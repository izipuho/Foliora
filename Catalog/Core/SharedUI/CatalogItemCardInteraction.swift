import Foundation
import SwiftUI

/// Shared state for selectable item cards with Move/Delete actions.
struct CatalogCardManagementState<Item: Identifiable> where Item.ID == UUID {
    var selectedIDs: Set<UUID> = []
    var isSelectionModeEnabled = false
    var pendingMove: Item?
    var pendingDeletion: Item?
    var isPresentingDeleteConfirmation = false
    var isPresentingHomeEditor = false
    var draftHome = Home(id: UUID(), name: "", iconName: "house.fill", notes: "")
    var draftHomeLocations: [Location] = []
    private var pendingMoveAfterHomeEditor: Item?

    mutating func enterSelection(with item: Item) {
        withAnimation(.snappy(duration: 0.2)) {
            isSelectionModeEnabled = true
            selectedIDs.insert(item.id)
        }
    }

    mutating func toggleSelection(of item: Item) {
        withAnimation(.snappy(duration: 0.2)) {
            if selectedIDs.contains(item.id) {
                selectedIDs.remove(item.id)
            } else {
                selectedIDs.insert(item.id)
            }
        }
    }

    mutating func pruneSelection(to items: [Item]) {
        selectedIDs.formIntersection(Set(items.map(\.id)))
        if selectedIDs.isEmpty {
            isSelectionModeEnabled = false
        }
    }

    mutating func cancelSelection() {
        withAnimation(.snappy(duration: 0.2)) {
            isSelectionModeEnabled = false
            selectedIDs.removeAll()
        }
    }

    func selectedItems(in items: [Item]) -> [Item] {
        items.filter { selectedIDs.contains($0.id) }
    }

    func itemsForAction(triggeredBy item: Item, visibleItems: [Item]) -> [Item] {
        isSelectionModeEnabled ? selectedItems(in: visibleItems) : [item]
    }

    mutating func beginMove(_ item: Item?) {
        pendingMove = item
    }

    mutating func beginDelete(_ item: Item?) {
        guard let item else { return }
        pendingDeletion = item
        isPresentingDeleteConfirmation = true
    }

    mutating func cancelDelete() {
        pendingDeletion = nil
        isPresentingDeleteConfirmation = false
    }

    mutating func completeAction() {
        pendingMove = nil
        pendingDeletion = nil
        isPresentingDeleteConfirmation = false
        if isSelectionModeEnabled {
            cancelSelection()
        }
    }

    mutating func presentHomeEditor(
        snapshot: CatalogSnapshot?,
        homeID: UUID,
        thenMove item: Item
    ) {
        guard let snapshot,
              let home = snapshot.homes.first(where: { $0.id == homeID }) else { return }

        draftHome = home
        draftHomeLocations = snapshot.locationsByHomeID[homeID] ?? []
        pendingMoveAfterHomeEditor = item
        isPresentingHomeEditor = true
    }

    mutating func finishHomeEditor() -> Item? {
        defer {
            pendingMoveAfterHomeEditor = nil
            isPresentingHomeEditor = false
        }
        return pendingMoveAfterHomeEditor
    }
}

/// Resolves collection-aware storage locations and paths for item-card actions.
struct CatalogStorageContext {
    let availableLocations: [Location]
    let locationPathByID: [UUID: String]
    private let locationsByID: [UUID: Location]

    init(snapshot: CatalogSnapshot?, collection: CollectionSummary?) {
        guard let snapshot else {
            availableLocations = []
            locationPathByID = [:]
            locationsByID = [:]
            return
        }

        let locations: [Location]
        if let collection {
            let collectionLocations = snapshot.collectionLocationsByCollectionID[collection.id] ?? []
            locations = collectionLocations.isEmpty
                ? snapshot.locationsByHomeID[collection.homeID] ?? []
                : collectionLocations
        } else {
            locations = snapshot.locations
        }

        availableLocations = locations
        locationsByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })

        if let collection,
           let paths = snapshot.collectionLocationPathByCollectionID[collection.id],
           !(snapshot.collectionLocationsByCollectionID[collection.id] ?? []).isEmpty {
            locationPathByID = paths
        } else {
            let ids = Set(locations.map(\.id))
            locationPathByID = snapshot.locationPathByID.filter { ids.contains($0.key) }
        }
    }

    func location(for id: UUID?) -> Location? {
        id.flatMap { locationsByID[$0] }
    }

    func storagePath(for location: Location) -> StoragePath {
        var components = [StoragePath.Component(kind: location.kind, name: location.name)]
        var parentID = location.parentLocationID

        while let id = parentID, let parent = locationsByID[id] {
            components.insert(StoragePath.Component(kind: parent.kind, name: parent.name), at: 0)
            parentID = parent.parentLocationID
        }

        return StoragePath(components: components)
    }
}

/// Propagates whether an item collection is currently in multi-selection mode.
struct CatalogSelectionModePreferenceKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Compatibility alias for existing bell collection-shell consumers.
typealias BellCatalogSelectionModePreferenceKey = CatalogSelectionModePreferenceKey

/// Provides shared tap, selection-overlay and context-menu behavior for catalog item cards.
struct CatalogInteractiveCard<Content: View>: View {
    let cardSize: CGSize
    let isSelected: Bool
    let isSelectionModeEnabled: Bool
    let onTap: () -> Void
    let onSelect: (() -> Void)?
    let selectTitle: String
    let contextMenu: (() -> AnyView)?
    private let content: () -> Content

    init(
        cardSize: CGSize,
        isSelected: Bool = false,
        isSelectionModeEnabled: Bool = false,
        onTap: @escaping () -> Void,
        onSelect: (() -> Void)? = nil,
        selectTitle: String = "",
        contextMenu: (() -> AnyView)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cardSize = cardSize
        self.isSelected = isSelected
        self.isSelectionModeEnabled = isSelectionModeEnabled
        self.onTap = onTap
        self.onSelect = onSelect
        self.selectTitle = selectTitle
        self.contextMenu = contextMenu
        self.content = content
    }

    var body: some View {
        let button = Button(action: onTap) {
            content()
                .overlay {
                    if isSelectionModeEnabled && isSelected {
                        CatalogShapes.medium
                            .fill(CatalogMediaContrast.scrimMedium)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isSelectionModeEnabled && isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(CatalogMediaContrast.onMediaPrimary)
                            .frame(width: 20, height: 20)
                            .background(CatalogSemanticColors.info, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(CatalogMediaContrast.onMediaPrimary.opacity(0.9), lineWidth: 2)
                            }
                            .padding(CatalogMetrics.Spacing.sm)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(width: cardSize.width, height: cardSize.height)
        .contentShape(Rectangle())

        if let contextMenu {
            button.contextMenu {
                if let onSelect {
                    Button(action: onSelect) {
                        Label(selectTitle, systemImage: "checkmark.circle")
                    }
                }

                contextMenu()
            }
        } else {
            button
        }
    }
}

/// Shared Move/Delete actions used by catalog item-card context menus.
struct CatalogCardManagementMenu: View {
    let moveTitle: String
    let onMove: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onMove) {
            Label(moveTitle, systemImage: "folder")
        }

        Button(role: .destructive, action: onDelete) {
            Label(String(localized: "common.delete"), systemImage: "trash")
        }
    }
}

/// Shared location picker used for quick-moving catalog items from card actions.
struct CatalogQuickMoveSheet: View {
    let currentLocationID: UUID?
    let title: String
    let locations: [Location]
    let locationPathByID: [UUID: String]
    let onManageLocations: () -> Void
    let onSave: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedLocationID: UUID?

    init(
        currentLocationID: UUID?,
        title: String,
        locations: [Location],
        locationPathByID: [UUID: String],
        onManageLocations: @escaping () -> Void,
        onSave: @escaping (UUID?) -> Void
    ) {
        self.currentLocationID = currentLocationID
        self.title = title
        self.locations = locations
        self.locationPathByID = locationPathByID
        self.onManageLocations = onManageLocations
        self.onSave = onSave
        _selectedLocationID = State(initialValue: currentLocationID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "common.storage")) {
                    LocationPickerField(
                        title: String(localized: "common.location"),
                        selectedLabel: selectedLocationLabel,
                        locations: locations,
                        onManageLocations: {
                            dismiss()
                            DispatchQueue.main.async {
                                onManageLocations()
                            }
                        },
                        presentationToken: 0,
                        selectedLocationID: $selectedLocationID
                    )
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "common.cancel"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave(selectedLocationID)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(String(localized: "common.save"))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var selectedLocationLabel: String {
        guard let selectedLocationID, let path = locationPathByID[selectedLocationID] else {
            return String(localized: "common.unassigned")
        }
        return path
    }
}

/// Hosts shared Move/Delete sheets, confirmation and multi-selection toolbar.
struct CatalogCardManagementModifier<Item: Identifiable>: ViewModifier where Item.ID == UUID {
    @Binding var state: CatalogCardManagementState<Item>
    let visibleItems: [Item]
    let snapshot: CatalogSnapshot?
    let collection: CollectionSummary?
    let currentLocationID: (Item) -> UUID?
    let moveTitle: String
    let deleteTitle: String
    let deleteMessage: String
    let selectedTitle: (Int) -> String
    let canEdit: Bool
    let tint: Color
    let onSaveHome: (Home, [Location]) -> Void
    let onMove: ([Item], UUID?) -> Void
    let onDelete: ([Item]) -> Void

    func body(content: Content) -> some View {
        let storage = CatalogStorageContext(snapshot: snapshot, collection: collection)
        let selected = state.selectedItems(in: visibleItems)

        content
            .sheet(item: $state.pendingMove) { item in
                if let collection {
                    CatalogQuickMoveSheet(
                        currentLocationID: currentLocationID(item),
                        title: moveTitle,
                        locations: storage.availableLocations,
                        locationPathByID: storage.locationPathByID,
                        onManageLocations: {
                            state.presentHomeEditor(
                                snapshot: snapshot,
                                homeID: collection.homeID,
                                thenMove: item
                            )
                        },
                        onSave: { locationID in
                            onMove(state.itemsForAction(triggeredBy: item, visibleItems: visibleItems), locationID)
                            state.completeAction()
                        }
                    )
                }
            }
            .sheet(isPresented: $state.isPresentingHomeEditor) {
                HomeEditorView(
                    home: $state.draftHome,
                    locations: $state.draftHomeLocations,
                    onSave: {
                        onSaveHome(state.draftHome, state.draftHomeLocations)
                        if let item = state.finishHomeEditor() {
                            DispatchQueue.main.async { state.beginMove(item) }
                        }
                    },
                    onDelete: nil
                )
            }
            .confirmationDialog(
                deleteTitle,
                isPresented: $state.isPresentingDeleteConfirmation,
                titleVisibility: .visible,
                presenting: state.pendingDeletion
            ) { item in
                Button(String(localized: "common.delete"), role: .destructive) {
                    onDelete(state.itemsForAction(triggeredBy: item, visibleItems: visibleItems))
                    state.completeAction()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {
                    state.cancelDelete()
                }
            } message: { _ in
                Text(deleteMessage)
            }
            .toolbar(state.isSelectionModeEnabled ? .hidden : .visible, for: .tabBar)
            .preference(key: CatalogSelectionModePreferenceKey.self, value: state.isSelectionModeEnabled)
            .toolbar {
                if state.isSelectionModeEnabled {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            state.cancelSelection()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(String(localized: "common.cancel"))
                    }

                    ToolbarItem(placement: .principal) {
                        Text(selectedTitle(selected.count))
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }

                    if canEdit && !selected.isEmpty {
                        ToolbarItem(placement: .bottomBar) {
                            Button { state.beginMove(selected.first) } label: {
                                Image(systemName: "folder")
                            }
                            .tint(tint)
                        }

                        ToolbarSpacer(.flexible, placement: .bottomBar)

                        ToolbarItem(placement: .bottomBar) {
                            Button(role: .destructive) { state.beginDelete(selected.first) } label: {
                                Image(systemName: "trash")
                            }
                            .tint(CatalogSemanticColors.destructive)
                        }
                    }
                }
            }
    }
}
