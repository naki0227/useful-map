import Foundation
import Testing

@testable import Domain

// MARK: - テストダブル

/// 座標の近くにある停留所を、テストが指定した表から返す。
final class FakeStopLocator: TransitStopLocating, @unchecked Sendable {
    /// 「この座標の近くにはこれらがある」という定義。
    var table: [(center: Coordinate, stops: [Place])] = []
    private(set) var queries: [Coordinate] = []

    func stops(near coordinate: Coordinate, within meters: Double, limit: Int) async throws -> [Place] {
        queries.append(coordinate)
        let matched = table
            .filter { $0.center.distance(to: coordinate) <= meters }
            .flatMap(\.stops)
            .filter { $0.coordinate.distance(to: coordinate) <= meters }
        return Array(matched.prefix(limit))
    }
}

/// 区間ごとの所要時間をテストが指定する。
final class FakeSegmentRouting: SegmentRouting, @unchecked Sendable {
    /// "出発地名->目的地名#モード" → 所要時間（秒）
    var times: [String: TimeInterval] = [:]
    /// "出発地名->目的地名#モード@出発時刻" → 所要時間（秒）。便ごとの違いを表す。
    var timesByDate: [String: TimeInterval] = [:]
    /// 既定値（未指定の区間）。nil なら失敗させる。
    var defaultWalkingSpeed: Double? = 1.2  // m/s
    var transitSpeed: Double = 12.0         // m/s
    private(set) var requests: [String] = []

    func leg(from: Place,
             to: Place,
             mode: TransportMode,
             timePreference: TimePreference,
             requestedDate: Date?) async throws -> RouteLeg {
        let key = "\(from.name)->\(to.name)#\(mode.rawValue)"
        requests.append(key)
        let distance = from.coordinate.distance(to: to.coordinate)

        if let requestedDate, let time = timesByDate["\(key)@\(requestedDate.timeIntervalSince1970)"] {
            return RouteLeg(expectedTravelTime: time,
                            departureDate: requestedDate,
                            arrivalDate: requestedDate.addingTimeInterval(time),
                            distance: distance)
        }
        if let time = times[key] {
            return RouteLeg(expectedTravelTime: time, distance: distance)
        }
        switch mode {
        case .walking:
            guard let speed = defaultWalkingSpeed else { throw RouteError.noRoutesFound }
            return RouteLeg(expectedTravelTime: distance / speed, distance: distance)
        case .transit:
            return RouteLeg(expectedTravelTime: distance / transitSpeed,
                            departureDate: Date(timeIntervalSince1970: 0),
                            arrivalDate: Date(timeIntervalSince1970: distance / transitSpeed),
                            distance: distance)
        case .driving:
            return RouteLeg(expectedTravelTime: distance / 8.0, distance: distance)
        }
    }
}

// MARK: - テスト

@Suite("RoutePlanner")
struct RoutePlannerTests {
    // 緯度 0.001 度 ≒ 111m。距離が判定に効くので、意図が読めるように並べる。
    private let home = Place(name: "自宅", latitude: 34.7500, longitude: 135.5000)
    /// 自宅から約 3.3km。徒歩だと 45 分以上かかるので分割の対象になる。
    private let umeda = Place(name: "梅田駅", latitude: 34.7200, longitude: 135.5000)
    private let kyoto = Place(name: "京都駅", latitude: 34.9858, longitude: 135.7587)
    /// 京都駅から約 1km。
    private let hotel = Place(name: "京都ホテル", latitude: 34.9950, longitude: 135.7600)
    /// 自宅から約 220m。
    private let busStop = Place(name: "自宅前バス停", latitude: 34.7480, longitude: 135.5000)
    /// 梅田駅から約 330m。
    private let umedaBusStop = Place(name: "梅田三丁目バス停", latitude: 34.7230, longitude: 135.5000)
    /// 自宅から約 800m。徒歩 11 分ほどで、分割の閾値に届かない。
    private let nearStation = Place(name: "近所の駅", latitude: 34.7428, longitude: 135.5000)
    /// 京都駅から約 3.3km 離れた目的地。降車後の徒歩が 45 分を超える。
    private let ruralInn = Place(name: "山あいの宿", latitude: 35.0158, longitude: 135.7587)
    /// 京都駅から約 330m。
    private let kyotoBusStop = Place(name: "京都駅前バス停", latitude: 34.9888, longitude: 135.7587)
    /// 宿から約 220m。
    private let innBusStop = Place(name: "宿前バス停", latitude: 35.0138, longitude: 135.7587)

