import SwiftUI

/// Displays the dashboard card interface.
struct DashboardCard<Leading: View, Content: View>: View {
    let leading: Leading
    let content: Content
    let cardHeight: CGFloat = 72 

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder content: () -> Content
    ) {
        self.leading = leading()
        self.content = content()
    }

    var body: some View {
        HStack(spacing: CatalogMetrics.Spacing.md) {
            leading

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: cardHeight)
        .catalogSurfaceCard()
    }
}

/// Displays a compact dashboard metric capsule.
struct MetricPill: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    var isInteractive = true
    var action: (() -> Void)?

    var body: some View {
        if isInteractive, let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: CatalogMetrics.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(CatalogTypography.cardSubtitle)

            Text(value)
                .font(CatalogTypography.cardSubtitle)
                .foregroundStyle(.secondary)
        }
        .catalogSurfaceCapsule()
    }
}

/// Displays a shared dashboard popover list container.
struct DashboardPopoverContainer<Entry, Content: View>: View {
    let title: String
    let entries: [Entry]
    let onSelect: ((Entry) -> Void)?
    let content: (Entry) -> Content

    init(
        title: String,
        entries: [Entry],
        onSelect: ((Entry) -> Void)? = nil,
        @ViewBuilder content: @escaping (Entry) -> Content
    ) {
        self.title = title
        self.entries = entries
        self.onSelect = onSelect
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries.indices, id: \.self) { index in
                        let entry = entries[index]

                        Group {
                            if let onSelect {
                                Button {
                                    onSelect(entry)
                                } label: {
                                    content(entry)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            } else {
                                content(entry)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if index < entries.count - 1 {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .presentationDetents([.medium])
    }
}

/// Displays a shared data-health entry row.
struct DashboardDataHealthRow: View {
    let title: String
    let countText: String
    let missingProgress: Double
    var showsDisclosureIndicator = false

    var body: some View {
        HStack(spacing: CatalogMetrics.Spacing.md) {
            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xxs) {
                Text(title)
                    .font(CatalogTypography.cardSubtitle)
                    .foregroundStyle(.primary)

                GeometryReader { proxy in
                    HStack(spacing: CatalogMetrics.Spacing.sm) {
                        Text(countText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        DashboardDataHealthMissingProgressBar(progress: missingProgress)
                            .frame(width: proxy.size.width / 2)

                        if showsDisclosureIndicator {
                            Image(systemName: "chevron.right")
                                .font(CatalogTypography.chipLabel)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(CatalogMetrics.Spacing.md)
    }
}

private struct DashboardDataHealthMissingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.green.opacity(0.35))

                Capsule()
                    .fill(.red.opacity(0.8))
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 6, maxHeight: 6)
    }
}
