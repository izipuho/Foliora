import SwiftUI
import UIKit

/// Shared edit, sort/layout, and add toolbar for collection-style catalog screens.
struct CatalogContentToolbar<SortOption: Hashable>: ToolbarContent {
    @Binding private var selectedSort: SortOption
    @Binding private var selectedLayoutMode: CatalogCardLayoutMode
    @Binding private var isPresentingAddOptions: Bool

    private let sortOptions: [SortOption]
    private let sortSectionTitle: String
    private let layoutSectionTitle: String
    private let sortTitle: (SortOption) -> String
    private let layoutTitle: (CatalogCardLayoutMode) -> String
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
        layoutSectionTitle: String,
        sortTitle: @escaping (SortOption) -> String,
        layoutTitle: @escaping (CatalogCardLayoutMode) -> String,
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
        self.layoutSectionTitle = layoutSectionTitle
        self.sortTitle = sortTitle
        self.layoutTitle = layoutTitle
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

                Section(layoutSectionTitle) {
                    ControlGroup {
                        Button {
                            zoomOutLayout()
                        } label: {
                            Image(systemName: "minus")
                        }
                        .disabled(!canZoomOut)

                        Text(layoutTitle(selectedLayoutMode))

                        Button {
                            zoomInLayout()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(!canZoomIn)
                    } label: {
                        Label(layoutSectionTitle, systemImage: "square.grid.2x2")
                    }
                    .menuActionDismissBehavior(.disabled)
                }
            } label: {
                toolbarIcon(systemName: "line.3.horizontal.decrease")
            }
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

    private func toolbarIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 30, height: 30)
    }
}
