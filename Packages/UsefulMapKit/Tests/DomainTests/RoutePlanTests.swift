import Foundation
import Testing

@testable import Domain

@Suite("RoutePlan")
struct RoutePlanTests {
    private let home = Place(name: "現在地", latitude: 34.7100, longitude: 135.5000)
    private let umeda = Place(name: "梅田駅", latitude: 34.7025, longitude: 135.4959)
    private let osaka = Place(name: "大阪駅", latitude: 34.7024854, longitude: 135.4959506)
    private let city = Place(name: "大阪ステーションシティ", latitude: 34.7030, longitude: 135.4970)

    private func node(_ place: Place, _ kind: RouteNode.Kind, inferred: Bool = false) -> RouteNode {
        RouteNode(place: place, kind: kind, isInferred: inferred)
    }

    private func fourNodePlan() -> RoutePlan {
        RoutePlan(nodes: [node(home, .origin),
                          node(umeda, .station, inferred: true),
                          node(osaka, .station, inferred: true),
                          node(city, .destination)],
                  modes: [.walking, .transit, .walking])
    }

    @Test("区間はノードの隣接ペアになる")
    func segments() {
        let plan = fourNodePlan()
        #expect(plan.segments.count == 3)
        #expect(plan.segments.map(\.mode) == [.walking, .transit, .walking])
        #expect(plan.segments[0].from.place == home)
        #expect(plan.segments[2].to.place == city)
    }

    @Test("モード数はノード数 - 1 に正規化される")
    func normalizesModeCount() {
        let plan = RoutePlan(nodes: [node(home, .origin), node(osaka, .destination)],
                             modes: [.transit, .walking, .driving])
        #expect(plan.modes == [.transit])

        let padded = RoutePlan(nodes: [node(home, .origin),
                                       node(umeda, .station),
                                       node(osaka, .destination)],
                               modes: [.walking])
        #expect(padded.modes == [.walking, .walking])
    }

    @Test("区間ごとに移動手段を変えられる")
    func setModePerSegment() {
        var plan = fourNodePlan()
        plan.setMode(.driving, at: 0)
        #expect(plan.modes == [.driving, .transit, .walking])
    }

    @Test("矢印のトグルは 公共交通 → 徒歩 → 車 → 公共交通 の順で回る")
    func cycleMode() {
        var plan = RoutePlan.simple(origin: node(home, .origin),
                                    destination: node(osaka, .destination),
                                    mode: .transit)
        plan.cycleMode(at: 0)
        #expect(plan.modes == [.walking])
        plan.cycleMode(at: 0)
        #expect(plan.modes == [.driving])
        plan.cycleMode(at: 0)
        #expect(plan.modes == [.transit])
    }

    @Test("一括プリセットは全区間を揃える")
    func applyPreset() {
        var plan = fourNodePlan()
        plan.applyPreset(.driving)
        #expect(plan.modes == [.driving, .driving, .driving])
    }

    @Test("モードを変えた区間の結果は捨てる")
    func changingModeInvalidatesLeg() {
        var plan = fourNodePlan()
        plan.setLeg(RouteLeg(expectedTravelTime: 600), at: 0)
        plan.setLeg(RouteLeg(expectedTravelTime: 1_200), at: 1)

        plan.setMode(.driving, at: 0)

        #expect(plan.segments[0].leg == nil)
        #expect(plan.segments[1].leg?.expectedTravelTime == 1_200, "他の区間は保つ")
    }

    @Test("地点を差し替えると前後の区間の結果を捨て、推定フラグも外れる")
    func updatingPlaceInvalidatesNeighbours() {
        var plan = fourNodePlan()
        for index in 0..<3 { plan.setLeg(RouteLeg(expectedTravelTime: 600), at: index) }

        plan.updatePlace(Place(name: "北新地駅", latitude: 34.6955, longitude: 135.4966), at: 1)

        #expect(plan.nodes[1].place.name == "北新地駅")
        #expect(!plan.nodes[1].isInferred)
        #expect(plan.segments[0].leg == nil)
        #expect(plan.segments[1].leg == nil)
        #expect(plan.segments[2].leg != nil, "離れた区間は保つ")
    }

    @Test("経由地を区間の途中に挿し込める")
    func insertNode() {
        var plan = RoutePlan.simple(origin: node(home, .origin),
                                    destination: node(osaka, .destination),
                                    mode: .walking)
        plan.insertNode(node(umeda, .waypoint), afterSegment: 0)

        #expect(plan.nodes.map(\.place.name) == ["現在地", "梅田駅", "大阪駅"])
        #expect(plan.modes == [.walking, .walking])
    }

