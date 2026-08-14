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
                .tabItem { Label(AppRouter.Tab.map.displayName, systemImage: AppRouter.Tab.map.symbolName) }
                .tag(AppRouter.Tab.map)

            RouteTabView(dependencies: dependencies)
                .tabItem { Label(AppRouter.Tab.route.displayName, systemImage: AppRouter.Tab.route.symbolName) }
                .tag(AppRouter.Tab.route)

            SavedView(dependencies: dependencies)
                .tabItem { Label(AppRouter.Tab.saved.displayName, systemImage: AppRouter.Tab.saved.symbolName) }
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
                    Label("経路がありません", systemImage: "arrow.triangle.swap")
                } description: {
                    Text("目的地を検索して「経路」を押すと、移動手段ごとの所要時間を比較できます。")
                } actions: {
                    Button("地図から検索") { router.selectedTab = .map }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