    private func node(_ place: Place, _ kind: RouteNode.Kind) -> RouteNode {
        RouteNode(place: place, kind: kind)
    }

    private func makePlanner(stops: FakeStopLocator,
                             routing: FakeSegmentRouting,
                             policy: RouteRefinementPolicy = .default) -> RoutePlanner {
        RoutePlanner(stops: stops, routing: routing, policy: policy)
    }

    @Test("公共交通なら両端に乗降地点を挟んで 徒歩→公共交通→徒歩 になる")
    func insertsStopsForTransit() async throws {
        let stops = FakeStopLocator()
        stops.table = [(home.coordinate, [nearStation]), (hotel.coordinate, [kyoto])]
        let planner = makePlanner(stops: stops, routing: FakeSegmentRouting())

        let plan = try await planner.makePlan(origin: node(home, .origin),
                                              destination: node(hotel, .destination),
                                              preset: .transit)

        #expect(plan.nodes.map(\.place.name) == ["自宅", "近所の駅", "京都駅", "京都ホテル"])
        #expect(plan.modes == [.walking, .transit, .walking])
        #expect(plan.segments.allSatisfy { $0.leg != nil })
    }

    @Test("徒歩プリセットでは乗降地点を挟まない")
    func doesNotInsertStopsForWalking() async throws {
        let stops = FakeStopLocator()
        stops.table = [(home.coordinate, [umeda])]
        let planner = makePlanner(stops: stops, routing: FakeSegmentRouting())

        let plan = try await planner.makePlan(origin: node(home, .origin),
                                              destination: node(hotel, .destination),
                                              preset: .walking)

        #expect(plan.nodes.count == 2)
        #expect(plan.modes == [.walking])
        #expect(stops.queries.isEmpty, "停留所検索も走らせない")
    }

    @Test("停留所が見つからなくてもプランは成立する")
    func survivesWithoutStops() async throws {
        let planner = makePlanner(stops: FakeStopLocator(), routing: FakeSegmentRouting())

        let plan = try await planner.makePlan(origin: node(home, .origin),
                                              destination: node(hotel, .destination),
                                              preset: .transit)

        #expect(plan.nodes.count == 2)
        #expect(plan.segments[0].leg != nil)
    }

