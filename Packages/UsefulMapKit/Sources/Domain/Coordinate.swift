import Foundation

/// MapKit から得た座標をアプリ内部で扱うための最小表現。
/// Google 固有の Place ID は保持しない（仕様書 5.1）。
public struct Coordinate: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// 緯度経度として妥当か。NaN / 範囲外 / (0,0) は URL 生成に使わない。
    public var isValid: Bool {
        guard latitude.isFinite, longitude.isFinite else { return false }
        guard (-90.0...90.0).contains(latitude), (-180.0...180.0).contains(longitude) else { return false }
        return !(latitude == 0 && longitude == 0)
    }

    /// URL やキーで使う固定精度表現（小数 7 桁 = 約 1cm）。
    public var latitudeString: String { Coordinate.format(latitude) }
    public var longitudeString: String { Coordinate.format(longitude) }

    public static func format(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        return String(format: "%.7f", value)
    }

    /// 球面距離（メートル）。CoreLocation に依存せず Domain 内で完結させる。
    public func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_008.8
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }
}
