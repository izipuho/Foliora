import SwiftUI

/// Scroll container for item detail screens that open with a full-bleed hero image.
///
/// While the in-content title is visible, the navigation bar stays clean: the top scroll edge
/// effect is hidden and the bar shows no title. Once the title scrolls under the bar, the system
/// edge effect returns and the bar shows a compact title with an optional thumbnail.
///
/// Mark the in-content title with ``SwiftUI/View/heroCollapsingTitleAnchor()``.
/// Toolbar buttons stay with the calling screen.
struct HeroCollapsingScrollView<Content: View, BarThumbnail: View>: View {
    let title: String
    private let barThumbnail: BarThumbnail?
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var titleTracker = HeroCollapsingTitleTracker()
    @State private var topBarInset: CGFloat = 0
    @State private var isTitleInBar = false

    /// - Parameters:
    ///   - title: Item title shown in the bar once the in-content title scrolls away.
    ///   - barThumbnail: Small image shown next to the bar title; `nil` shows the title alone.
    init(
        title: String,
        barThumbnail: BarThumbnail?,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.barThumbnail = barThumbnail
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
        }
        .coordinateSpace(.named(HeroCollapsingTitleAnchor.coordinateSpaceName))
        .scrollPosition($scrollPosition)
        .environment(\.heroCollapsingTitleTracker, titleTracker)
        .ignoresSafeArea(edges: .top)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.safeAreaInsets.top
        } action: { inset in
            topBarInset = inset
        }
        .onChange(of: shouldShowTitleInBar, initial: true) { _, newValue in
            guard newValue != isTitleInBar else { return }
            withAnimation(reduceMotion ? .linear(duration: 0.15) : .snappy(duration: 0.25)) {
                isTitleInBar = newValue
            }
        }
        .scrollEdgeEffectHidden(!isTitleInBar, for: .top)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                barTitle
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    /// The title has scrolled under the navigation bar.
    private var shouldShowTitleInBar: Bool {
        topBarInset > 0 && titleTracker.titleMaxY < topBarInset
    }

    private var barTitle: some View {
        HStack(spacing: CatalogMetrics.Spacing.sm) {
            if let barThumbnail {
                barThumbnail
                    .frame(width: 30, height: 30)
                    .clipShape(.rect(cornerRadius: 7))
            }

            ViewThatFits {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .opacity(isTitleInBar ? 1 : 0)
        .scaleEffect(isTitleInBar || reduceMotion ? 1 : 0.7)
        .contentShape(.rect)
        .onTapGesture {
            withAnimation {
                scrollPosition.scrollTo(edge: .top)
            }
        }
        .accessibilityHidden(!isTitleInBar)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension HeroCollapsingScrollView where BarThumbnail == EmptyView {
    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.barThumbnail = nil
        self.content = content()
    }
}

/// Bottom edge of the in-content title, in the scroll viewport's coordinate space.
@MainActor
@Observable
final class HeroCollapsingTitleTracker {
    var titleMaxY: CGFloat = .infinity
}

extension EnvironmentValues {
    @Entry var heroCollapsingTitleTracker: HeroCollapsingTitleTracker?
}

/// Reports the bottom edge of the in-content title to the enclosing ``HeroCollapsingScrollView``.
private struct HeroCollapsingTitleAnchor: ViewModifier {
    nonisolated static let coordinateSpaceName = "HeroCollapsingScrollView"

    @Environment(\.heroCollapsingTitleTracker) private var tracker

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .named(Self.coordinateSpaceName)).maxY
        } action: { maxY in
            tracker?.titleMaxY = maxY
        }
    }
}

extension View {
    /// Marks this view as the title tracked by the enclosing ``HeroCollapsingScrollView``.
    func heroCollapsingTitleAnchor() -> some View {
        modifier(HeroCollapsingTitleAnchor())
    }
}