    @Test("長い徒歩区間はバス停を挟んで分割される（駅を手で選び直した後など）")
    func splitsLongWalk() async throws {
        // ユーザーが乗車駅を 3.3km 先の梅田駅に指定した状況。
        // 自宅の近くと梅田駅の近くにバス停があるので、そこを使えば速くなる。
        let stops = FakeStopLocator()
        stops.table = [(home.coordinate, [busStop, umeda]),
                       (umeda.coordinate, [umeda, umedaBusStop])]
        let planner = makePlanner(stops: stops, routing: FakeSegmentRouting())

        var plan = RoutePlan(nodes: [node(home, .origin),
                                     node(umeda, .station),
                                     node(kyoto, .station),
                                     node(hotel, .destination)],
                             modes: [.walking, .transit, .walking])
        plan = try await planner.computeLegs(plan)
        #expect(plan.segments[0].leg?.expectedTravelTime ?? 0 > 15 * 60, "前提: 徒歩が長いこと")

        let refined = try await planner.refine(plan, depth: 2)

        #expect(refined.nodes.map(\.place.name)
                == ["自宅", "自宅前バス停", "梅田三丁目バス停", "梅田駅", "京都駅", "京都ホテル"])
        #expect(refined.modes == [.walking, .transit, .walking, .transit, .walking])
        // 徒歩と公共交通が交互に並び、徒歩が連続しない。
        for (index, mode) in refined.modes.enumerated() where index > 0 {
            #expect(!(refined.modes[index - 1] == .walking && mode == .walking), "徒歩が連続している")
        }
    }

    @Test("分割しても速くならないなら徒歩のまま残す")
    func keepsWalkingWhenSplitIsSlower() async throws {
        let stops = FakeStopLocator()
        stops.table = [(home.coordinate, [busStop, umeda]),
                       (umeda.coordinate, [umeda, umedaBusStop])]
        let routing = FakeSegmentRouting()
        // 歩けば 45 分。バスは本数が少なく、待ち時間込みで 70 分かかる想定にする。
        routing.times["自宅->梅田駅#walking"] = 45 * 60
        routing.times["自宅->自宅前バス停#walking"] = 5 * 60
        routing.times["自宅前バス停->梅田三丁目バス停#transit"] = 60 * 60
        routing.times["梅田三丁目バス停->梅田駅#walking"] = 5 * 60

        let planner = makePlanner(stops: stops, routing: routing)
        var plan = RoutePlan(nodes: [node(home, .origin),
                                     node(umeda, .station),
                                     node(kyoto, .station),
                                     node(hotel, .destination)],
                             modes: [.walking, .transit, .walking])
        plan = try await planner.computeLegs(plan)

        let refined = try await planner.refine(plan, depth: 2)

        #expect(!refined.nodes.map(\.place.name).contains("自宅前バス停"))
    }

    @Test("駅が遠くても、近くにバス停があればそちらを乗車地点にする")
    func prefersNearestStopEvenIfNotTrain() async throws {
        let stops = FakeStopLocator()
        // 自宅の近くにはバス停（220m）、遠くに駅（3.3km）。
        stops.table = [(home.coordinate, [umeda, busStop]), (hotel.coordinate, [kyoto])]
        let planner = makePlanner(stops: stops, routing: FakeSegmentRouting())

        let plan = try await planner.makePlan(origin: node(home, .origin),
                                              destination: node(hotel, .destination),
                                              preset: .transit)

        #expect(plan.nodes[1].place.name == "自宅前バス停")
    }

    @Test("短い徒歩区間は分割しない")
    func doesNotSplitShortWalk() async throws {
        let stops = FakeStopLocator()
        stops.table = [(home.coordinate, [nearStation]), (hotel.coordinate, [kyoto])]
        let routing = FakeSegmentRouting()
        let planner = makePlanner(stops: stops, routing: routing)

        let plan = try await planner.makePlan(origin: node(home, .origin),
                                              destination: node(hotel, .destination),
                                              preset: .transit)

        #expect(plan.nodes.map(\.place.name) == ["自宅", "近所の駅", "京都駅", "京都ホテル"])
    }

    @Test("再帰の深さは上限で止まる")
    func respectsMaxDepth() async throws {
        let stops = FakeStopLocator()
        // どこにでも停留所がある状況（際限なく割れてしまう）。
        let everywhere = (0..<12).map { index in
            Place(name: "停留所\(index)",
                  latitude: 34.7500 - Double(index) * 0.004,
                  longitude: 135.5000)
        }
        stops.table = [(home.coordinate, everywhere + [umeda]),
                       (hotel.coordinate, [kyoto])]
            + everywhere.map { ($0.coordinate, everywhere) }
        let planner = makePlanner(stops: stops,
                                  routing: FakeSegmentRouting(),
                                  policy: RouteRefinementPolicy(maxDepth: 1))

        let plan = try await planner.makePlan(origin: node(home, .origin),
                                              destination: node(hotel, .destination),
                                              preset: .transit)

        // 初期 3 区間 + 分割 1 回（+2 区間）= 最大 5 区間。
        #expect(plan.modes.count <= 5)
    }

    @Test("区間の取得に失敗しても、その区間だけ空になり他は残る")
    func toleratesPartialFailure() async throws {
        let stops = FakeStopLocator()
        stops.table = [(home.coordinate, [umeda]), (hotel.coordinate, [kyoto])]
        let routing = FakeSegmentRouting()
        routing.defaultWalkingSpeed = nil  // 徒歩区間を失敗させる

        let planner = makePlanner(stops: stops, routing: routing)
        let plan = try await planner.makePlan(origin: node(home, .origin),
                                              destination: node(hotel, .destination),
                                              preset: .transit)

        #expect(plan.segments.contains { $0.leg == nil })
        #expect(plan.segments.contains { $0.leg != nil })
        #expect(plan.totalTravelTime == nil, "欠けたまま合計は出さない")
    }

    @Test("長距離では鉄道を優先し、短距離ではバス停も使う")
    func prefersTrainForLongTrips() {
        let stationAndBus = [Place(name: "○○バス停", latitude: 34.7495, longitude: 135.5000),
                             Place(name: "○○駅", latitude: 34.7480, longitude: 135.5000)]

        let long = TransitStopClassifier.preferred(from: stationAndBus,
                                                   near: home.coordinate,
                                                   preferTrain: true)
        #expect(long?.name == "○○駅")

        let short = TransitStopClassifier.preferred(from: stationAndBus,
                                                    near: home.coordinate,
                                                    preferTrain: false)
        #expect(short?.name == "○○バス停", "近い順ならバス停が先")
    }
}

