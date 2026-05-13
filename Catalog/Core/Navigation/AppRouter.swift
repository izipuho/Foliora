import SwiftUI

enum AppDestination: Hashable {
    case collection(CollectionSummary)
    case home(UUID)
}

enum RootTab: String, CaseIterable, Identifiable {
    case collections
    case settings
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collections:
            return String(localized: "root_tab.collections")
        case .settings:
            return String(localized: "root_tab.settings")
        case .search:
            return String(localized: "root_tab.search")
        }
    }

    var systemImage: String {
        switch self {
        case .collections:
            return "square.grid.2x2"
        case .settings:
            return "gearshape"
        case .search:
            return "magnifyingglass"
        }
    }
}

struct AppShellView: View {
    let repository: any CatalogRepository

    var body: some View {
        RootShellView(repository: repository)
    }
}

private struct RootShellView: View {
    let repository: any CatalogRepository

    var body: some View {
        TabView {
            Tab(RootTab.collections.title, systemImage: RootTab.collections.systemImage) {
                CollectionsView(repository: repository)
            }

            Tab(RootTab.settings.title, systemImage: RootTab.settings.systemImage) {
                SettingsView(repository: repository)
            }

            Tab(role: .search) {
                SearchTabView(repository: repository)
            }
        }
        .modifier(ModernTabBarBehavior())
        .tabViewSearchActivation(.searchTabSelection)
    }
}
private struct ModernTabBarBehavior: ViewModifier {
    func body(content: Content) -> some View {
        content.tabBarMinimizeBehavior(.onScrollDown)
    }
}