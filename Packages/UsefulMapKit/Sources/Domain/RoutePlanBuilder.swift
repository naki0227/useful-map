import Foundation

/// プランの組み立てポリシー。
///
/// 公共交通で行くとき、実際の移動は「出発地 →徒歩→ 乗車駅 →電車→ 降車駅 →徒歩→ 目的地」になる。
/// MapKit はこの区切りを返さないため、最寄駅を推定して差し込む。
/// 地点そのものが駅の場合は徒歩区間を作らない。
public enum RoutePlanBuilder {
    /// 出発地・目的地が駅とみなせる距離（これ以内なら徒歩区間を挟まない）。
    public static let stationProximityMeters: Double = 150

    /// 乗降地点を探す範囲。
    /// 「最寄りが遠い」ケースを拾うために広めに取る。
    /// 遠い結果として徒歩が長くなった場合は、RoutePlanner が再帰的に分割する。
    public static let stationSearchRadiusMeters: Double = 5_000

    /// 素朴な 2 点プランを作る。
    public static func plan(origin: RouteNode,
                            destination: RouteNode,
                            mode: TransportMode,
                            timePreference: TimePreference = .now,
                            requestedDate: Date? = nil) -> RoutePlan {
        RoutePlan.simple(origin: origin,
                         destination: destination,
                         mode: mode,
                         timePreference: timePreference,
                         requestedDate: requestedDate)
    }

    /// 公共交通プランへ駅ノードを差し込む。
    ///
    /// - Parameters:
    ///   - originStation: 出発地側の最寄駅（無ければ nil）
    ///   - destinationStation: 目的地側の最寄駅（無ければ nil）
    /// - Returns: 徒歩と電車に分かれたプラン。駅が取れなければ元のプランのまま。
    public static func insertingStations(into plan: RoutePlan,
                                         originStation: Place?,
                                         destinationStation: Place?) -> RoutePlan {
        guard plan.nodes.count == 2, plan.modes.first == .transit else { return plan }

        var nodes = [plan.origin]
        var modes: [TransportMode] = []

        if let originStation, shouldInsert(station: originStation, near: plan.origin.place) {
            nodes.append(RouteNode(place: originStation, kind: .station, isInferred: true))
            modes.append(.walking)
        }

        // 降車地点は、乗車地点と別の場所であるときだけ意味がある。
        if let destinationStation,
           shouldInsert(station: destinationStation, near: plan.destination.place),
           nodes.last?.place.id != destinationStation.id {
            nodes.append(RouteNode(place: destinationStation, kind: .station, isInferred: true))
            modes.append(.transit)
            modes.append(.walking)
        } else {
            // 降車地点を置かない場合は、そこから目的地まで公共交通で直行する。
            modes.append(.transit)
        }

        nodes.append(plan.destination)

        return RoutePlan(nodes: nodes,
                         modes: modes,
                         timePreference: plan.timePreference,
                         requestedDate: plan.requestedDate)
    }

    /// 地点が既に駅とみなせるなら、徒歩区間を作らない。
    static func shouldInsert(station: Place, near place: Place) -> Bool {
        guard station.id != place.id else { return false }
        return station.coordinate.distance(to: place.coordinate) > stationProximityMeters
    }
}