@Suite("乗降地点の種別推定")
struct TransitStopClassifierTests {
    @Test("名称から駅とバス停を見分ける", arguments: [
        ("東京駅", TransitStopKind.train),
        ("Osaka Station", TransitStopKind.train),
        ("서울역", TransitStopKind.train),
        ("梅田三丁目バス停", TransitStopKind.bus),
        ("市役所前停留所", TransitStopKind.bus),
        ("Shibuya Bus Stop", TransitStopKind.bus),
        ("なにかの乗り場", TransitStopKind.unknown)
    ])
    func classification(name: String, expected: TransitStopKind) {
        let place = Place(name: name, latitude: 35.0, longitude: 135.0)
        #expect(TransitStopClassifier.kind(of: place) == expected)
    }

    @Test("種別ごとにアイコンを持つ")
    func symbols() {
        for kind in TransitStopKind.allCases {
            #expect(!kind.symbolName.isEmpty)
        }
    }
}

@Suite("徒歩ペースと便の固定")
struct WalkingPaceAndPinTests {
    private let home = Place(name: "自宅", latitude: 34.7500, longitude: 135.5000)
    private let station = Place(name: "近所の駅", latitude: 34.7428, longitude: 135.5000)
    private let kyoto = Place(name: "京都駅", latitude: 34.9858, longitude: 135.7587)
    private let hotel = Place(name: "京都ホテル", latitude: 34.9950, longitude: 135.7600)

    private func node(_ place: Place, _ kind: RouteNode.Kind) -> RouteNode {
        RouteNode(place: place, kind: kind)
    }

    private func threeSegmentPlan() -> RoutePlan {
        RoutePlan(nodes: [node(home, .origin), node(station, .station),
                          node(kyoto, .station), node(hotel, .destination)],
                  modes: [.walking, .transit, .walking])
    }

    @Test("ペースは徒歩区間だけに掛かる")
    func paceAffectsWalkingOnly() {
        let walk = RouteLeg(expectedTravelTime: 600)
        let ride = RouteLeg(expectedTravelTime: 600)

        #expect(WalkingPace.slow.adjusted(walk, mode: .walking).expectedTravelTime == 750)
        #expect(WalkingPace.fast.adjusted(walk, mode: .walking).expectedTravelTime == 480)
        #expect(WalkingPace.normal.adjusted(walk, mode: .walking).expectedTravelTime == 600)
        #expect(WalkingPace.slow.adjusted(ride, mode: .transit).expectedTravelTime == 600)
    }

