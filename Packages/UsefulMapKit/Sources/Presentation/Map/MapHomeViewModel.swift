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

    private let locationService: LocationProviding
    private let store: LocalStoring

    public init(dependencies: AppDependencies) {
        self.locationService = dependencies.locationService
        self.store = dependencies.store
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
            locationMessage = "位置情報が許可されていません。出発地を検索して指定できます"
        } catch {
            authorizationStatus = locationService.authorizationStatus
            locationMessage = "現在地を取得できませんでした"
        }
    }

    /// 検索・履歴から選んだ地点を場所詳細（S03）へ渡す。
    public func select(_ place: Place) {
        selectedPlace = place
    }

    /// 場所詳細から経路比較へ渡す初期条件。既定は「現在地から公共交通で」。
    public func defaultQuery(for place: Place) -> RouteQuery {
        RouteQuery(origin: .currentLocation, destination: place, transportMode: .transit)
    }
}