    @Test("中間ノードは削除できるが、出発地と目的地は消せない")
    func removeNode() {
        var plan = fourNodePlan()
        plan.removeNode(at: 1)
        #expect(plan.nodes.map(\.place.name) == ["現在地", "大阪駅", "大阪ステーションシティ"])
        #expect(plan.modes.count == 2)

        let before = plan.nodes
        plan.removeNode(at: 0)
        plan.removeNode(at: plan.nodes.count - 1)
        #expect(plan.nodes == before)
    }

    @Test("入れ替えるとノードと区間の並びが反転する")
    func reverse() {
        var plan = fourNodePlan()
        plan.reverse()

        #expect(plan.nodes.map(\.place.name)
                == ["大阪ステーションシティ", "大阪駅", "梅田駅", "現在地"])
        #expect(plan.modes == [.walking, .transit, .walking])
        #expect(plan.origin.kind == .origin)
        #expect(plan.destination.kind == .destination)
    }

    @Test("自動推定した駅だけをまとめて外せる")
    func removeInferredStations() {
        var plan = RoutePlan(nodes: [node(home, .origin),
                                     node(umeda, .station, inferred: true),
                                     node(city, .waypoint),
                                     node(osaka, .destination)],
                             modes: [.walking, .transit, .walking])
        plan.removeInferredStations()

        #expect(plan.nodes.map(\.place.name) == ["現在地", "大阪ステーションシティ", "大阪駅"])
    }

    @Test("全区間が揃ったときだけ合計を返す")
    func totals() {
        var plan = fourNodePlan()
        #expect(plan.totalTravelTime == nil)

        plan.setLeg(RouteLeg(expectedTravelTime: 600, distance: 500), at: 0)
        plan.setLeg(RouteLeg(expectedTravelTime: 1_260,
                             departureDate: TestDates.make(2026, 8, 15, 5, 13),
                             arrivalDate: TestDates.make(2026, 8, 15, 5, 34),
                             distance: 14_000), at: 1)
        #expect(plan.totalTravelTime == nil, "1 区間でも欠けたら合計は出さない")

        plan.setLeg(RouteLeg(expectedTravelTime: 240, distance: 300), at: 2)
        #expect(plan.totalTravelTime == 2_100)
        #expect(plan.totalDistance == 14_800)
    }

    @Test("公共交通区間があれば Google Maps へ委譲できる")
    func includesTransit() {
        #expect(fourNodePlan().includesTransit)

        var walkingOnly = fourNodePlan()
        walkingOnly.applyPreset(.walking)
        #expect(!walkingOnly.includesTransit)
    }

    @Test("時刻指定なのに日時が無いプランは不正")
    func validity() {
        var plan = fourNodePlan()
        #expect(plan.isValid)

        plan.timePreference = .arriveBy
        #expect(!plan.isValid)

        plan.requestedDate = TestDates.make(2026, 8, 15, 11, 0)
        #expect(plan.isValid)
    }
}

@Suite("RoutePlanBuilder（駅の差し込み）")
struct RoutePlanBuilderTests {
    private let home = Place(name: "自宅", latitude: 34.7100, longitude: 135.5000)
    private let umeda = Place(name: "梅田駅", latitude: 34.7025, longitude: 135.4959)
    private let kyoto = Place(name: "京都駅", latitude: 34.9858083, longitude: 135.7587846)
    private let hotel = Place(name: "京都ホテル", latitude: 34.9950, longitude: 135.7600)

    private func plan(from origin: Place, to destination: Place, mode: TransportMode = .transit) -> RoutePlan {
        RoutePlan.simple(origin: RouteNode(place: origin, kind: .origin),
                         destination: RouteNode(place: destination, kind: .destination),
                         mode: mode)
    }

    @Test("両端に駅を差し込むと 徒歩→電車→徒歩 になる")
    func insertsBothStations() {
        let result = RoutePlanBuilder.insertingStations(into: plan(from: home, to: hotel),
                                                        originStation: umeda,
                                                        destinationStation: kyoto)

        #expect(result.nodes.map(\.place.name) == ["自宅", "梅田駅", "京都駅", "京都ホテル"])
        #expect(result.modes == [.walking, .transit, .walking])
        #expect(result.nodes[1].isInferred)
        #expect(result.nodes[1].kind == .station)
    }

    @Test("目的地そのものが駅なら、その先の徒歩区間は作らない")
    func skipsWalkWhenDestinationIsStation() {
        let result = RoutePlanBuilder.insertingStations(into: plan(from: home, to: kyoto),
                                                        originStation: umeda,
                                                        destinationStation: kyoto)

        #expect(result.nodes.map(\.place.name) == ["自宅", "梅田駅", "京都駅"])
        #expect(result.modes == [.walking, .transit])
    }

