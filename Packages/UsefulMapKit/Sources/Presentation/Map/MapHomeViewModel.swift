import Domain
import Foundation

/// S01 地図ホーム。現在地の取得と、下部シートで再利用する履歴・保存地点を扱う。
@MainActor
public final class MapHomeViewModel: ObservableObject {
    @Published public private(set) var currentCoordinate: Coordinate?
    @Published public private(set) var authorizationStatus: LocationAuthorizationStatus
    @Published public private(set) var locationMessage: String?
    @Published public private(set) var recentSearches: [RecentSearch] = []
    @Published public private(set) var savedPlaces: [SavedPlace] = []
    @Published public var selectedPlace: Place?

    // MARK: - 検索前の条件（下書き）
    //
    // 検索してから条件を直すのではなく、最初に出発地と時刻条件を決めてから
    // 目的地を探せるようにする。

    /// 出発地。nil なら現在地。
    @Published public var draftOrigin: Place?
    @Published public var draftTimePreference: TimePreference = .now
    @Published public var draftDate: Date?
    /// 下書きのどの欄を編集しているか。
    @Published public var editingDraftField: DraftField?

    public enum DraftField: String, Identifiable {
        case origin
        case destination

        public var id: String { rawValue }
    }

    private let locationService: LocationProviding
    private let store: LocalStoring
    private let now: () -> Date

    public init(dependencies: AppDependencies) {
        self.locationService = dependencies.locationService
        self.store = dependencies.store
        self.now = dependencies.now
        self.authorizationStatus = dependencies.locationService.authorizationStatus
    }

    /// 位置権限が拒否されていても、出発地を手動で指定すれば利用できる（仕様書 12 / 13）。
    public var needsManualOrigin: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    public func onAppear() async {
        refreshStoredData()
        await refreshLocation()
    }

    public func refreshStoredData() {
        recentSearches = store.recentSearches
        savedPlaces = store.savedPlaces
    }

    public func requestAuthorizationIfNeeded() {
        if authorizationStatus == .notDetermined {
            locationService.requestAuthorization()
        }
    }

    /// 現在地へ戻る。
    public func refreshLocation() async {
        requestAuthorizationIfNeeded()
        do {
            let coordinate = try await locationService.currentCoordinate()
            currentCoordinate = coordinate
            authorizationStatus = locationService.authorizationStatus
            locationMessage = nil
        } catch LocationError.denied {
            authorizationStatus = locationService.authorizationStatus
            locationMessage = L10n.string("map.locationDenied")
        } catch {
            authorizationStatus = locationService.authorizationStatus
            locationMessage = L10n.string("map.locationUnavailable")
        }
    }

    /// 検索・履歴から選んだ地点を場所詳細（S03）へ渡す。
    public func select(_ place: Place) {
        selectedPlace = place
    }

    /// 出発地の表示名。未指定なら「現在地」。
    public var draftOriginName: String {
        draftOrigin?.displayName ?? RouteEndpoint.currentLocation.displayName
    }

    /// 時刻条件が指定済みかどうか（表示の強調に使う）。
    public var hasDraftTimeCondition: Bool {
        draftTimePreference.requiresDate
    }

    public func setDraftTimePreference(_ preference: TimePreference, date: Date?) {
        draftTimePreference = preference
        draftDate = preference.requiresDate ? (date ?? now()) : nil
    }

    public func useCurrentLocationAsDraftOrigin() {
        draftOrigin = nil
        editingDraftField = nil
    }

    /// 下書きの条件から経路プランを作る。
    ///
    /// 出発地の実座標は取得のたびに解決されるため、現在地の場合は印だけを持つ
    /// 仮のノードを置く。
    public func makePlan(destination: Place) -> RoutePlan {
        let originNode: RouteNode
        if let draftOrigin {
            originNode = RouteNode(place: draftOrigin, kind: .origin)
        } else {
            let placeholder = Place(name: RouteEndpoint.currentLocation.displayName,
                                    coordinate: currentCoordinate ?? destination.coordinate)
            originNode = RouteNode(place: placeholder, kind: .origin, isCurrentLocation: true)
        }
        return RoutePlan.simple(origin: originNode,
                                destination: RouteNode(place: destination, kind: .destination),
                                mode: .transit,
                                timePreference: draftTimePreference,
                                requestedDate: draftDate)
    }
}
