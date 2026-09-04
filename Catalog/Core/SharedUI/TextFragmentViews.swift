import Foundation
import SwiftUI

struct TextFragmentBar: View {
    let fragments: [TextFragment]
    let usedFragmentIDs: Set<UUID>

    private var availableFragments: [TextFragment] {
        fragments
            .filter { !usedFragmentIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsPriority = presentationPriority(for: lhs.text)
                let rhsPriority = presentationPriority(for: rhs.text)

                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }

                return TextFragment.readingOrder(lhs, rhs)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CatalogMetrics.Spacing.sm) {
                    ForEach(availableFragments) { fragment in
                        TextFragmentChip(
                            fragment: fragment,
                            transfer: TextFragmentTransfer(id: fragment.id)
                        )
                    }
                }
                .padding(.horizontal, CatalogMetrics.Insets.screen)
                .padding(.vertical, CatalogMetrics.Spacing.sm)
            }
        }
        .background(.ultraThinMaterial)
    }

    private func presentationPriority(for rawText: String) -> Int {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        let letterCount = text.lazy.filter { $0.isLetter }.count
        let lowercaseText = text.lowercased()
        let looksLikeWebAddress = lowercaseText.contains("http://")
            || lowercaseText.contains("https://")
            || lowercaseText.contains("www.")
            || text.contains("@")
        let endsLikeSentence = text.last.map { ".!?".contains($0) } ?? false

        if looksLikeWebAddress {
            return 3
        }

        if letterCount >= 3, wordCount <= 5, text.count <= 50 {
            return 0
        }

        if wordCount >= 6, endsLikeSentence {
            return 2
        }

        if letterCount >= 3, wordCount <= 10, text.count <= 90 {
            return 1
        }

        if text.count <= 90 {
            return 2
        }

        return 3
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
