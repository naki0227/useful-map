import Domain
import SwiftUI

/// タブ構成（モック: 地図 / 経路 / 保存）。
public struct RootView: View {
    private let dependencies: AppDependencies
    @StateObject private var router = AppRouter()

    public init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    public var body: some View {
        TabView(selection: $router.selectedTab) {
            MapHomeView(dependencies: dependencies)
                .tabItem { Label(L10n.string("tab.map"), systemImage: AppRouter.Tab.map.symbolName) }
                .tag(AppRouter.Tab.map)

            RouteTabView(dependencies: dependencies)
                .tabItem { Label(L10n.string("tab.route"), systemImage: AppRouter.Tab.route.symbolName) }
                .tag(AppRouter.Tab.route)

            SavedView(dependencies: dependencies)
                .tabItem { Label(L10n.string("tab.saved"), systemImage: AppRouter.Tab.saved.symbolName) }
                .tag(AppRouter.Tab.saved)
        }
        .environmentObject(router)
    }
}

/// 経路タブ。比較条件が未設定なら地図タブへ誘導する。
struct RouteTabView: View {
    let dependencies: AppDependencies
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Group {
            if let query = router.activeQuery {
                RouteCompareView(query: query, dependencies: dependencies)
                    // 条件が外部から差し替わったら ViewModel ごと作り直す。
                    .id(query)
            } else {
                ContentUnavailableView {
                    Label(L10n.string("route.none.title"), systemImage: "arrow.triangle.swap")
                } description: {
                    Text(l10n: "route.none.body")
                } actions: {
                    Button(L10n.string("route.none.action")) { router.selectedTab = .map }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
