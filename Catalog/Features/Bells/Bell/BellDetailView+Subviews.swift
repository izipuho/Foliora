import SwiftUI

/// Displays the origin storage section interface.
struct OriginStorageSection: View {
    let place: Place?
    let storagePath: String
    let accentColor: Color
    let isStorageAssigned: Bool
    let canEdit: Bool
    let onEditOrigin: () -> Void
    let onEditStorage: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: CatalogMetrics.Spacing.md) {
            CatalogOriginTile(
                place: place,
                accentColor: accentColor,
                canEdit: canEdit,
                onEdit: onEditOrigin
            )

            CatalogStorageTile(
                storagePath: storagePath,
                accentColor: accentColor,
                isAssigned: isStorageAssigned,
                canEdit: canEdit,
                onEdit: onEditStorage
            )
        }
    }
}
