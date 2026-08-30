import SwiftUI

/// Displays catalog data health status in a dashboard card that expands over surrounding content.
struct CatalogDashboardDataHealthCard<Entry, Content: View>: View {
    let progress: Double
    let tint: Color
    let entries: [Entry]
    let expandedWidth: CGFloat?
    let onExpansionChanged: (Bool) -> Void
    let onSelect: (Entry) -> Void
    let content: (Entry) -> Content

    @State private var isExpanded = false

    init(
        progress: Double,
        tint: Color,
        entries: [Entry],
        expandedWidth: CGFloat? = nil,
        onExpansionChanged: @escaping (Bool) -> Void = { _ in },
        onSelect: @escaping (Entry) -> Void,
        @ViewBuilder content: @escaping (Entry) -> Content
    ) {
        self.progress = progress
        self.tint = tint
        self.entries = entries
        self.expandedWidth = expandedWidth
        self.onExpansionChanged = onExpansionChanged
        self.onSelect = onSelect
        self.content = content
    }

    var body: some View {
        compactCard
            .opacity(isExpanded ? 0 : 1)
            .frame(width: isExpanded ? expandedWidth : nil, alignment: .leading)
            .overlay(alignment: .topLeading) {
                if isExpanded {
                    expandedCard
                        .frame(width: expandedWidth, alignment: .leading)
                        .zIndex(1)
                }
            }
            .animation(.snappy, value: isExpanded)
    }

    private var compactCard: some View {
        header
            .catalogSurfaceCard()
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            VStack(spacing: 0) {
                ForEach(entries.indices, id: \.self) { index in
                    let entry = entries[index]

                    Button {
                        setExpanded(false)
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
        }
        .catalogSurfaceCard()
    }

    private var header: some View {
        Button {
            setExpanded(!isExpanded)
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
            }
            .frame(height: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func setExpanded(_ expanded: Bool) {
        withAnimation(.snappy) {
            isExpanded = expanded
        }
        onExpansionChanged(expanded)
    }
}
