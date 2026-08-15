import Foundation

/// 分割の方針。
public struct RouteRefinementPolicy: Sendable {
    /// 徒歩がこの時間を超えたら、公共交通で置き換えられないか試す。
    public var walkingSplitThreshold: TimeInterval
    /// 置き換えでこれ以上短くならなければ採用しない（歩いた方が早いなら歩く）。
    public var minimumImprovement: TimeInterval
    /// 乗降地点を探す半径。
    public var stopSearchRadius: Double
    /// 再帰の深さ。徒歩 → バス → さらに徒歩 … と際限なく割らないための上限。
    public var maxDepth: Int
    /// この距離を超える区間は鉄道を優先し、それ未満はバス停でも許容する。
    public var preferTrainOverMeters: Double
    /// 公共交通区間がこの時間を超えたら、中の乗換地点を探して割ってみる。
    public var transitSplitThreshold: TimeInterval
    /// 1 区間あたりに試す中継地点の数（MapKit のリクエスト制限があるため絞る）。
    public var maxProbesPerSegment: Int
    /// ユーザーが選んだ便を選び直すときに、出発時刻をずらして試す回数。
    public var maxDepartureProbes: Int
    /// ずらす幅。
    public var departureProbeStep: TimeInterval
    /// 「同じ経路」とみなす所要時間の許容差。
    public var durationTolerance: DurationTolerance

    public init(walkingSplitThreshold: TimeInterval = 15 * 60,
                minimumImprovement: TimeInterval = 3 * 60,
                stopSearchRadius: Double = RoutePlanBuilder.stationSearchRadiusMeters,
                maxDepth: Int = 2,
                preferTrainOverMeters: Double = 3_000,
                transitSplitThreshold: TimeInterval = 10 * 60,
                maxProbesPerSegment: Int = 3,
                maxDepartureProbes: Int = 4,
                departureProbeStep: TimeInterval = 10 * 60,
                durationTolerance: DurationTolerance = .default) {
        self.walkingSplitThreshold = walkingSplitThreshold
        self.minimumImprovement = minimumImprovement
        self.stopSearchRadius = stopSearchRadius
        self.maxDepth = maxDepth
        self.preferTrainOverMeters = preferTrainOverMeters
        self.transitSplitThreshold = transitSplitThreshold
        self.maxProbesPerSegment = maxProbesPerSegment
        self.maxDepartureProbes = maxDepartureProbes
        self.departureProbeStep = departureProbeStep
        self.durationTolerance = durationTolerance
    }

    public static let `default` = RouteRefinementPolicy()
}

/// プランの組み立てと、徒歩区間の再帰的な分割。
///
/// MapKit は公共交通について合計所要時間しか返さないため、
/// 「どこで乗ってどこで降りるか」はアプリ側で組み立てる。
///
///   1. 出発地 → 目的地 を 1 区間として置く
///   2. 公共交通なら、両端の最寄り乗降地点を挟んで 徒歩 / 公共交通 / 徒歩 に割る
///   3. 残った徒歩区間が長ければ、その区間の中でさらに乗降地点を探して割る（再帰）
///   4. 割った方が遅くなる場合は割らない
///
/// 3 が「最寄駅が遠いならバス停まで歩いてバスに乗る」に相当する。
/// ただし MapKit は駅とバス停を区別しないため、どちらも「公共交通」として計算される。
public struct RoutePlanner: Sendable {
    // 分割の実装は RoutePlanner+Splitting.swift にあるため、モジュール内には見せる。
    let stops: TransitStopLocating
    let routing: SegmentRouting
    let policy: RouteRefinementPolicy
    /// 徒歩の速さ。MapKit の所要時間に倍率を掛けて補正する。
    public let walkingPace: WalkingPace
    let now: @Sendable () -> Date