    @Test("ペースを変えると徒歩区間の所要時間が変わる")
    func paceChangesPlanTotals() async throws {
        let stops = FakeStopLocator()
        let routing = FakeSegmentRouting()
        let normal = RoutePlanner(stops: stops, routing: routing)
        let slow = normal.withWalkingPace(.slow)

        let normalPlan = try await normal.computeLegs(threeSegmentPlan())
        let slowPlan = try await slow.computeLegs(threeSegmentPlan())

        let normalWalk = try #require(normalPlan.segments[0].leg?.expectedTravelTime)
        let slowWalk = try #require(slowPlan.segments[0].leg?.expectedTravelTime)
        #expect(slowWalk > normalWalk)
        #expect(abs(slowWalk - normalWalk * 1.25) < 0.001)

        // 公共交通区間は変わらない。
        #expect(normalPlan.segments[1].leg?.expectedTravelTime
                == slowPlan.segments[1].leg?.expectedTravelTime)
    }

    @Test("ボタン 1 つで 普通 → 速い → 遅い → 普通 と切り替わる")
    func paceCycles() {
        #expect(WalkingPace.normal.next == .fast)
        #expect(WalkingPace.fast.next == .slow)
        #expect(WalkingPace.slow.next == .normal)
        #expect(WalkingPace.allCases.allSatisfy { !$0.symbolName.isEmpty })
    }

    @Test("便を固定すると、その区間だけ結果が残り前後は取り直しになる")
    func pinningInvalidatesNeighbours() async throws {
        var plan = try await RoutePlanner(stops: FakeStopLocator(),
                                          routing: FakeSegmentRouting()).computeLegs(threeSegmentPlan())
        #expect(plan.segments.allSatisfy { $0.leg != nil })

        plan.pinTime(TimeAnchor(kind: .depart, date: TestDates.make(2026, 8, 15, 10, 0)), at: 1)

        #expect(plan.segments[1].leg != nil, "固定した区間は残す")
        #expect(plan.segments[0].leg == nil)
        #expect(plan.segments[2].leg == nil)
        #expect(plan.pinnedSegmentIndex == 1)
    }

    @Test("固定した便を基準に、前は到着時刻指定・後は出発時刻指定で取り直す")
    func pinDrivesNeighbourConditions() async throws {
        let routing = FakeSegmentRouting()
        let planner = RoutePlanner(stops: FakeStopLocator(), routing: routing)
        var plan = try await planner.computeLegs(threeSegmentPlan())

        let departure = TestDates.make(2026, 8, 15, 10, 0)
        plan = try await planner.applyPin(TimeAnchor(kind: .depart, date: departure), at: 1, to: plan)

        #expect(planner.timeCondition(for: plan, at: 0).preference == .arriveBy)
        #expect(planner.timeCondition(for: plan, at: 2).preference == .departAt)
        #expect(plan.segments.allSatisfy { $0.leg != nil }, "前後が取り直されている")
    }

    @Test("時刻表は固定した区間を起点に前後へ伸びる")
    func scheduleChainsAroundPin() async throws {
        let routing = FakeSegmentRouting()
        routing.times["自宅->近所の駅#walking"] = 600
        routing.times["近所の駅->京都駅#transit"] = 1_800
        routing.times["京都駅->京都ホテル#walking"] = 300
        let planner = RoutePlanner(stops: FakeStopLocator(), routing: routing)

        var plan = try await planner.computeLegs(threeSegmentPlan())
        let departure = TestDates.make(2026, 8, 15, 10, 0)
        plan.pinTime(TimeAnchor(kind: .depart, date: departure), at: 1)
        plan = try await planner.computeLegs(plan)

        let schedule = plan.schedule()
        #expect(schedule[1]?.departure == departure)
        #expect(schedule[1]?.arrival == departure.addingTimeInterval(1_800))
        // 前の徒歩は電車の出発に間に合うように逆算される。
        #expect(schedule[0]?.arrival == departure)
        #expect(schedule[0]?.departure == departure.addingTimeInterval(-600))
        // 後の徒歩は到着後から始まる。
        #expect(schedule[2]?.departure == departure.addingTimeInterval(1_800))
    }
}

@Suite("公共交通区間の内側を割る（ETA を判定器にする）")
struct TransitRelaySplitTests {
    private let stationA = Place(name: "A駅", latitude: 34.7000, longitude: 135.5000)
    private let relay = Place(name: "B駅", latitude: 34.8000, longitude: 135.6000)
    private let offRoute = Place(name: "遠回り駅", latitude: 34.7500, longitude: 136.2000)
    private let stationC = Place(name: "C駅", latitude: 34.9000, longitude: 135.7000)

    private func node(_ place: Place, _ kind: RouteNode.Kind) -> RouteNode {
        RouteNode(place: place, kind: kind)
    }

    private func plan() -> RoutePlan {
        RoutePlan(nodes: [node(stationA, .station), node(stationC, .station)], modes: [.transit])
    }

    @Test("経路上の乗換地点なら割って層を増やす")
    func splitsAtRelayOnRoute() async throws {
        let stops = FakeStopLocator()
        // A と C の中点付近に B 駅がある。
        let midpoint = Coordinate(latitude: (stationA.coordinate.latitude + stationC.coordinate.latitude) / 2,
                                  longitude: (stationA.coordinate.longitude + stationC.coordinate.longitude) / 2)
        stops.table = [(midpoint, [relay])]

        let routing = FakeSegmentRouting()
        routing.times["A駅->C駅#transit"] = 40 * 60
        routing.times["A駅->B駅#transit"] = 18 * 60
        routing.times["B駅->C駅#transit"] = 20 * 60  // 合計 38 分 ≒ 40 分

        let planner = RoutePlanner(stops: stops, routing: routing)
        var target = try await planner.computeLegs(plan())
        target = try await planner.refine(target, depth: 2)

        #expect(target.nodes.map(\.place.name) == ["A駅", "B駅", "C駅"])
        #expect(target.modes == [.transit, .transit])
        // 割った合計が元の所要時間から大きくずれない。
        let total = try #require(target.totalTravelTime)
        #expect(abs(total - 38 * 60) < 1)
    }

