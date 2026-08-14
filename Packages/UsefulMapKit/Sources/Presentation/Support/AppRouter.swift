import Domain
import Foundation
import MapKit

/// タブと画面遷移の状態。
@MainActor
public final class AppRouter: ObservableObject {
    public enum Tab: String, Hashable, CaseIterable, Identifiable {
        case map
        case route
        case saved

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .map: return "地図"
            case .route: return "経路"
            case .saved: return "保存"
            }
        }

        public var symbolName: String {
            switch self {
            case .map: return "map"
            case .route: return "arrow.triangle.swap"
            case .saved: return "bookmark"
            }
        }
    }

    @Published public var selectedTab: Tab = .map
    /// 場所詳細（S03）に表示中の地点。
    @Published public var detailPlace: Place?
    /// 検索シート（S02）の表示状態。
    @Published public var isSearchPresented = false
    /// 経路タブ（S04）で比較中の条件。
    @Published public var activeQuery: RouteQuery?

    public init() {}

    public func showPlaceDetail(_ place: Place) {
        detailPlace = place
        isSearchPresented = false
    }

    public func showRoute(_ query: RouteQuery) {
        activeQuery = query
        detailPlace = nil
        selectedTab = .route
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