    @Test("駅が取れなければ元のプランのまま（機能は止めない）")
    func keepsPlanWhenNoStationFound() {
        let original = plan(from: home, to: hotel)
        let result = RoutePlanBuilder.insertingStations(into: original,
                                                        originStation: nil,
                                                        destinationStation: nil)
        #expect(result.nodes.count == 2)
        #expect(result.modes == [.transit])
    }

    @Test("公共交通以外のプランには駅を挟まない")
    func onlyForTransit() {
        let walking = plan(from: home, to: hotel, mode: .walking)
        let result = RoutePlanBuilder.insertingStations(into: walking,
                                                        originStation: umeda,
                                                        destinationStation: kyoto)
        #expect(result.nodes.count == 2)
    }

    @Test("出発地の目の前が駅なら徒歩区間を挟まない")
    func skipsNearbyStation() {
        // 梅田駅から 50m ほどの地点。
        let nearStation = Place(name: "駅前ビル", latitude: 34.70295, longitude: 135.4959)
        #expect(!RoutePlanBuilder.shouldInsert(station: umeda, near: nearStation))
        #expect(RoutePlanBuilder.shouldInsert(station: umeda, near: home))
    }

    @Test("出発側と目的側で同じ駅になった場合は電車区間を作らない")
    func ignoresIdenticalStations() {
        let result = RoutePlanBuilder.insertingStations(into: plan(from: home, to: hotel),
                                                        originStation: umeda,
                                                        destinationStation: umeda)
        #expect(result.nodes.map(\.place.name) == ["自宅", "梅田駅", "京都ホテル"])
        #expect(result.modes == [.walking, .transit])
    }
}

@Suite("時刻表の起点")
struct RoutePlanScheduleTests {
    private let home = Place(name: "自宅", latitude: 34.7500, longitude: 135.5000)
    private let station = Place(name: "駅", latitude: 34.7428, longitude: 135.5000)
    private let goal = Place(name: "目的地", latitude: 34.9950, longitude: 135.7600)

    private func node(_ place: Place, _ kind: RouteNode.Kind) -> RouteNode {
        RouteNode(place: place, kind: kind)
    }

    /// 徒歩 → 公共交通 の 2 区間。徒歩には時刻が無い。
    private func plan() -> RoutePlan {
        var plan = RoutePlan(nodes: [node(home, .origin), node(station, .station), node(goal, .destination)],
                             modes: [.walking, .transit])
        plan.setLeg(RouteLeg(expectedTravelTime: 360), at: 0)  // 徒歩 6 分・時刻なし
        plan.setLeg(RouteLeg(expectedTravelTime: 1_320,
                             departureDate: TestDates.make(2026, 8, 15, 10, 32),
                             arrivalDate: TestDates.make(2026, 8, 15, 10, 54)), at: 1)
        return plan
    }

    @Test("最初が徒歩でも、公共交通の時刻から全体の出発時刻を逆算する")
    func derivesDepartureFromTransitLeg() {
        let target = plan()
        let schedule = target.schedule()

        // 10:32 の電車に乗るため、6 分前の 10:26 に歩き始める。
        #expect(schedule[0]?.departure == TestDates.make(2026, 8, 15, 10, 26))
        #expect(schedule[0]?.arrival == TestDates.make(2026, 8, 15, 10, 32))
        #expect(schedule[1]?.departure == TestDates.make(2026, 8, 15, 10, 32))

        #expect(target.departureDate == TestDates.make(2026, 8, 15, 10, 26))
        #expect(target.arrivalDate == TestDates.make(2026, 8, 15, 10, 54))
    }

    @Test("時刻を持つ区間が 1 つも無ければ時刻表は空")
    func noScheduleWithoutTransit() {
        var target = RoutePlan(nodes: [node(home, .origin), node(goal, .destination)], modes: [.walking])
        target.setLeg(RouteLeg(expectedTravelTime: 600), at: 0)

        #expect(target.schedule().allSatisfy { $0 == nil })
        #expect(target.departureDate == nil)
    }

    @Test("便を固定した場合はそちらが起点になる")
    func pinTakesPrecedence() {
        var target = plan()
        target.pinTime(TimeAnchor(kind: .depart, date: TestDates.make(2026, 8, 15, 11, 0)), at: 1)
        // 固定すると前後の区間は取り直しになるので、再取得された状態を作る。
        #expect(target.segments[0].leg == nil, "前の区間は取り直し待ちになる")
        target.setLeg(RouteLeg(expectedTravelTime: 360), at: 0)

        let schedule = target.schedule()
        #expect(schedule[1]?.departure == TestDates.make(2026, 8, 15, 11, 0))
        #expect(schedule[0]?.departure == TestDates.make(2026, 8, 15, 10, 54))
    }
}