    @Test("経路から外れた地点では割らない（合計が大きく増えるため）")
    func doesNotSplitOffRoute() async throws {
        let stops = FakeStopLocator()
        let midpoint = Coordinate(latitude: (stationA.coordinate.latitude + stationC.coordinate.latitude) / 2,
                                  longitude: (stationA.coordinate.longitude + stationC.coordinate.longitude) / 2)
        stops.table = [(midpoint, [offRoute])]

        let routing = FakeSegmentRouting()
        routing.times["A駅->C駅#transit"] = 40 * 60
        routing.times["A駅->遠回り駅#transit"] = 50 * 60
        routing.times["遠回り駅->C駅#transit"] = 55 * 60  // 合計 105 分。明らかに経路外。

        let planner = RoutePlanner(stops: stops, routing: routing)
        var target = try await planner.computeLegs(plan())
        target = try await planner.refine(target, depth: 2)

        #expect(target.nodes.count == 2, "割らずに 1 区間のまま")
    }

    @Test("短い公共交通区間はそもそも割らない")
    func skipsShortTransit() async throws {
        let stops = FakeStopLocator()
        let midpoint = Coordinate(latitude: (stationA.coordinate.latitude + stationC.coordinate.latitude) / 2,
                                  longitude: (stationA.coordinate.longitude + stationC.coordinate.longitude) / 2)
        stops.table = [(midpoint, [relay])]

        let routing = FakeSegmentRouting()
        routing.times["A駅->C駅#transit"] = 5 * 60

        let planner = RoutePlanner(stops: stops, routing: routing)
        var target = try await planner.computeLegs(plan())
        target = try await planner.refine(target, depth: 2)

        #expect(target.nodes.count == 2)
    }

    @Test("試す中継地点の数には上限がある（リクエストを撃ちすぎない）")
    func limitsProbes() async throws {
        let stops = FakeStopLocator()
        let midpoint = Coordinate(latitude: (stationA.coordinate.latitude + stationC.coordinate.latitude) / 2,
                                  longitude: (stationA.coordinate.longitude + stationC.coordinate.longitude) / 2)
        // 中点付近に候補が 10 個ある。
        let many = (0..<10).map { index in
            Place(name: "候補\(index)",
                  latitude: midpoint.latitude + Double(index) * 0.0001,
                  longitude: midpoint.longitude)
        }
        stops.table = [(midpoint, many)]

        let routing = FakeSegmentRouting()
        routing.times["A駅->C駅#transit"] = 40 * 60
        // どの候補も経路外（大幅に増える）にして、全部試させる。
        for place in many {
            routing.times["A駅->\(place.name)#transit"] = 60 * 60
            routing.times["\(place.name)->C駅#transit"] = 60 * 60
        }

        let planner = RoutePlanner(stops: stops, routing: routing,
                                   policy: RouteRefinementPolicy(maxProbesPerSegment: 2))
        var target = try await planner.computeLegs(plan())
        target = try await planner.refine(target, depth: 1)

        let probes = routing.requests.filter { $0.contains("候補") }
        #expect(probes.count <= 4, "候補 2 件 × 前後 2 区間まで")
        #expect(target.nodes.count == 2)
    }
}

@Suite("ユーザーの指定を保つ")
struct SegmentLockTests {
    private let home = Place(name: "自宅", latitude: 34.7500, longitude: 135.5000)
    private let stationA = Place(name: "A駅", latitude: 34.7428, longitude: 135.5000)
    private let stationB = Place(name: "B駅", latitude: 34.9858, longitude: 135.7587)
    private let goal = Place(name: "目的地", latitude: 34.9950, longitude: 135.7600)

    private func node(_ place: Place, _ kind: RouteNode.Kind) -> RouteNode {
        RouteNode(place: place, kind: kind)
    }

    private func plan() -> RoutePlan {
        RoutePlan(nodes: [node(home, .origin), node(stationA, .station),
                          node(stationB, .station), node(goal, .destination)],
                  modes: [.walking, .transit, .walking])
    }

    @Test("手段を変えるとその区間は指定として記録される")
    func changingModeLocksSegment() {
        var target = plan()
        #expect(!target.isLocked(at: 2))

        target.setMode(.walking, at: 2)

        #expect(target.isLocked(at: 2))
        #expect(target.lock(at: 2)?.mode == .walking)
    }

    @Test("プリセットはユーザーが決めた区間を上書きしない")
    func presetSkipsLockedSegments() {
        var target = plan()
        // 「降りた後は歩く」とユーザーが決める。
        target.setMode(.walking, at: 2)

        target.applyPreset(.driving)

        #expect(target.modes[0] == .driving)
        #expect(target.modes[1] == .driving)
        #expect(target.modes[2] == .walking, "ユーザーの指定が残る")
    }

