import Domain
import Foundation
import MapKit

/// タブと画面遷移の状態。
@MainActor
final class AppRouter: ObservableObject {
    enum Tab: String, Hashable, CaseIterable, Identifiable {
        case map
        case saved

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .map: return "map"
            case .saved: return "bookmark"
            }
        }
    }

    @Published var selectedTab: Tab = .map
    /// 場所詳細（S03）に表示中の地点。
    @Published var detailPlace: Place?
    /// 検索シート（S02）の表示状態。
    @Published var isSearchPresented = false
    /// 経路を編集・表示中の ViewModel。nil なら経路は開いていない。
    /// 地図画面の上下のシートがこれを見て表示を切り替える。
    @Published var planViewModel: RoutePlanViewModel?
    /// 「地図で選ぶ」中に、どのノードへ反映するか。
    @Published var mapPickTarget: Int?

    init() {}

    func showPlaceDetail(_ place: Place) {
        detailPlace = place
        isSearchPresented = false
    }

    /// 経路を開く。地図はそのままで、上下のシートだけが切り替わる。
    func showRoute(_ plan: RoutePlan, dependencies: AppDependencies) {
        let viewModel = RoutePlanViewModel(plan: plan, dependencies: dependencies)
        planViewModel = viewModel
        detailPlace = nil
        isSearchPresented = false
        selectedTab = .map
        viewModel.rebuild(preset: plan.modes.first ?? .transit)
    }

    /// 経路を閉じて地図に戻る。
    func closeRoute() {
        planViewModel = nil
        mapPickTarget = nil
    }
}

/// Presentation 内で使う座標変換。Infrastructure に依存せず SwiftUI Map へ渡すためのもの。
extension Coordinate {
    var mapCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func region(spanMeters: Double = 1_500) -> MKCoordinateRegion {
        MKCoordinateRegion(center: mapCoordinate,
                           latitudinalMeters: spanMeters,
                           longitudinalMeters: spanMeters)
    }
}
