import Foundation

/// 経路の分割。RoutePlanner 本体から切り出してあるが、役割は続きもの。
///
/// 「徒歩が長いなら公共交通に置き換えられないか」を再帰で試し、
/// 置き換えた結果が本当に速くなったときだけ採用する。
extension RoutePlanner {
    /// 長い徒歩区間を公共交通へ置き換えられないか試す（再帰）。
    ///
    /// 公共交通の区間は分割しない。区間を分けて別々に検索すると待ち時間が積み上がり、
    /// 直通で検索した場合より遅い行程になってしまうため
    /// （実測: 萱島→淀屋橋が直通 26 分に対し、途中駅で割ると 29 分になった）。
    /// ユーザーが指定した地点だけを固定し、その間は最速の経路を 1 回で検索する。
    public func refine(_ plan: RoutePlan, depth: Int) async throws -> RoutePlan {
        guard depth > 0 else { return plan }

        if let split = try await refiningWalking(plan) {
            return try await refine(split, depth: depth - 1)
        }
        if let split = try await refiningTransit(plan) {
            return try await refine(split, depth: depth - 1)
        }
        return plan
    }

    /// 公共交通区間の内側にある乗換地点を推定して割る。
    ///
    /// MapKit の ETA は合計しか返さないため、中身は見えない。中継地点 M を挟んで
    /// 前後を実際に検索し、**待ち時間まで含めた合計が直通より遅くならない場合だけ**割る。
    ///
    /// 直通の電車に乗ったままなら、途中駅で区切って検索すると次の便を待つ扱いになり、
    /// 必ず遅くなる。その場合は割らずに直通のまま残す
    /// （実測: 萱島→淀屋橋は直通 26 分に対し、途中駅で割ると 29 分になった）。
    func refiningTransit(_ plan: RoutePlan) async throws -> RoutePlan? {
        for (index, segment) in plan.segments.enumerated() {
            guard !plan.isLocked(at: index) else { continue }
            guard segment.mode == .transit,
                  let leg = segment.leg,
                  leg.expectedTravelTime > policy.transitSplitThreshold else { continue }

            try Task.checkCancellation()
            guard let relay = try await findRelayStop(for: segment,
                                                      budget: leg.expectedTravelTime,
                                                      departure: leg.departureDate) else { continue }

            var result = plan
            result.insertNode(RouteNode(place: relay.place, kind: .station, isInferred: true),
                              afterSegment: index)
            result.setMode(.transit, at: index, byUser: false)
            result.setMode(.transit, at: index + 1, byUser: false)
            result.setLeg(relay.first, at: index)
            result.setLeg(relay.second, at: index + 1)
            return result
        }
        return nil
    }

    struct RelaySplit {
        let place: Place
        let first: RouteLeg
        let second: RouteLeg

        var totalTime: TimeInterval {
            first.expectedTravelTime + second.expectedTravelTime
        }
    }

    /// 中継地点の候補を実際に検索し、直通より遅くならないものだけを返す。
    func findRelayStop(for segment: RouteSegment,
                       budget: TimeInterval,
                       departure: Date?) async throws -> RelaySplit? {
        let from = segment.from.place.coordinate
        let to = segment.to.place.coordinate
        let midpoint = Coordinate(latitude: (from.latitude + to.latitude) / 2,
                                  longitude: (from.longitude + to.longitude) / 2)

        let candidates = await candidates(near: midpoint)
            .filter { RoutePlanBuilder.shouldInsert(station: $0, near: segment.from.place) }
            .filter { RoutePlanBuilder.shouldInsert(station: $0, near: segment.to.place) }
            .prefix(policy.maxProbesPerSegment)

        for candidate in candidates {
            try Task.checkCancellation()
            guard let first = try? await routing.leg(from: segment.from.place, to: candidate,
                                                     mode: .transit,
                                                     timePreference: departure == nil ? .now : .departAt,
                                                     requestedDate: departure) else { continue }
            // 2 本目は「1 本目に着いた時刻から」で検索する。待ち時間もここに現れる。
            let connection = first.arrivalDate
            guard let second = try? await routing.leg(from: candidate, to: segment.to.place,
                                                      mode: .transit,
                                                      timePreference: connection == nil ? .now : .departAt,
                                                      requestedDate: connection) else { continue }

            let combined = actualDuration(first: first, second: second, departure: departure)
            // 少しでも遅くなるなら割らない。
            guard combined <= budget else { continue }
            return RelaySplit(place: candidate, first: first, second: second)
        }
        return nil
    }

