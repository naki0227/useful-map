import Foundation

/// 公共交通の乗降地点の種別。
///
/// MapKit の POI カテゴリは `.publicTransport` の 1 種類しかなく、
/// 駅・バス停・地下鉄を区別できない。そのため名称から推定する。
/// 表示（アイコンとラベル）と、分割時にどちらを優先するかの判断にだけ使い、
/// 経路計算そのものには影響させない。
public enum TransitStopKind: String, Sendable, CaseIterable {
    case train
    case bus
    case unknown

    public var symbolName: String {
        switch self {
        case .train: return "tram.fill"
        case .bus: return "bus.fill"
        case .unknown: return "figure.wave"
        }
    }
}

public enum TransitStopClassifier {
    private static let trainMarkers = ["駅", "station", "Station", "STATION", "역", "站"]
    private static let busMarkers = ["バス停", "停留所", "bus stop", "Bus Stop", "バスターミナル",
                                     "정류장", "公交", "巴士"]

    public static func kind(of place: Place) -> TransitStopKind {
        let name = place.name
        if busMarkers.contains(where: { name.localizedCaseInsensitiveContains($0) }) { return .bus }
        if trainMarkers.contains(where: { name.localizedCaseInsensitiveContains($0) }) { return .train }
        return .unknown
    }

    /// 鉄道を優先して選べる距離の上乗せ分。
    /// 「最寄りより少し遠い程度なら駅を選ぶ」までに留め、
    /// 数 km 先の駅を乗車地点にしてしまわないようにする。
    public static let trainDetourAllowanceMeters: Double = 400

    /// 近い順に選ぶ。長距離の移動では、近くに駅があれば多少遠くても駅を優先する。
    public static func preferred(from candidates: [Place],
                                 near coordinate: Coordinate,
                                 preferTrain: Bool,
                                 trainDetourAllowance: Double = trainDetourAllowanceMeters) -> Place? {
        let sorted = candidates.sorted {
            $0.coordinate.distance(to: coordinate) < $1.coordinate.distance(to: coordinate)
        }
        guard let nearest = sorted.first else { return nil }
        guard preferTrain else { return nearest }

        let limit = nearest.coordinate.distance(to: coordinate) + trainDetourAllowance
        let train = sorted.first {
            kind(of: $0) == .train && $0.coordinate.distance(to: coordinate) <= limit
        }
        return train ?? nearest
    }
}
