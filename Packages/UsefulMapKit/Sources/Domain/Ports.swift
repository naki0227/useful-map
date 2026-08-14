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
            return "利用可能な経路が見つかりませんでした"
        case let .unsupportedInRegion(mode):
            return "この地域では\(mode.displayName)の経路を取得できません"
        case .cancelled:
            return "検索を中断しました"
        case let .failed(message):
            return message
        }
    }
}

public protocol RouteProviding: Sendable {
    /// 指定モードの候補を返す。出発地は解決済みの Place を渡す。
    func routes(for query: RouteQuery, resolvedOrigin: Place) async throws -> [RouteOption]
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