    @Test("出発地と目的地を入れ替えても指定は向きを変えて残る")
    func reversePreservesLocks() {
        var target = plan()
        target.setMode(.walking, at: 2)  // B駅 → 目的地 を徒歩に
        let key = SegmentKey(from: stationB.id, to: goal.id)
        #expect(target.locks[key]?.mode == .walking)

        target.reverse()

        // 反転後は 目的地 → B駅 の区間として残る。
        #expect(target.locks[key.reversed]?.mode == .walking)
        #expect(target.modes[0] == .walking)
    }

    @Test("別の場所を編集しても、指定した区間のロックは消えない")
    func editingElsewhereKeepsLock() {
        var target = plan()
        target.setMode(.walking, at: 2)

        // 出発地を変える。
        target.updatePlace(Place(name: "職場", latitude: 34.7600, longitude: 135.5100), at: 0)

        #expect(target.lock(at: 2)?.mode == .walking)
        #expect(target.modes[2] == .walking)
    }

    @Test("便を選ぶと、その時刻と所要時間が指紋として記録される")
    func pinningRecordsDurationFingerprint() async throws {
        let routing = FakeSegmentRouting()
        routing.times["A駅->B駅#transit"] = 21 * 60
        let planner = RoutePlanner(stops: FakeStopLocator(), routing: routing)

        var target = try await planner.computeLegs(plan())
        let departure = TestDates.make(2026, 8, 15, 10, 0)
        target.pinTime(TimeAnchor(kind: .depart, date: departure), at: 1)

        #expect(target.lock(at: 1)?.timeAnchor?.date == departure)
        let fingerprint = try #require(target.lock(at: 1)?.duration)
        #expect(abs(fingerprint - 21 * 60) < 1)
    }

    @Test("再取得で別の便になっても、記録した所要時間に近い便を選び直す")
    func rematchesRouteByDuration() async throws {
        let routing = FakeSegmentRouting()
        // 既定の問い合わせでは 29 分の便（ユーザーが選んだのは 21 分の便）。
        routing.times["A駅->B駅#transit"] = 29 * 60
        let planner = RoutePlanner(stops: FakeStopLocator(), routing: routing)

        var target = try await planner.computeLegs(plan())
        let departure = TestDates.make(2026, 8, 15, 10, 0)
        target.pinTime(TimeAnchor(kind: .depart, date: departure), at: 1)
        // ユーザーは 21 分の便を選んだことにする。
        target.setLeg(RouteLeg(expectedTravelTime: 21 * 60), at: 1)
        target.pinTime(TimeAnchor(kind: .depart, date: departure), at: 1)

        // 出発を 10 分ずらすと 21 分の便が見つかる状況にする。
        let shifted = departure.addingTimeInterval(10 * 60)
        routing.timesByDate["A駅->B駅#transit@\(shifted.timeIntervalSince1970)"] = 21 * 60

        // 徒歩ペース変更など、別の理由で全区間を取り直す状況を作る。
        target.clearLegs()
        let recomputed = try await planner.computeLegs(target)

        let leg = try #require(recomputed.segments[1].leg)
        #expect(abs(leg.expectedTravelTime - 21 * 60) < 60, "同じ所要時間の便を選び直す")
    }

    @Test("一致する便が無ければ、勝手に置き換えず差分として提示する")
    func proposesUpdateWhenNoMatch() async throws {
        let routing = FakeSegmentRouting()
        routing.times["A駅->B駅#transit"] = 29 * 60
        let planner = RoutePlanner(stops: FakeStopLocator(), routing: routing)

        var target = try await planner.computeLegs(plan())
        let departure = TestDates.make(2026, 8, 15, 10, 0)
        target.setLeg(RouteLeg(expectedTravelTime: 21 * 60), at: 1)
        target.pinTime(TimeAnchor(kind: .depart, date: departure), at: 1)

        target.clearLegs()
        let recomputed = try await planner.computeLegs(target)

        // 表示は選んだ内容のまま。
        let leg = try #require(recomputed.segments[1].leg)
        #expect(leg.expectedTravelTime == 21 * 60.0, "選択が取り消されない")

        // 食い違いは提案として持つ。
        let update = try #require(recomputed.pendingUpdate(at: 1))
        #expect(update.current.expectedTravelTime == 21 * 60.0)
        #expect(update.proposed.expectedTravelTime == 29 * 60.0)
        #expect(update.durationDelta == 8 * 60.0)
        #expect(update.isLonger)
    }

