import SwiftUI

/// Displays the header of a nested group inside a catalog section, with its item count.
struct CatalogSubgroupHeader: View {
    let title: String
    let count: Int
    let isCollapsed: Bool
    let onToggle: (() -> Void)?

    init(
        title: String,
        count: Int,
        isCollapsed: Bool = false,
        onToggle: (() -> Void)? = nil
    ) {
        self.title = title
        self.count = count
        self.isCollapsed = isCollapsed
        self.onToggle = onToggle
    }

    var body: some View {
        Group {
            if let onToggle {
                Button(action: onToggle) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: CatalogMetrics.Spacing.xs) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if onToggle != nil {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text(count, format: .number)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, CatalogMetrics.Spacing.xs)
        .contentShape(Rectangle())
    }
}
