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
enum A11y {
    static let searchField = "search.field"
    static let recenterButton = "map.recenter"
    static let routeButton = "placeDetail.route"
    static let saveButton = "placeDetail.save"
    static let placeTitle = "placeDetail.title"
    static let routeError = "routeCompare.error"
    static let lastOpenedURL = "debug.lastOpenedURL"

    static let walkingPaceButton = "route.walkingPace"
    static let swapButtonInline = "route.swap"
    static let currentLocationButton = "route.useCurrentLocation"
    static let closeRouteButton = "route.close"
    static let draftOrigin = "draft.origin"
    static let timeCondition = "time.condition"
    static let timePreferencePicker = "time.preference"
    static let datePicker = "time.date"
    static let pickOnMapButton = "route.pickOnMap"
    static let planTotal = "route.total"

    static func addWaypoint(_ index: Int) -> String { "route.addWaypoint.\(index)" }
    static func node(_ index: Int) -> String { "route.node.\(index)" }
    static func nodeField(_ index: Int) -> String { "route.node.field.\(index)" }
    static func segmentMode(_ index: Int) -> String { "route.segment.mode.\(index)" }
    static func segmentTime(_ index: Int) -> String { "route.segment.time.\(index)" }
    static func preset(_ id: String) -> String { "route.preset.\(id)" }
    static func updateKeep(_ index: Int) -> String { "route.update.keep.\(index)" }
    static func updateApply(_ index: Int) -> String { "route.update.apply.\(index)" }
    static func saveLabelOption(_ label: String) -> String { "placeDetail.saveLabel.\(label)" }
    static func savedPlaceMenu(_ index: Int) -> String { "saved.place.menu.\(index)" }
    static func savedLabelOption(_ label: String) -> String { "saved.label.\(label)" }
    static func searchResult(_ index: Int) -> String { "search.result.\(index)" }
    static func detailButton(_ index: Int) -> String { "routeCompare.detail.\(index)" }
    static func savedPlace(_ index: Int) -> String { "saved.place.\(index)" }
    static func recentRoute(_ index: Int) -> String { "saved.route.\(index)" }
    static func recentSearch(_ index: Int) -> String { "map.recentSearch.\(index)" }
}