    public init(stops: TransitStopLocating,
                routing: SegmentRouting,
                policy: RouteRefinementPolicy = .default,
                walkingPace: WalkingPace = .normal,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.stops = stops
        self.routing = routing
        self.policy = policy
        self.walkingPace = walkingPace
        self.now = now
    }

    /// 徒歩ペースだけ差し替えた別の Planner を作る。
    public func withWalkingPace(_ pace: WalkingPace) -> RoutePlanner {
        RoutePlanner(stops: stops, routing: routing, policy: policy, walkingPace: pace, now: now)
    }

    /// 出発地と目的地からプランを作り、区間を計算し、必要なら再帰的に分割する。
    public func makePlan(origin: RouteNode,
                         destination: RouteNode,
                         preset: TransportMode,
                         timePreference: TimePreference = .now,
                         requestedDate: Date? = nil) async throws -> RoutePlan {
        var plan = RoutePlan.simple(origin: origin,
                                    destination: destination,
                                    mode: preset,
                                    timePreference: timePreference,
                                    requestedDate: requestedDate)

        if preset == .transit {
            plan = await insertingStops(into: plan)
        }
        plan = try await computeLegs(plan)
        if preset == .transit {
            plan = try await refine(plan, depth: policy.maxDepth)
        }
        return plan
    }

    /// 未計算の区間を埋める。1 区間でも失敗したらその区間だけ空のままにする。
    ///
    /// 便を固定している区間がある場合は、そこを基準に前の区間は「到着時刻指定」、
    /// 後の区間は「出発時刻指定」で取り直す。
    public func computeLegs(_ plan: RoutePlan) async throws -> RoutePlan {
        var result = plan
        // 前の区間に着いた時刻。次の区間はその時刻から出発する条件で問い合わせる。
        // これをしないと全区間が「今から出発」で検索され、
        // 実際には間に合わない便が表示されてしまう。
        var cursor: Date? = plan.timePreference == .arriveBy
            ? nil
            : (plan.requestedDate ?? now())

        for (index, segment) in plan.segments.enumerated() {
            guard segment.leg == nil else {
                cursor = advanced(cursor, by: segment.leg)
                continue
            }
            try Task.checkCancellation()
            var condition = timeCondition(for: plan, at: index)
            if plan.pinnedSegmentIndex == nil, index > 0, let cursor {
                condition = (.departAt, cursor)
            }
            var leg = try? await routing.leg(from: segment.from.place,
                                             to: segment.to.place,
                                             mode: segment.mode,
                                             timePreference: condition.preference,
                                             requestedDate: condition.date)

            // ユーザーが選んだ便がある区間は、同じ所要時間になる便を選び直す。
            if let lock = plan.lock(at: index), lock.duration != nil, segment.mode == .transit {
                let matched = try await matchingLeg(for: segment,
                                                    lock: lock,
                                                    fallback: leg,
                                                    condition: condition)
                if let matched,
                   lock.matchesDuration(matched.expectedTravelTime, tolerance: policy.durationTolerance) {
                    // 同じ経路を取り戻せた。
                    leg = matched
                } else if let chosen = lock.leg {
                    // 取り戻せなかった。選んだ内容は残したまま、差分として提示する。
                    result.setLeg(walkingPace.adjusted(chosen, mode: segment.mode), at: index)
                    if let matched {
                        result.proposeUpdate(walkingPace.adjusted(matched, mode: segment.mode), at: index)
                    }
                    continue
                } else {
                    leg = matched
                }
            }
            let adjusted = leg.map { walkingPace.adjusted($0, mode: segment.mode) }
            result.setLeg(adjusted, at: index)
            cursor = advanced(cursor, by: adjusted)
        }
        return result
    }

    /// 区間を終えた時刻へ進める。時刻が返らない区間（徒歩）は所要時間で足す。
    private func advanced(_ cursor: Date?, by leg: RouteLeg?) -> Date? {
        guard let leg else { return nil }
        if let arrival = leg.arrivalDate { return arrival }
        return cursor?.addingTimeInterval(leg.expectedTravelTime)
    }