    @Test("提案を受け入れると、その内容が新しい選択になる")
    func acceptingUpdateReplacesChoice() async throws {
        let routing = FakeSegmentRouting()
        routing.times["A駅->B駅#transit"] = 29 * 60
        let planner = RoutePlanner(stops: FakeStopLocator(), routing: routing)

        var target = try await planner.computeLegs(plan())
        target.setLeg(RouteLeg(expectedTravelTime: 21 * 60), at: 1)
        target.pinTime(TimeAnchor(kind: .depart, date: TestDates.make(2026, 8, 15, 10, 0)), at: 1)
        target.clearLegs()
        target = try await planner.computeLegs(target)

        target.acceptUpdate(at: 1)

        #expect(target.segments[1].leg?.expectedTravelTime == 29 * 60.0)
        #expect(target.pendingUpdate(at: 1) == nil)
        // 新しい所要時間が次回以降の指紋になる。
        #expect(target.lock(at: 1)?.duration == 29 * 60.0)
    }

    @Test("提案を退ければ、選んだ内容のまま続く")
    func dismissingUpdateKeepsChoice() async throws {
        let routing = FakeSegmentRouting()
        routing.times["A駅->B駅#transit"] = 29 * 60
        let planner = RoutePlanner(stops: FakeStopLocator(), routing: routing)

        var target = try await planner.computeLegs(plan())
        target.setLeg(RouteLeg(expectedTravelTime: 21 * 60), at: 1)
        target.pinTime(TimeAnchor(kind: .depart, date: TestDates.make(2026, 8, 15, 10, 0)), at: 1)
        target.clearLegs()
        target = try await planner.computeLegs(target)

        target.dismissUpdate(at: 1)

        #expect(target.segments[1].leg?.expectedTravelTime == 21 * 60.0)
        #expect(target.pendingUpdate(at: 1) == nil)
    }

    @Test("同じ所要時間の便が見つかれば、差分は出さない")
    func noProposalWhenRouteIsRecovered() async throws {
        let routing = FakeSegmentRouting()
        routing.times["A駅->B駅#transit"] = 29 * 60
        let departure = TestDates.make(2026, 8, 15, 10, 0)
        let shifted = departure.addingTimeInterval(10 * 60)
        routing.timesByDate["A駅->B駅#transit@\(shifted.timeIntervalSince1970)"] = 21 * 60
        let planner = RoutePlanner(stops: FakeStopLocator(), routing: routing)

        var target = try await planner.computeLegs(plan())
        target.setLeg(RouteLeg(expectedTravelTime: 21 * 60), at: 1)
        target.pinTime(TimeAnchor(kind: .depart, date: departure), at: 1)
        target.clearLegs()

        let recomputed = try await planner.computeLegs(target)

        #expect(recomputed.pendingUpdate(at: 1) == nil)
        #expect(abs((recomputed.segments[1].leg?.expectedTravelTime ?? 0) - 21 * 60) < 60)
    }

    @Test("指定した区間は自動分割の対象にしない")
    func lockedSegmentsAreNotSplit() async throws {
        let stops = FakeStopLocator()
        let midpoint = Coordinate(latitude: (stationA.coordinate.latitude + stationB.coordinate.latitude) / 2,
                                  longitude: (stationA.coordinate.longitude + stationB.coordinate.longitude) / 2)
        stops.table = [(midpoint, [Place(name: "中間駅", latitude: midpoint.latitude,
                                         longitude: midpoint.longitude)])]
        let routing = FakeSegmentRouting()
        routing.times["A駅->B駅#transit"] = 40 * 60
        let planner = RoutePlanner(stops: stops, routing: routing)

        var target = try await planner.computeLegs(plan())
        target.setMode(.transit, at: 1)  // ユーザーが「ここは公共交通」と決める

        let refined = try await planner.refine(target, depth: 2)

        #expect(!refined.nodes.map(\.place.name).contains("中間駅"))
    }

    @Test("指定を解除すれば自動推定に戻る")
    func clearingLockRestoresAutomatic() {
        var target = plan()
        target.setMode(.walking, at: 2)
        #expect(target.isLocked(at: 2))

        target.clearLock(at: 2)

        #expect(!target.isLocked(at: 2))
        target.applyPreset(.transit)
        #expect(target.modes[2] == .transit)
    }
}
