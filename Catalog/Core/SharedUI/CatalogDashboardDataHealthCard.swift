import SwiftUI

/// Displays catalog data health status in a dashboard card that expands in place.
struct CatalogDashboardDataHealthCard<Entry, Content: View>: View {
    let progress: Double
    let tint: Color
    let entries: [Entry]
    let onSelect: (Entry) -> Void
    let content: (Entry) -> Content

    @State private var isExpanded = false

    init(
        progress: Double,
        tint: Color,
        entries: [Entry],
        onSelect: @escaping (Entry) -> Void,
        @ViewBuilder content: @escaping (Entry) -> Content
    ) {
        self.progress = progress
        self.tint = tint
        self.entries = entries
        self.onSelect = onSelect
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: CatalogMetrics.Spacing.md) {
                    progressIndicator

                    VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                        Text(String(localized: "catalog.dashboard.health"))
                            .font(CatalogTypography.sectionTitle)
                        Text(String(localized: "catalog.dashboard.health.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(CatalogTypography.chipLabel)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .frame(height: 72)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()

                LazyVStack(spacing: 0) {
                    ForEach(entries.indices, id: \.self) { index in
                        let entry = entries[index]

                        Button {
                            withAnimation(.snappy) {
                                isExpanded = false
                            }
                            onSelect(entry)
                        } label: {
                            content(entry)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < entries.count - 1 {
                            Divider()
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(minWidth: isExpanded ? 320 : nil, alignment: .leading)
        .catalogSurfaceCard()
        .animation(.snappy, value: isExpanded)
    }

    private var progressIndicator: some View {
        ZStack {
            Circle()
                .stroke(Color(uiColor: .separator), lineWidth: 8)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text(progress.formatted(.percent.precision(.fractionLength(0))))
                .font(CatalogTypography.cardSubtitle)
        }
        .frame(width: 56, height: 56)
    }
}