    /// ユーザーが選んだ所要時間に一致する便を探す。
    ///
    /// MapKit は路線名を返さないため「同じ経路か」は直接判定できない。
    /// ただし経路が同じなら所要時間はほぼ変わらないので、これを指紋として使う。
    /// 出発時刻を少しずつずらして問い合わせ、記録した所要時間に最も近いものを採用する。
    /// 見つからなければ素直に最新の結果を返す（勝手に古い値を表示しない）。
    func matchingLeg(for segment: RouteSegment,
                     lock: SegmentLock,
                     fallback: RouteLeg?,
                     condition: (preference: TimePreference, date: Date?)) async throws -> RouteLeg? {
        guard let target = lock.duration else { return fallback }
        if let fallback, lock.matchesDuration(fallback.expectedTravelTime, tolerance: policy.durationTolerance) {
            return fallback
        }

        let base = lock.timeAnchor?.date ?? condition.date
        guard let base else { return fallback }

        var best = fallback
        var bestGap = fallback.map { abs($0.expectedTravelTime - target) } ?? .greatestFiniteMagnitude

        for step in 1...max(1, policy.maxDepartureProbes) {
            try Task.checkCancellation()
            let shifted = base.addingTimeInterval(Double(step) * policy.departureProbeStep)
            guard let candidate = try? await routing.leg(from: segment.from.place,
                                                         to: segment.to.place,
                                                         mode: segment.mode,
                                                         timePreference: .departAt,
                                                         requestedDate: shifted) else { continue }
            let gap = abs(candidate.expectedTravelTime - target)
            if gap < bestGap {
                best = candidate
                bestGap = gap
            }
            if lock.matchesDuration(candidate.expectedTravelTime, tolerance: policy.durationTolerance) {
                return candidate
            }
        }
        return best
    }

    /// 区間ごとの時刻条件。固定した便がある場合はそれを基準にする。
    func timeCondition(for plan: RoutePlan,
                       at index: Int) -> (preference: TimePreference, date: Date?) {
        guard let pinnedIndex = plan.pinnedSegmentIndex, let anchor = plan.pinnedTime else {
            return (plan.timePreference, plan.requestedDate)
        }
        if index == pinnedIndex {
            return (anchor.kind == .arrive ? .arriveBy : .departAt, anchor.date)
        }
        // 固定した便より前は「その時刻までに着く」、後は「その時刻から出発する」。
        let schedule = plan.schedule()
        if index < pinnedIndex {
            let target = schedule[safe: index]??.arrival ?? anchor.date
            return (.arriveBy, target)
        }
        let target = schedule[safe: index]??.departure ?? anchor.date
        return (.departAt, target)
    }

    /// 便を固定して、前後の区間を取り直す。
    public func applyPin(_ anchor: TimeAnchor, at index: Int, to plan: RoutePlan) async throws -> RoutePlan {
        var result = plan
        result.pinTime(anchor, at: index)
        return try await computeLegs(result)
    }

    /// 両端に乗降地点を挟む。
    func insertingStops(into plan: RoutePlan) async -> RoutePlan {
        let distance = plan.origin.place.coordinate.distance(to: plan.destination.place.coordinate)
        let preferTrain = distance > policy.preferTrainOverMeters

        async let originCandidates = candidates(near: plan.origin.place.coordinate)
        async let destinationCandidates = candidates(near: plan.destination.place.coordinate)

        let originStop = TransitStopClassifier.preferred(from: await originCandidates,
                                                         near: plan.origin.place.coordinate,
                                                         preferTrain: preferTrain)
        let destinationStop = TransitStopClassifier.preferred(from: await destinationCandidates,
                                                              near: plan.destination.place.coordinate,
                                                              preferTrain: preferTrain)
        return RoutePlanBuilder.insertingStations(into: plan,
                                                  originStation: originStop,
                                                  destinationStation: destinationStop)
    }

}
