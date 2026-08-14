import Domain
import Foundation
import Testing

@testable import Presentation

@Suite("RoutePlanViewModel")
@MainActor
struct RoutePlanViewModelTests {
    private let home = Place(name: "自宅", latitude: 34.7500, longitude: 135.5000)
    private let station = Place(name: "近所の駅", latitude: 34.7428, longitude: 135.5000)
    private let kyoto = Place(name: "京都駅", latitude: 34.9858, longitude: 135.7587)
    private let goal = Place(name: "京都ホテル", latitude: 34.9950, longitude: 135.7600)

    private func node(_ place: Place, _ kind: RouteNode.Kind) -> RouteNode {
        RouteNode(place: place, kind: kind)
    }

    private func plan() -> RoutePlan {
        RoutePlan(nodes: [node(home, .origin), node(station, .station),
                          node(kyoto, .station), node(goal, .destination)],
                  modes: [.walking, .transit, .walking])
    }

    private func makeViewModel(store: FakeStore = FakeStore(),
                               location: FakeLocationService = FakeLocationService(),
                               detail: FakeDetailLinking = FakeDetailLinking(),
                               resolver: PlaceResolving = FakePlaceResolver())
        -> RoutePlanViewModel {
        RoutePlanViewModel(plan: plan(),
                           dependencies: TestEnvironment.make(location: location,
                                                              placeResolver: resolver,
                                                              detail: detail,
                                                              store: store))
    }

    @Test("区間ごとの所要時間を取得する")
    func loadsLegs() async {
        let viewModel = makeViewModel()

        await viewModel.reload().value

        #expect(viewModel.segments.count == 3)
        #expect(viewModel.segments.allSatisfy { $0.leg != nil })
        #expect(viewModel.totalTravelTime != nil)
    }

    @Test("矢印のアイコンを押すと区間の手段が切り替わる")
    func togglesSegmentMode() async {
        let viewModel = makeViewModel()
        await viewModel.reload().value

        viewModel.toggleMode(at: 1)
        await viewModel.reload().value

        #expect(viewModel.segments[1].mode == .walking, "公共交通 → 徒歩")
        #expect(viewModel.isLocked(at: 1), "ユーザー指定として記録される")
    }

    @Test("プリセットはユーザーが決めた区間を上書きしない")
    func presetKeepsUserChoice() async {
        let viewModel = makeViewModel()
        await viewModel.reload().value
        viewModel.toggleMode(at: 2)  // 最後の徒歩を車に

        await viewModel.rebuild(preset: .transit).value

        #expect(viewModel.segments.last?.mode != .walking || viewModel.isLocked(at: 2))
    }

    @Test("地点を選ぶと編集が閉じて取り直す")
    func updatingPlaceClosesEditor() async {
        let viewModel = makeViewModel()
        viewModel.editingNodeIndex = 1

        viewModel.updatePlace(Place(name: "別の駅", latitude: 34.7400, longitude: 135.5000), at: 1)
        await viewModel.reload().value

        #expect(viewModel.editingNodeIndex == nil)
        #expect(viewModel.nodes[1].place.name == "別の駅")
    }

