import Foundation

/// 比較ロジック（仕様書 6）。
///
/// 「最善」は所要時間のみを主要指標とする。MapKit から取得できない運賃・乗換回数は
/// 推定も表示もしない（受け入れ条件 15）。
public enum RouteComparator {
    /// 所要時間の短い順。同着の場合は出発が早い順 → モードの安定順で決定的に並べる。
    public static func sorted(_ options: [RouteOption]) -> [RouteOption] {
        options.sorted { lhs, rhs in
            if lhs.expectedTravelTime != rhs.expectedTravelTime {
                return lhs.expectedTravelTime < rhs.expectedTravelTime
            }
            switch (lhs.departureDate, rhs.departureDate) {
            case let (left?, right?) where left != right:
                return left < right
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                break
            }
            if lhs.mode != rhs.mode {
                return modeOrder(lhs.mode) < modeOrder(rhs.mode)
            }
            return lhs.id < rhs.id
        }
    }

    /// おすすめ候補（= 所要時間が最短のもの）。候補が無ければ nil。
    public static func recommended(_ options: [RouteOption]) -> RouteOption? {
        sorted(options).first
    }

    /// モード別にまとめる。表示順は transit → walking → driving で固定する。
    public static func groupedByMode(_ options: [RouteOption]) -> [(mode: TransportMode, options: [RouteOption])] {
        TransportMode.allCases.compactMap { mode in
            let matching = sorted(options.filter { $0.mode == mode })
            return matching.isEmpty ? nil : (mode, matching)
        }
    }

    private static func modeOrder(_ mode: TransportMode) -> Int {
        switch mode {
        case .transit: return 0
        case .walking: return 1
        case .driving: return 2
        }
    }
}
