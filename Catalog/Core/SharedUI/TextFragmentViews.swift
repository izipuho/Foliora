import Foundation
import SwiftUI

struct TextFragmentBar: View {
    let fragments: [TextFragment]
    let usedFragmentIDs: Set<UUID>

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CatalogMetrics.Spacing.sm) {
                    ForEach(fragments) { fragment in
                        if !usedFragmentIDs.contains(fragment.id) {
                            TextFragmentChip(
                                fragment: fragment,
                                transfer: TextFragmentTransfer(id: fragment.id)
                            )
                        }
                    }
                }
                .padding(.horizontal, CatalogMetrics.Insets.screen)
                .padding(.vertical, CatalogMetrics.Spacing.sm)
            }
        }
        .background(.ultraThinMaterial)
    }
}

struct TextFragmentChip: View {
    let fragment: TextFragment
    let transfer: TextFragmentTransfer

    var body: some View {
        Text(fragment.text)
            .font(.subheadline)
            .lineLimit(1)
            .frame(maxWidth: 240)
            .catalogSurfaceCapsule()
            .contentShape(.interaction, Rectangle())
            .contentShape(.dragPreview, CatalogShapes.capsule)
            .draggable(transfer)
            .accessibilityLabel(fragment.text)
    }
}

struct AssignedTextFragmentChip: View {
    let fragment: TextFragment
    let statusSystemImage: String?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: CatalogMetrics.Spacing.xxs) {
            Text(fragment.text)
                .lineLimit(1)

            if let statusSystemImage {
                Image(systemName: statusSystemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "common.delete"))
        }
        .font(.subheadline)
        .frame(maxWidth: 240)
        .catalogSurfaceCapsule()
    }
}
