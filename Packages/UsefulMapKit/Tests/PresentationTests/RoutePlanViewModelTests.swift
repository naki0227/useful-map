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

    @Test("経由地の追加は最後の区間の途中に入る")
    func addsWaypoint() async {
        let viewModel = makeViewModel()
        await viewModel.reload().value

        viewModel.beginAddingWaypoint()
        #expect(viewModel.addingWaypointAfterSegment == 2)
        #expect(viewModel.editingNodeIndex == 3)

        viewModel.commitPlace(Place(name: "寄り道", latitude: 34.9900, longitude: 135.7590), at: 3)
        await viewModel.reload().value

        #expect(viewModel.nodes.map(\.place.name)
                == ["自宅", "近所の駅", "京都駅", "寄り道", "京都ホテル"])
        #expect(viewModel.addingWaypointAfterSegment == nil)
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
