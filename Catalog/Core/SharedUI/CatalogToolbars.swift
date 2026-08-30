import SwiftUI
import UIKit

/// Shared edit, sort/layout, and add toolbar for collection-style catalog screens.
struct CatalogCollectionToolbar<SortOption: Hashable>: ToolbarContent {
    @Binding private var selectedSort: SortOption
    @Binding private var selectedLayoutMode: CatalogCardLayoutMode
    @Binding private var isPresentingAddOptions: Bool

    private let sortOptions: [SortOption]
    private let sortSectionTitle: String
    private let sortTitle: (SortOption) -> String
    private let hasActiveFilters: Bool
    private let onFilters: (() -> Void)?
    private let canEdit: Bool
    private let onEdit: () -> Void
    private let onPhotoLibrary: () -> Void
    private let onCamera: () -> Void

    init(
        selectedSort: Binding<SortOption>,
        selectedLayoutMode: Binding<CatalogCardLayoutMode>,
        isPresentingAddOptions: Binding<Bool>,
        sortOptions: [SortOption],
        sortSectionTitle: String,
        sortTitle: @escaping (SortOption) -> String,
        hasActiveFilters: Bool = false,
        onFilters: (() -> Void)? = nil,
        canEdit: Bool,
        onEdit: @escaping () -> Void,
        onPhotoLibrary: @escaping () -> Void,
        onCamera: @escaping () -> Void
    ) {
        self._selectedSort = selectedSort
        self._selectedLayoutMode = selectedLayoutMode
        self._isPresentingAddOptions = isPresentingAddOptions
        self.sortOptions = sortOptions
        self.sortSectionTitle = sortSectionTitle
        self.sortTitle = sortTitle
        self.hasActiveFilters = hasActiveFilters
        self.onFilters = onFilters
        self.canEdit = canEdit
        self.onEdit = onEdit
        self.onPhotoLibrary = onPhotoLibrary
        self.onCamera = onCamera
    }

    var body: some ToolbarContent {
        if canEdit {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onEdit) {
                    toolbarIcon(systemName: "square.and.pencil")
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            CatalogSortLayoutMenu(
                selectedSort: $selectedSort,
                selectedLayoutMode: $selectedLayoutMode,
                sortOptions: sortOptions,
                sortSectionTitle: sortSectionTitle,
                sortTitle: sortTitle,
                hasActiveFilters: hasActiveFilters,
                onFilters: onFilters
            )
        }

        if canEdit {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingAddOptions = true
                } label: {
                    toolbarIcon(systemName: "plus")
                }
                .confirmationDialog(
                    String(localized: "common.add"),
                    isPresented: $isPresentingAddOptions,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "editor.media.photo_library"), action: onPhotoLibrary)

                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button(String(localized: "editor.media.camera"), action: onCamera)
                    }

                    Button(String(localized: "common.cancel"), role: .cancel) {}
                }
            }
        }
    }

    private func toolbarIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 30, height: 30)
    }
}

/// Shared sort and card-scale toolbar for catalog grid detail screens.
struct CatalogSortLayoutToolbar<SortOption: Hashable>: ToolbarContent {
    @Binding private var selectedSort: SortOption
    @Binding private var selectedLayoutMode: CatalogCardLayoutMode

    private let sortOptions: [SortOption]
    private let sortSectionTitle: String
    private let sortTitle: (SortOption) -> String
    private let hasActiveFilters: Bool
    private let onFilters: (() -> Void)?

    init(
        selectedSort: Binding<SortOption>,
        selectedLayoutMode: Binding<CatalogCardLayoutMode>,
        sortOptions: [SortOption],
        sortSectionTitle: String,
        sortTitle: @escaping (SortOption) -> String,
        hasActiveFilters: Bool = false,
        onFilters: (() -> Void)? = nil
    ) {
        self._selectedSort = selectedSort
        self._selectedLayoutMode = selectedLayoutMode
        self.sortOptions = sortOptions
        self.sortSectionTitle = sortSectionTitle
        self.sortTitle = sortTitle
        self.hasActiveFilters = hasActiveFilters
        self.onFilters = onFilters
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            CatalogSortLayoutMenu(
                selectedSort: $selectedSort,
                selectedLayoutMode: $selectedLayoutMode,
                sortOptions: sortOptions,
                sortSectionTitle: sortSectionTitle,
                sortTitle: sortTitle,
                hasActiveFilters: hasActiveFilters,
                onFilters: onFilters
            )
        }
    }
}