    @Test("経由地は押した区間の途中に入る（他のノードは消えない）")
    func addsWaypointIntoChosenSegment() async {
        let viewModel = makeViewModel()
        await viewModel.reload().value

        // 先頭の区間（自宅 → 近所の駅）の途中に足す。
        viewModel.beginAddingWaypoint(afterSegment: 0)
        #expect(viewModel.addingWaypointAfterSegment == 0)
        #expect(viewModel.editingNodeIndex == nil, "既存ノードの編集は始まらない")

        viewModel.commitPlace(Place(name: "寄り道", latitude: 34.7460, longitude: 135.5000), at: 0)
        await viewModel.reload().value

        #expect(viewModel.nodes.map(\.place.name)
                == ["自宅", "寄り道", "近所の駅", "京都駅", "京都ホテル"],
                "目的地も他のノードも消えない")
        #expect(viewModel.addingWaypointAfterSegment == nil)
    }

    @Test("経由地の追加はキャンセルできる")
    func cancelsAddingWaypoint() async {
        let viewModel = makeViewModel()
        await viewModel.reload().value
        let before = viewModel.nodes

        viewModel.beginAddingWaypoint(afterSegment: 1)
        viewModel.cancelAddingWaypoint()

        #expect(viewModel.addingWaypointAfterSegment == nil)
        #expect(viewModel.nodes == before)
    }

    @Test("入れ替えで出発地と目的地が反転する")
    func swaps() async {
        let viewModel = makeViewModel()
        await viewModel.reload().value

        viewModel.swapEndpoints()
        await viewModel.reload().value

        #expect(viewModel.nodes.first?.place == goal)
        #expect(viewModel.nodes.last?.place == home)
    }

    @Test("現在地ボタンで出発地が現在地になる")
    func usesCurrentLocation() async {
        let location = FakeLocationService()
        let viewModel = makeViewModel(location: location)

        await viewModel.useCurrentLocation().value

        #expect(viewModel.nodes[0].isCurrentLocation)
        #expect(viewModel.nodes[0].place.coordinate == TestFixtures.currentLocation)
    }

    @Test("位置情報が拒否されていれば案内を出す")
    func currentLocationDenied() async {
        let location = FakeLocationService(authorizationStatus: .denied, coordinate: nil, error: .denied)
        let viewModel = makeViewModel(location: location)

        await viewModel.useCurrentLocation().value

        #expect(viewModel.errorMessage == L10n.string("route.error.location"))
    }

    @Test("徒歩ペースはボタン 1 つで切り替わり、徒歩区間の時間が変わる")
    func cyclesWalkingPace() async {
        let viewModel = makeViewModel()
        await viewModel.reload().value
        let normalWalk = viewModel.segments[0].leg?.expectedTravelTime

        viewModel.cycleWalkingPace()
        #expect(viewModel.walkingPace == .fast)
        await viewModel.reload(recomputeAll: true).value

        let fastWalk = viewModel.segments[0].leg?.expectedTravelTime
        #expect((fastWalk ?? 0) < (normalWalk ?? 0))

        viewModel.cycleWalkingPace()
        #expect(viewModel.walkingPace == .slow)
    }

    @Test("区間ごとに外部詳細を開ける")
    func detailAvailability() async {
        let viewModel = makeViewModel()
        await viewModel.reload().value

        #expect(viewModel.canOpenDetail(at: 0))
        #expect(viewModel.canOpenDetail(at: 1))
        #expect(!viewModel.canOpenDetail(at: 99))
    }

    @Test("区間の詳細は Primary URL で開き、結果を保持する")
    func opensDetail() async {
        let linking = FakeDetailLinking()
        let viewModel = makeViewModel(detail: linking)
        await viewModel.reload().value

        await viewModel.openDetail(at: 1)

        #expect(viewModel.lastOpenOutcome == .openedPrimary)
        #expect(viewModel.lastOpenedURL == linking.primary?.absoluteString)
        #expect(linking.openedOptions.count == 1)
    }

    @Test("区間の詳細はその区間の 2 地点だけを渡す（経由地を持たない）")
    func detailOptionIsPointToPoint() async throws {
        let viewModel = makeViewModel()
        await viewModel.reload().value

        // 公共交通の区間。
        let transit = try #require(viewModel.detailOption(at: 1))
        #expect(transit.origin == station)
        #expect(transit.destination == kyoto)
        #expect(transit.waypoints.isEmpty, "Google は公共交通で経由地を扱えない")
        #expect(transit.mode == .transit)

        // 徒歩の区間も同じ形で開ける。
        let walking = try #require(viewModel.detailOption(at: 0))
        #expect(walking.origin == home)
        #expect(walking.destination == station)
        #expect(walking.mode == .walking)
    }

    @Test("区間の詳細にはその区間の発着時刻が入る")
    func detailOptionCarriesSegmentTime() async throws {
        let viewModel = makeViewModel()
        await viewModel.reload().value

        let option = try #require(viewModel.detailOption(at: 1))
        #expect(option.departureDate != nil)
        #expect(option.timeAnchor != nil, "時刻付き URL を作れる")
    }

    @Test("範囲外の区間では何も開かない")
    func ignoresInvalidSegment() async {
        let linking = FakeDetailLinking()
        let viewModel = makeViewModel(detail: linking)
        await viewModel.reload().value

        await viewModel.openDetail(at: 99)

        #expect(linking.openedOptions.isEmpty)
        #expect(viewModel.lastOpenOutcome == nil)
    }

    @Test("取得に成功したら履歴へ記録する")
    func recordsHistory() async {
        let store = FakeStore()
        let viewModel = makeViewModel(store: store)

        await viewModel.reload().value

        #expect(store.recentRoutes.count == 1)
        #expect(store.recentRoutes.first?.destination == goal)
    }

    @Test("編集のたびに古いリクエストは捨てられる")
    func dropsStaleRequests() async {
        let viewModel = makeViewModel()
        let stale = viewModel.reload()
        let fresh = viewModel.reload()

        await fresh.value
        await stale.value

        #expect(!viewModel.isLoading)
    }

    @Test("便の選び直しは公共交通の区間でだけ始められる")
    func picksDepartureOnlyForTransit() async {
        let viewModel = makeViewModel()
        await viewModel.reload().value

        viewModel.beginPickingDeparture(at: 0)  // 徒歩区間
        #expect(viewModel.pickingDepartureAt == nil)

        viewModel.beginPickingDeparture(at: 1)  // 公共交通区間
        #expect(viewModel.pickingDepartureAt == 1)

        viewModel.cancelPickingDeparture()
        #expect(viewModel.pickingDepartureAt == nil)
    }

    @Test("中間ノードは外せるが、出発地と目的地は外せない")
    func removesIntermediateNodes() async {
        let viewModel = makeViewModel()
        await viewModel.reload().value

        viewModel.removeNode(at: 1)
        await viewModel.reload().value
        #expect(viewModel.nodes.map(\.place.name) == ["自宅", "京都駅", "京都ホテル"])

        let before = viewModel.nodes
        viewModel.removeNode(at: 0)
        #expect(viewModel.nodes == before)
    }
}

