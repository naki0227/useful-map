import Domain
import SwiftUI

/// タブは「地図」と「保存」だけ。
/// 経路は地図画面の上下のシートで扱うため、タブで行き来しない。
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

            SavedView(dependencies: dependencies)
                .tabItem { Label(L10n.string("tab.saved"), systemImage: AppRouter.Tab.saved.symbolName) }
                .tag(AppRouter.Tab.saved)
        }
        .environmentObject(router)
    }
}
