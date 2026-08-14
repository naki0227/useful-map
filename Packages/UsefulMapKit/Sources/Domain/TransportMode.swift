import Foundation

/// MVP で比較対象にする移動手段。MapKit の transportType に 1:1 で対応させる。
/// 電車 / バスは MapKit では区別できないため「公共交通」に統合する（仕様書 6）。
public enum TransportMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case transit
    case walking
    case driving

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .transit: return "公共交通"
        case .walking: return "徒歩"
        case .driving: return "車"
        }
    }

    public var symbolName: String {
        switch self {
        case .transit: return "tram.fill"
        case .walking: return "figure.walk"
        case .driving: return "car.fill"
        }
    }

    /// MapKit が経路ジオメトリ（MKRoute）を返すのは徒歩・車のみ。
    /// 公共交通は ETA（出発 / 到着時刻・所要時間）だけを取得する。
    public var providesRouteGeometry: Bool {
        self != .transit
    }

    /// 公共交通のみ Google Maps へ詳細を委譲する（企画書 7）。
    public var delegatesDetailToGoogleMaps: Bool {
        self == .transit
    }

    /// 出発 / 到着時刻を持ちうるモード。徒歩・車は MapKit が時刻を返さない。
    public var supportsScheduledTimes: Bool {
        self == .transit
    }
}

// Google Maps 側の表現（公式 URL の travelmode / 内部形式のモードコード）は
// Domain には置かない。Data 層の GoogleMapsURLBuilder が対応表を持つ。
