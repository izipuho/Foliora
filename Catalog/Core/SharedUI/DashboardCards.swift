import SwiftUI

private struct CatalogDashboardMutationTargetPreferenceKey: PreferenceKey {
    static var defaultValue: String? { nil }

    static func reduce(value: inout String?, nextValue: () -> String?) {
        value = nextValue() ?? value
    }
}

extension View {
    func catalogDashboardMutationTarget(id: String, isExpanded: Bool) -> some View {
        self
            .id(id)
            .preference(
                key: CatalogDashboardMutationTargetPreferenceKey.self,
                value: isExpanded ? id : nil
            )
    }
}

/// Displays a horizontally scrolling dashboard card strip and keeps an expanded mutation target visible.
struct CatalogDashboardCardStrip<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: CatalogMetrics.Spacing.md) {
                    content
                }
            }
            .scrollClipDisabled()
            .onPreferenceChange(CatalogDashboardMutationTargetPreferenceKey.self) { targetID in
                guard let targetID else { return }
                DispatchQueue.main.async {
                    withAnimation(.snappy) {
                        scrollProxy.scrollTo(targetID, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 104)
    }
}

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
