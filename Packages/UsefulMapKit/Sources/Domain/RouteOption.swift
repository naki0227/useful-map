import Foundation

/// Google Maps へ渡す時刻条件の基準（出発 or 到着）。
public struct TimeAnchor: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case depart
        case arrive
    }

    public let kind: Kind
    public let date: Date

    public init(kind: Kind, date: Date) {
        self.kind = kind
        self.date = date
    }
}

/// Google Maps へ区間を委譲するときの表現（仕様書 5.3）。
///
/// アプリ内の経路は RoutePlan（ノードと区間）で扱う。この型は
/// 「2 地点＋時刻条件」を外部サービスへ渡すための境界の形として残している。
///
/// 仕様書では `mapRoute: MKRoute` を保持する案だったが、Domain を MapKit から独立させるため
/// 描画に必要な情報だけを `geometry`（座標列）として保持する。MKRoute → geometry の変換は
/// Infrastructure 層が行う。
public struct RouteOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let query: RouteQuery
    /// 現在地を解決した後の実際の出発地点。
    public let origin: Place
    public let mode: TransportMode
    public let expectedTravelTime: TimeInterval
    public let departureDate: Date?
    public let arrivalDate: Date?
    public let distance: Double?
    public let geometry: [Coordinate]
    /// MapKit が返した経路名（"山手線" ではなく "国道 1 号" のような道路名）。
    public let routeName: String?

    public init(id: String = UUID().uuidString,
                query: RouteQuery,
                origin: Place,
                mode: TransportMode,
                expectedTravelTime: TimeInterval,
                departureDate: Date? = nil,
                arrivalDate: Date? = nil,
                distance: Double? = nil,
                geometry: [Coordinate] = [],
                routeName: String? = nil) {
        self.id = id
        self.query = query
        self.origin = origin
        self.mode = mode
        self.expectedTravelTime = expectedTravelTime
        self.departureDate = departureDate
        self.arrivalDate = arrivalDate
        self.distance = distance
        self.geometry = geometry
        self.routeName = routeName
    }

    public var destination: Place { query.destination }
    public var waypoints: [Place] { query.waypoints }

    /// Google Maps へ詳細を委譲できる候補か（公共交通のみ）。
    public var supportsExternalDetail: Bool {
        mode.delegatesDetailToGoogleMaps
    }

    /// 出発 / 到着時刻の両方が取得できているか（公共交通カードの時刻表示条件）。
    public var hasScheduledTimes: Bool {
        departureDate != nil && arrivalDate != nil
    }

    /// Google Maps 内部 URL に埋める時刻条件。
    /// 到着指定なら到着時刻、出発指定・現在なら出発時刻を使う。
    /// どの時刻も得られない場合は nil（= 時刻付き URL を作らず公式 URL へ fallback する）。
    public var timeAnchor: TimeAnchor? {
        switch query.timePreference {
        case .arriveBy:
            guard let date = arrivalDate ?? query.requestedDate else { return nil }
            return TimeAnchor(kind: .arrive, date: date)
        case .departAt:
            guard let date = departureDate ?? query.requestedDate else { return nil }
            return TimeAnchor(kind: .depart, date: date)
        case .now:
            guard let date = departureDate else { return nil }
            return TimeAnchor(kind: .depart, date: date)
        }
    }

    /// 経路生成に使う地点列。
    public var orderedPlaces: [Place] {
        query.orderedPlaces(resolvedOrigin: origin)
    }
}
