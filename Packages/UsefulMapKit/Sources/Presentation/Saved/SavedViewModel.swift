import Domain
import Foundation

/// S06 保存・履歴。アカウント / クラウド同期は持たない（仕様書 11）。
@MainActor
public final class SavedViewModel: ObservableObject {
    @Published public private(set) var savedPlaces: [SavedPlace] = []
    @Published public private(set) var recentRoutes: [RecentRoute] = []
    @Published public private(set) var recentSearches: [RecentSearch] = []

    private let store: LocalStoring
    private let now: () -> Date

    public init(dependencies: AppDependencies) {
        self.store = dependencies.store
        self.now = dependencies.now
        refresh()
    }

    public func refresh() {
        savedPlaces = store.savedPlaces
        recentRoutes = store.recentRoutes
        recentSearches = store.recentSearches
    }

    public func save(_ place: Place, label: SavedPlace.Label = .other) {
        store.savePlace(place, label: label, at: now())
        refresh()
    }

    public func remove(id: SavedPlace.ID) {
        store.removeSavedPlace(id: id)
        refresh()
    }

    public func isSaved(_ place: Place) -> Bool {
        store.isSaved(place)
    }

    /// 保存済みならそのラベル。未保存なら nil。
    public func label(for place: Place) -> SavedPlace.Label? {
        savedPlaces.first { $0.id == place.id }?.label
    }

    /// 保存済み地点のラベルを変更する。保存日時は維持し、一覧では先頭へ移動する。
    public func setLabel(_ label: SavedPlace.Label, for place: Place) {
        let savedAt = savedPlaces.first { $0.id == place.id }?.savedAt ?? now()
        store.savePlace(place, label: label, at: savedAt)
        refresh()
    }

    /// 保存 / 解除のトグル。場所詳細（S03）の「保存」から使う。
    public func toggleSave(_ place: Place, label: SavedPlace.Label = .other) {
        if store.isSaved(place) {
            store.removeSavedPlace(id: place.id)
        } else {
            store.savePlace(place, label: label, at: now())
        }
        refresh()
    }

    public func clearHistory() {
        store.clearHistory()
        refresh()
    }

    /// 履歴から経路を復元する。区間の分割は開いた直後に組み直される。
    public func plan(from route: RecentRoute) -> RoutePlan {
        let originPlace = route.origin.place
            ?? Place(name: RouteEndpoint.currentLocation.displayName,
                     coordinate: route.destination.coordinate)
        return RoutePlan.simple(origin: RouteNode(place: originPlace,
                                                  kind: .origin,
                                                  isCurrentLocation: route.origin.isCurrentLocation),
                                destination: RouteNode(place: route.destination, kind: .destination),
                                mode: route.transportMode)
    }
}