    /// 分割後の実際の所要時間。待ち時間を含めるため、着時刻の差で測る。
    private func actualDuration(first: RouteLeg, second: RouteLeg, departure: Date?) -> TimeInterval {
        if let start = departure ?? first.departureDate, let end = second.arrivalDate {
            return end.timeIntervalSince(start)
        }
        return first.expectedTravelTime + second.expectedTravelTime
    }

    /// 長い徒歩区間を、公共交通を使う形へ置き換えられないか試す。
    func refiningWalking(_ plan: RoutePlan) async throws -> RoutePlan? {
        for (index, segment) in plan.segments.enumerated() {
            guard !plan.isLocked(at: index) else { continue }
            guard segment.mode == .walking,
                  let leg = segment.leg,
                  leg.expectedTravelTime > policy.walkingSplitThreshold else { continue }

            try Task.checkCancellation()
            guard let replacement = try await split(segment: segment,
                                                    timePreference: plan.timePreference,
                                                    requestedDate: plan.requestedDate) else { continue }

            // 置き換えて速くなる場合だけ採用する。
            guard leg.expectedTravelTime - replacement.totalTime >= policy.minimumImprovement else { continue }

            // 添字がずれるので、1 区間ずつ確定させて組み直す。
            return apply(replacement, to: plan, at: index)
        }
        return nil
    }

    // MARK: - 分割の実体

    struct SegmentSplit {
        let boardingStop: Place
        let alightingStop: Place
        let walkToStop: RouteLeg
        let ride: RouteLeg
        let walkFromStop: RouteLeg

        var totalTime: TimeInterval {
            walkToStop.expectedTravelTime + ride.expectedTravelTime + walkFromStop.expectedTravelTime
        }
    }

    /// 徒歩区間を 徒歩 → 公共交通 → 徒歩 に割れるか試す。
    func split(segment: RouteSegment,
               timePreference: TimePreference,
               requestedDate: Date?) async throws -> SegmentSplit? {
        let from = segment.from.place.coordinate
        let to = segment.to.place.coordinate
        let distance = from.distance(to: to)
        let preferTrain = distance > policy.preferTrainOverMeters

        async let boardingCandidates = candidates(near: from)
        async let alightingCandidates = candidates(near: to)

        // 区間の端そのものに当たる停留所は、挟んでも区間が分かれないので候補から外す。
        let boardingOptions = (await boardingCandidates)
            .filter { RoutePlanBuilder.shouldInsert(station: $0, near: segment.from.place) }
        let alightingOptions = (await alightingCandidates)
            .filter { RoutePlanBuilder.shouldInsert(station: $0, near: segment.to.place) }

        guard let boarding = TransitStopClassifier.preferred(from: boardingOptions,
                                                             near: from,
                                                             preferTrain: preferTrain),
              let alighting = TransitStopClassifier.preferred(from: alightingOptions,
                                                              near: to,
                                                              preferTrain: preferTrain),
              boarding.id != alighting.id else { return nil }

        do {
            let walkToStop = try await routing.leg(from: segment.from.place, to: boarding,
                                                   mode: .walking,
                                                   timePreference: timePreference,
                                                   requestedDate: requestedDate)
            let ride = try await routing.leg(from: boarding, to: alighting,
                                             mode: .transit,
                                             timePreference: timePreference,
                                             requestedDate: requestedDate)
            let walkFromStop = try await routing.leg(from: alighting, to: segment.to.place,
                                                     mode: .walking,
                                                     timePreference: timePreference,
                                                     requestedDate: requestedDate)
            return SegmentSplit(boardingStop: boarding,
                                alightingStop: alighting,
                                walkToStop: walkToStop,
                                ride: ride,
                                walkFromStop: walkFromStop)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // 区間が取れなければ分割しない（元の徒歩のまま残る）。
            return nil
        }
    }

    /// 分割結果をプランへ差し込む。
    func apply(_ split: SegmentSplit, to plan: RoutePlan, at index: Int) -> RoutePlan {
        var result = plan
        result.insertNode(RouteNode(place: split.boardingStop, kind: .station, isInferred: true),
                          afterSegment: index)
        result.insertNode(RouteNode(place: split.alightingStop, kind: .station, isInferred: true),
                          afterSegment: index + 1)
        result.setMode(.walking, at: index, byUser: false)
        result.setMode(.transit, at: index + 1, byUser: false)
        result.setMode(.walking, at: index + 2, byUser: false)
        result.setLeg(split.walkToStop, at: index)
        result.setLeg(split.ride, at: index + 1)
        result.setLeg(split.walkFromStop, at: index + 2)
        return result
    }

    func candidates(near coordinate: Coordinate) async -> [Place] {
        (try? await stops.stops(near: coordinate, within: policy.stopSearchRadius, limit: 10)) ?? []
    }
}
