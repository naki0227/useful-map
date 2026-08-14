import Domain
import Foundation
import SwiftUI

/// Presentation が必要とする外部機能一式。実装の組み立ては App（composition root）が行う。
public struct AppDependencies {
    public let searchService: PlaceSearching
    public let routeService: RouteProviding
    public let locationService: LocationProviding
    public let detailLinking: RouteDetailLinking
    public let store: LocalStoring
    /// 現在時刻。テストで固定できるよう関数で持つ。
    public let now: () -> Date
    /// 検索入力のデバウンス。UI テストでは 0 にして待ち時間を無くす。
    public let searchDebounce: Duration

    public init(searchService: PlaceSearching,
                routeService: RouteProviding,
                locationService: LocationProviding,
                detailLinking: RouteDetailLinking,
                store: LocalStoring,
                now: @escaping () -> Date = Date.init,
                searchDebounce: Duration = .milliseconds(250)) {
        self.searchService = searchService
        self.routeService = routeService
        self.locationService = locationService
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