@Suite("ノードの自動振り分け")
@MainActor
struct AutomaticNodeAssignmentTests {
    private let home = Place(name: "自宅", latitude: 34.7500, longitude: 135.5000)
    private let station = Place(name: "近所の駅", latitude: 34.7428, longitude: 135.5000)
    private let goal = Place(name: "京都ホテル", latitude: 34.9950, longitude: 135.7600)

    /// 自宅の近くと目的地の近くに駅がある状況。
    private func makeViewModel() -> RoutePlanViewModel {
        let stops = FakeStopLocator()
        stops.table = [(home.coordinate, [station]),
                       (goal.coordinate, [Place(name: "京都駅", latitude: 34.9858, longitude: 135.7587)])]
        let planner = RoutePlanner(stops: stops, routing: SimpleSegmentRouting())
        let plan = RoutePlan.simple(origin: RouteNode(place: home, kind: .origin),
                                    destination: RouteNode(place: goal, kind: .destination),
                                    mode: .transit)
        return RoutePlanViewModel(plan: plan,
                                  dependencies: TestEnvironment.make(planner: planner))
    }

    @Test("ユーザーが足した経由地を外すと、自動推定に戻る")
    func removingUserWaypointRestoresInference() async throws {
        let viewModel = makeViewModel()
        await viewModel.rebuild(preset: .transit).value
        #expect(!viewModel.nodes.filter(\.isInferred).isEmpty, "前提: 駅が自動で挟まっている")

        viewModel.insertWaypoint(Place(name: "寄り道", latitude: 34.8000, longitude: 135.6000),
                                 afterSegment: 0)
        await viewModel.reload().value
        #expect(viewModel.nodes.map(\.place.name).contains("寄り道"))

        // #require の中でクロージャを使うと throws 扱いになるため、先に配列へ落とす。
        let names = viewModel.nodes.map(\.place.name)
        let waypointIndex = try #require(names.firstIndex(of: "寄り道"))
        viewModel.removeNode(at: waypointIndex)
        await viewModel.reload().value

        #expect(!viewModel.nodes.map(\.place.name).contains("寄り道"))
        #expect(!viewModel.nodes.filter(\.isInferred).isEmpty, "駅の自動推定が残っている")
    }

    @Test("自動で挟まった駅を外したら、勝手に戻さない")
    func removingInferredStationIsRespected() async throws {
        let viewModel = makeViewModel()
        await viewModel.rebuild(preset: .transit).value

        let inferredFlags = viewModel.nodes.map(\.isInferred)
        let stationIndex = try #require(inferredFlags.firstIndex(of: true))
        let stationName = viewModel.nodes[stationIndex].place.name

        viewModel.removeNode(at: stationIndex)
        await viewModel.reload().value

        #expect(!viewModel.nodes.map(\.place.name).contains(stationName), "外した駅が復活しない")
    }
}