private struct CatalogSortLayoutMenu<SortOption: Hashable>: View {
    @Binding var selectedSort: SortOption
    @Binding var selectedLayoutMode: CatalogCardLayoutMode
    let sortOptions: [SortOption]
    let sortSectionTitle: String
    let sortTitle: (SortOption) -> String
    let hasActiveFilters: Bool
    let onFilters: (() -> Void)?

    var body: some View {
        Menu {
            Section(sortSectionTitle) {
                ForEach(sortOptions, id: \.self) { option in
                    Button {
                        selectedSort = option
                    } label: {
                        if selectedSort == option {
                            Label(sortTitle(option), systemImage: "checkmark")
                        } else {
                            Text(sortTitle(option))
                        }
                    }
                }
            }

            if let onFilters {
                Section {
                    Button(action: onFilters) {
                        Label(
                            "Filters",
                            systemImage: hasActiveFilters
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle"
                        )
                    }
                }
            }

            Section(String(localized: "card_layout.menu")) {
                ControlGroup {
                    Button {
                        zoomOutLayout()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(!canZoomOut)

                    Text(layoutTitle(for: selectedLayoutMode))

                    Button {
                        zoomInLayout()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!canZoomIn)
                } label: {
                    Label(String(localized: "card_layout.menu"), systemImage: "square.grid.2x2")
                }
                .menuActionDismissBehavior(.disabled)
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 30, height: 30)
        }
    }

    private var orderedLayoutModes: [CatalogCardLayoutMode] {
        [.covers, .mini, .compact, .wide, .showcase]
    }

    private var canZoomOut: Bool {
        guard let currentIndex = orderedLayoutModes.firstIndex(of: selectedLayoutMode) else {
            return false
        }
        return currentIndex > 0
    }

    private var canZoomIn: Bool {
        guard let currentIndex = orderedLayoutModes.firstIndex(of: selectedLayoutMode) else {
            return false
        }
        return currentIndex < orderedLayoutModes.count - 1
    }

    private func zoomOutLayout() {
        guard let currentIndex = orderedLayoutModes.firstIndex(of: selectedLayoutMode), currentIndex > 0 else {
            return
        }
        selectedLayoutMode = orderedLayoutModes[currentIndex - 1]
    }

    private func zoomInLayout() {
        guard let currentIndex = orderedLayoutModes.firstIndex(of: selectedLayoutMode),
              currentIndex < orderedLayoutModes.count - 1 else {
            return
        }
        selectedLayoutMode = orderedLayoutModes[currentIndex + 1]
    }

    private func layoutTitle(for mode: CatalogCardLayoutMode) -> String {
        switch mode {
        case .covers:
            return String(localized: "card_layout.covers")
        case .mini:
            return String(localized: "card_layout.mini")
        case .compact:
            return String(localized: "card_layout.compact")
        case .wide:
            return String(localized: "card_layout.wide")
        case .showcase:
            return String(localized: "card_layout.showcase")
        }
    }
}

/// Shared navigation toolbar for catalog item detail screens.
struct CatalogItemDetailToolbar: ToolbarContent {
    enum ContentState {
        case readOnly
        case viewing(onEdit: () -> Void)
        case pendingChanges(onCancel: () -> Void, onSave: () -> Void)
    }

    struct FavoriteAction {
        let isFavorite: Bool
        let action: () -> Void
    }

    let onClose: (() -> Void)?
    let favorite: FavoriteAction?
    let contentState: ContentState

    var body: some ToolbarContent {
        if onClose != nil || isPendingChanges {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: handleCloseOrCancel) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(String(localized: "common.cancel"))
            }
        }

        if let favorite {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: favorite.action) {
                    Image(systemName: favorite.isFavorite ? "star.fill" : "star")
                }
                .accessibilityLabel(
                    favorite.isFavorite
                        ? String(localized: "favorite.remove")
                        : String(localized: "favorite.add")
                )
            }
        }

        if case .viewing(let onEdit) = contentState {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onEdit) {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel(String(localized: "common.edit"))
            }
        }

        if case .pendingChanges(_, let onSave) = contentState {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onSave) {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel(String(localized: "common.save"))
            }
        }
    }

    private var isPendingChanges: Bool {
        if case .pendingChanges = contentState {
            return true
        }
        return false
    }

    private func handleCloseOrCancel() {
        if case .pendingChanges(let onCancel, _) = contentState {
            onCancel()
        } else {
            onClose?()
        }
    }
}
