import Data
import Domain
import Foundation
import Infrastructure
import Presentation

/// 実装の組み立てはここだけで行う。
/// 各画面は Domain のプロトコルにしか依存しないため、UI テストでは実装だけを差し替えられる。
enum CompositionRoot {
    static func makeDependencies() -> AppDependencies {
        #if DEBUG
        if UITestConfiguration.isEnabled {
            return UITestConfiguration.makeDependencies()
        }
        #endif
        return makeLiveDependencies()
    }

    static func makeLiveDependencies() -> AppDependencies {
        let opener = SystemURLOpener()
        return AppDependencies(searchService: MapKitPlaceSearchService(),
                               // 経路は区間単位で取得する。停留所の推定と区間 ETA だけで成立する。
                               planner: RoutePlanner(stops: MapKitTransitStopLocator(),
                                                     routing: MapKitRouteService()),
                               locationService: CoreLocationService(),
                               placeResolver: CoreLocationPlaceResolver(),
                               detailLinking: GoogleMapsURLBuilder(opener: opener),
                               store: UserDefaultsLocalStore())
    }
}
