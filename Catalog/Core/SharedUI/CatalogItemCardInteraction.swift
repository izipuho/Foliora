import Foundation
import SwiftUI

/// Shared selection state for item-card collections.
struct CatalogCardSelectionState: Equatable {
    var isEnabled = false
    var selectedIDs: Set<UUID> = []

    mutating func enter(with id: UUID) {
        isEnabled = true
        selectedIDs.insert(id)
    }

    mutating func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    mutating func prune(to visibleIDs: Set<UUID>) {
        selectedIDs.formIntersection(visibleIDs)
        if selectedIDs.isEmpty {
            isEnabled = false
        }
    }

    mutating func cancel() {
        isEnabled = false
        selectedIDs.removeAll()
    }

    func selectedVisibleIDs(in visibleIDs: Set<UUID>) -> Set<UUID> {
        selectedIDs.intersection(visibleIDs)
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
