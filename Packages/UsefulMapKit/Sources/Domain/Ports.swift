import Foundation

// 外部世界との境界（ポート）。実装は Data / Infrastructure が持ち、
// Presentation はこのファイルの型にだけ依存する。

// MARK: - 検索

public enum PlaceSearchError: Error, Equatable, Sendable {
    case cancelled
    case failed(String)
}

public protocol PlaceSearching: Sendable {
    /// MKLocalSearch 相当。呼び出し側は Task の cancel で中断できること（仕様書 14）。
    func search(query: String, around: Coordinate?) async throws -> [Place]
}

// MARK: - 経路

public enum RouteError: Error, Equatable, Sendable {
    /// MapKit が候補を返さなかった。
    case noRoutesFound
    /// 地域・モードの都合で MapKit が経路を提供しない（例: 公共交通非対応地域）。
    case unsupportedInRegion(TransportMode)
    case cancelled
    case failed(String)

    public var localizedMessage: String {
        switch self {
        case .noRoutesFound:
            return L10n.string("route.error.noRoutes")
        case let .unsupportedInRegion(mode):
            return L10n.string("route.error.unsupported", mode.displayName)
        case .cancelled:
            return L10n.string("route.error.cancelled")
        case let .failed(message):
            return message
        }
    }
}

// MARK: - 位置情報

public enum LocationAuthorizationStatus: String, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

public enum LocationError: Error, Equatable, Sendable {
    case denied
    case unavailable
    case timedOut
}

/// 位置情報は UI 主導で 1 点取得するだけなので、呼び出しは MainActor 側に閉じる。
/// （Sendable を要求せず、CLLocationManager をそのまま保持できるようにする）
public protocol LocationProviding: AnyObject {
    var authorizationStatus: LocationAuthorizationStatus { get }
    func requestAuthorization()
    /// 現在地を 1 点だけ取得する。権限が無い場合は LocationError.denied。
    func currentCoordinate() async throws -> Coordinate
}

// MARK: - 外部詳細遷移（Google Maps）

public enum DetailOpenOutcome: String, Equatable, Sendable {
    /// 時刻付き Primary URL で開けた。
    case openedPrimary
    /// 公式 Directions URL へ fallback して開いた。
    case openedFallback
    /// どちらも開けなかった。
    case failed
}

public protocol RouteDetailLinking: Sendable {
    /// 時刻付き Primary URL。生成できない場合は nil。
    func primaryURL(for option: RouteOption) -> URL?
    /// 公式 Maps URLs の Directions URL。
    func officialURL(for option: RouteOption) -> URL?
    /// Primary → 失敗時 official の順で開く（仕様書 7.5）。
    func open(_ option: RouteOption) async -> DetailOpenOutcome
}

public protocol URLOpening: Sendable {
    /// 開けたら true。
    func open(_ url: URL) async -> Bool
}

// MARK: - 公共交通の乗降地点

/// MapKit は公共交通の乗車駅を返さないため、地理的に近い停留所をアプリ側で探して補う。
/// 推定なので実際の路線事情とはズレうる。ユーザーが選び直せることを前提にする。
public protocol TransitStopLocating: Sendable {
    /// 指定座標の近くにある公共交通の乗降地点を、近い順に返す。
    func stops(near coordinate: Coordinate, within meters: Double, limit: Int) async throws -> [Place]
}

// MARK: - 区間単位の経路取得

public protocol SegmentRouting: Sendable {
    /// 1 区間ぶんの所要時間・時刻・距離・経路線を取得する。
    func leg(from: Place,
             to: Place,
             mode: TransportMode,
             timePreference: TimePreference,
             requestedDate: Date?) async throws -> RouteLeg
}

// MARK: - 座標から地点へ

/// 地図をタップして地点を選ぶための逆引き。
public protocol PlaceResolving: Sendable {
    /// 座標に対応する地点。名称が取れなければ座標そのものを名前にする。
    func place(at coordinate: Coordinate) async -> Place
}
