import Domain
import Foundation
import SwiftUI

/// Presentation が必要とする外部機能一式。実装の組み立ては App（composition root）が行う。
public struct AppDependencies {
    public let searchService: PlaceSearching
    /// 区間分割つきのプラン作成。最寄りの乗降地点の推定と、長い徒歩区間の再帰分割を行う。
    public let planner: RoutePlanner
    public let locationService: LocationProviding
    /// 地図タップから地点を作るための逆引き。
    public let placeResolver: PlaceResolving
    public let detailLinking: RouteDetailLinking
    public let store: LocalStoring
    /// 現在時刻。テストで固定できるよう関数で持つ。
    public let now: () -> Date
    /// 検索入力のデバウンス。UI テストでは 0 にして待ち時間を無くす。
    public let searchDebounce: Duration

    public init(searchService: PlaceSearching,
                planner: RoutePlanner,
                locationService: LocationProviding,
                placeResolver: PlaceResolving,
                detailLinking: RouteDetailLinking,
                store: LocalStoring,
                now: @escaping () -> Date = Date.init,
                searchDebounce: Duration = .milliseconds(250)) {
        self.searchService = searchService
        self.planner = planner
        self.locationService = locationService
        self.placeResolver = placeResolver
        self.detailLinking = detailLinking
        self.store = store
        self.now = now
        self.searchDebounce = searchDebounce
    }
}

/// アクセシビリティ識別子。E2E から参照するため一箇所に集約する。
public enum A11y {
    public static let searchField = "search.field"
    public static let searchCancel = "search.cancel"
    public static let searchEmpty = "search.empty"
    public static let recenterButton = "map.recenter"
    public static let routeButton = "placeDetail.route"
    public static let saveButton = "placeDetail.save"
    public static let placeTitle = "placeDetail.title"
    public static let routeCompareTitle = "routeCompare.title"
    public static let routeEmpty = "routeCompare.empty"
    public static let routeError = "routeCompare.error"
    public static let editRouteButton = "routeCompare.edit"
    public static let swapButton = "routeEditor.swap"
    public static let addWaypointButton = "routeEditor.addWaypoint"
    public static let closeEditorButton = "routeEditor.close"
    public static let lastOpenedURL = "debug.lastOpenedURL"

    public static let walkingPaceButton = "route.walkingPace"
    public static let swapButtonInline = "route.swap"
    public static let currentLocationButton = "route.useCurrentLocation"
    public static let closeRouteButton = "route.close"
    public static let pickOnMapButton = "route.pickOnMap"
    public static let planTotal = "route.total"
    public static let openDetailButton = "route.openDetail"

    public static func addWaypoint(_ index: Int) -> String { "route.addWaypoint.\(index)" }
    public static func node(_ index: Int) -> String { "route.node.\(index)" }
    public static func nodeField(_ index: Int) -> String { "route.node.field.\(index)" }
    public static func segmentMode(_ index: Int) -> String { "route.segment.mode.\(index)" }
    public static func segmentTime(_ index: Int) -> String { "route.segment.time.\(index)" }
    public static func preset(_ id: String) -> String { "route.preset.\(id)" }
    public static func updateKeep(_ index: Int) -> String { "route.update.keep.\(index)" }
    public static func updateApply(_ index: Int) -> String { "route.update.apply.\(index)" }
    public static func saveLabelOption(_ label: String) -> String { "placeDetail.saveLabel.\(label)" }
    public static func savedPlaceMenu(_ index: Int) -> String { "saved.place.menu.\(index)" }
    public static func savedLabelOption(_ label: String) -> String { "saved.label.\(label)" }
    public static func searchResult(_ index: Int) -> String { "search.result.\(index)" }
    public static func modeFilter(_ id: String) -> String { "routeCompare.mode.\(id)" }
    public static func routeCard(_ index: Int) -> String { "routeCompare.card.\(index)" }
    public static func detailButton(_ index: Int) -> String { "routeCompare.detail.\(index)" }
    public static func savedPlace(_ index: Int) -> String { "saved.place.\(index)" }
    public static func recentRoute(_ index: Int) -> String { "saved.route.\(index)" }
    public static func recentSearch(_ index: Int) -> String { "map.recentSearch.\(index)" }
}
