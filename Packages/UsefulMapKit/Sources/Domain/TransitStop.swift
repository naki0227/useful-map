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

    public var symbolName: String {
        switch self {
        case .train: return "tram.fill"
        case .bus: return "bus.fill"
        }
    }
}

public enum TransitStopClassifier {
    /// 鉄道とみなす手がかり。日本語・英語・韓国語・中国語の駅名表記に加え、
    /// 空港連絡や新幹線のように「駅」が付かない表記も拾う。
    private static let trainMarkers = [
        "駅", "station", "역", "站",
        "新幹線", "地下鉄", "メトロ", "metro", "subway", "rail", "線のりば"
    ]

    /// バス停とみなす手がかり（明示されている場合）。
    private static let busMarkers = [
        "バス停", "停留所", "停留場", "電停", "バスターミナル", "bus stop", "bus terminal",
        "정류장", "公交", "巴士"
    ]

    /// 名称から種別を推定する。
    ///
    /// MapKit の POI カテゴリは `.publicTransport` の 1 種類しかなく、
    /// 駅とバス停を区別できないため名称で判断する。
    /// 日本では駅名にほぼ必ず「駅」が付き、バス停には付かないことが多い。
    /// そのため鉄道の手がかりが無いものはバス停として扱う。
    ///
    /// 「淀屋橋」のように駅名から「駅」が落ちた表記はバス停に倒れるが、
    /// 影響はアイコン表示と「長距離なら駅を優先」の判断だけで、
    /// 経路計算には効かない（最寄りを選ぶ規則にフォールバックする）。
    public static func kind(of place: Place) -> TransitStopKind {
        let name = place.name
        if busMarkers.contains(where: { name.localizedCaseInsensitiveContains($0) }) { return .bus }
        if trainMarkers.contains(where: { name.localizedCaseInsensitiveContains($0) }) { return .train }
        return .bus
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
