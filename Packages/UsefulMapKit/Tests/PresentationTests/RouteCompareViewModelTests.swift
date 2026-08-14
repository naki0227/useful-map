import Domain
import Foundation
import Testing

@testable import Presentation

@Suite("RouteCompareViewModel")
@MainActor
struct RouteCompareViewModelTests {
    private func makeQuery(mode: TransportMode = .transit,
                           waypoints: [Place] = []) -> RouteQuery {
        RouteQuery(origin: .currentLocation,
                   destination: TestFixtures.tokyo,
                   waypoints: waypoints,
                   transportMode: mode)
    }

    private func standardRoutes(_ query: RouteQuery) -> FakeRouteService {
        let service = FakeRouteService()
        service.responses[.transit] = [
            FakeRouteService.option(.transit, minutes: 22, query: query,
                                    departure: TestFixtures.date(10, 32),
                                    arrival: TestFixtures.date(10, 54))
        ]
        service.responses[.walking] = [FakeRouteService.option(.walking, minutes: 62, query: query)]
        service.responses[.driving] = [FakeRouteService.option(.driving, minutes: 26, query: query)]
        return service
    }

    @Test("既定は選択モードのみを取得する")
    func loadsSelectedMode() async {
        let query = makeQuery()
        let service = standardRoutes(query)
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: service))

        await viewModel.load().value

        #expect(viewModel.options.map(\.mode) == [.transit])
        #expect(!viewModel.isLoading)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("「最適」は全モードを取得して所要時間順に並べる")
    func comparesAllModes() async {
        let query = makeQuery()
        let service = standardRoutes(query)
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: service))

        viewModel.modeFilter = .all
        await viewModel.load().value

        #expect(viewModel.options.map(\.mode) == [.transit, .driving, .walking])
        #expect(viewModel.recommendedID == "transit-0")
    }

    @Test("現在地出発は位置情報で解決してから経路サービスへ渡す")
    func resolvesCurrentLocation() async {
        let query = makeQuery()
        let service = standardRoutes(query)
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: service))

        await viewModel.load().value

        #expect(service.receivedOrigins.first?.coordinate == TestFixtures.currentLocation)
        #expect(service.receivedOrigins.first?.name == RouteEndpoint.currentLocation.displayName)
    }

    @Test("地点出発なら位置情報を使わない")
    func usesExplicitOrigin() async {
        var query = makeQuery()
        query.origin = .place(TestFixtures.shinjuku)
        let service = standardRoutes(query)
        let location = FakeLocationService(authorizationStatus: .denied, coordinate: nil, error: .denied)
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: service,
                                                                                 location: location))

        await viewModel.load().value

        #expect(service.receivedOrigins.first == TestFixtures.shinjuku)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("位置情報が拒否されていれば出発地の手動指定を促す")
    func locationDeniedMessage() async {
        let query = makeQuery()
        let location = FakeLocationService(authorizationStatus: .denied, coordinate: nil, error: .denied)
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: standardRoutes(query),
                                                                                 location: location))

        await viewModel.load().value

        #expect(viewModel.options.isEmpty)
        #expect(viewModel.errorMessage == L10n.string("route.error.location"))
    }

    @Test("候補が 0 件なら「利用可能な経路なし」を表示する")
    func emptyRoutes() async {
        let query = makeQuery()
        let service = FakeRouteService()
        service.responses[.transit] = []
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: service))

        await viewModel.load().value

        #expect(viewModel.options.isEmpty)
        #expect(viewModel.errorMessage == RouteError.noRoutesFound.localizedMessage)
    }

    @Test("一部モードだけ失敗しても、取得できたモードで比較を続ける")
    func partialFailureKeepsComparison() async {
        let query = makeQuery()
        let service = standardRoutes(query)
        service.responses[.transit] = nil
        service.errors[.transit] = .unsupportedInRegion(.transit)
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: service))

        viewModel.modeFilter = .all
        await viewModel.load().value

        #expect(viewModel.options.map(\.mode) == [.driving, .walking])
        #expect(viewModel.errorMessage == nil)
    }

    @Test("全モードが失敗した場合だけエラーを表示する")
    func totalFailureShowsError() async {
        let query = makeQuery()
        let service = FakeRouteService()
        for mode in TransportMode.allCases {
            service.errors[mode] = .unsupportedInRegion(mode)
        }
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: service))

        viewModel.modeFilter = .all
        await viewModel.load().value

        #expect(viewModel.options.isEmpty)
        #expect(viewModel.errorMessage
            == RouteError.unsupportedInRegion(.transit).localizedMessage)
    }

    @Test("モードを切り替えると条件も更新して取り直す")
    func switchingModeReloads() async {
        let query = makeQuery()
        let service = standardRoutes(query)
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: service))
        await viewModel.load().value

        viewModel.modeFilter = .mode(.walking)
        await viewModel.load().value

        #expect(viewModel.query.transportMode == .walking)
        #expect(viewModel.options.map(\.mode) == [.walking])
    }

    @Test("取得に成功したら最近の経路へ記録する")
    func recordsHistory() async {
        let query = makeQuery()
        let store = FakeStore()
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: standardRoutes(query),
                                                                                 store: store))

        await viewModel.load().value

        #expect(store.recentRoutes.count == 1)
        #expect(store.recentRoutes.first?.destination == TestFixtures.tokyo)
        #expect(store.recentRoutes.first?.usedAt == TestFixtures.now)
    }

    @Test("0 件のときは履歴へ記録しない")
    func doesNotRecordEmptyResult() async {
        let query = makeQuery()
        let store = FakeStore()
        let service = FakeRouteService()
        service.responses[.transit] = []
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: service, store: store))

        await viewModel.load().value

        #expect(store.recentRoutes.isEmpty)
    }

    @Test("古いリクエストの応答で新しい結果を上書きしない")
    func staleResponseIsDropped() async {
        let query = makeQuery()
        let service = standardRoutes(query)
        service.delay = .milliseconds(120)
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: service))

        let stale = viewModel.load()
        service.delay = .zero
        service.responses[.transit] = [FakeRouteService.option(.transit, minutes: 5, query: query)]
        let fresh = viewModel.load()

        await fresh.value
        await stale.value

        #expect(viewModel.options.map(\.expectedTravelTime) == [5 * 60])
    }

    // MARK: - 外部詳細遷移

    @Test("公共交通の詳細は Primary URL で開く")
    func openDetailPrimary() async throws {
        let query = makeQuery()
        let linking = FakeDetailLinking()
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: standardRoutes(query),
                                                                                 detail: linking))
        await viewModel.load().value
        let option = try #require(viewModel.options.first)

        await viewModel.openDetail(for: option)

        #expect(viewModel.lastOpenOutcome == .openedPrimary)
        #expect(viewModel.lastOpenedURL == linking.primary?.absoluteString)
        #expect(linking.openedOptions.count == 1)
    }

    @Test("fallback したときは公式 URL を記録する")
    func openDetailFallback() async throws {
        let query = makeQuery()
        let linking = FakeDetailLinking()
        linking.outcome = .openedFallback
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: standardRoutes(query),
                                                                                 detail: linking))
        await viewModel.load().value
        let option = try #require(viewModel.options.first)

        await viewModel.openDetail(for: option)

        #expect(viewModel.lastOpenOutcome == .openedFallback)
        #expect(viewModel.lastOpenedURL == linking.official?.absoluteString)
    }

    @Test("どちらも開けなければエラーを表示する")
    func openDetailFailure() async throws {
        let query = makeQuery()
        let linking = FakeDetailLinking()
        linking.outcome = .failed
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: standardRoutes(query),
                                                                                 detail: linking))
        await viewModel.load().value
        let option = try #require(viewModel.options.first)

        await viewModel.openDetail(for: option)

        #expect(viewModel.lastOpenOutcome == .failed)
        #expect(viewModel.lastOpenedURL == nil)
        #expect(viewModel.errorMessage == L10n.string("route.open.failed"))
    }

    @Test("徒歩・車の候補では外部詳細を開かない")
    func doesNotOpenDetailForNonTransit() async throws {
        var query = makeQuery(mode: .walking)
        query.transportMode = .walking
        let linking = FakeDetailLinking()
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: standardRoutes(query),
                                                                                 detail: linking))
        await viewModel.load().value
        let option = try #require(viewModel.options.first)

        await viewModel.openDetail(for: option)

        #expect(linking.openedOptions.isEmpty)
        #expect(viewModel.lastOpenOutcome == nil)
    }

    // MARK: - 経路編集

    @Test("出発地・目的地の変更で再取得する")
    func editingEndpointsReloads() async {
        let query = makeQuery()
        let service = standardRoutes(query)
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: service))
        await viewModel.load().value

        viewModel.setOrigin(.place(TestFixtures.shinjuku))
        await viewModel.load().value
        #expect(viewModel.query.origin == .place(TestFixtures.shinjuku))

        viewModel.setDestination(TestFixtures.shibuya)
        await viewModel.load().value
        #expect(viewModel.query.destination == TestFixtures.shibuya)
        #expect(service.receivedQueries.count >= 3)
    }

    @Test("経由地の追加・削除・並べ替えが条件に反映される")
    func waypointEditing() async {
        let query = makeQuery()
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: standardRoutes(query)))

        viewModel.addWaypoint(TestFixtures.shinjuku)
        viewModel.addWaypoint(TestFixtures.shibuya)
        await viewModel.load().value
        #expect(viewModel.query.waypoints.map(\.name) == ["新宿御苑", "渋谷スクランブルスクエア"])

        viewModel.moveWaypoints(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(viewModel.query.waypoints.map(\.name) == ["渋谷スクランブルスクエア", "新宿御苑"])

        viewModel.removeWaypoint(id: TestFixtures.shibuya.id)
        #expect(viewModel.query.waypoints.map(\.name) == ["新宿御苑"])
    }

    @Test("時刻条件を変えると requestedDate が入る")
    func timePreferenceEditing() async {
        let query = makeQuery()
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: standardRoutes(query)))

        viewModel.setTimePreference(.arriveBy, date: TestFixtures.date(11, 0))
        #expect(viewModel.query.timePreference == .arriveBy)
        #expect(viewModel.query.requestedDate == TestFixtures.date(11, 0))

        viewModel.setTimePreference(.now, date: nil)
        #expect(viewModel.query.requestedDate == nil)
    }

    @Test("日時未指定で時刻条件にすると現在時刻を使う")
    func timePreferenceDefaultsToNow() {
        let query = makeQuery()
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: standardRoutes(query)))

        viewModel.setTimePreference(.departAt, date: nil)
        #expect(viewModel.query.requestedDate == TestFixtures.now)
    }

    @Test("解決済み現在地があれば出発地と目的地を入れ替えられる")
    func swapEndpoints() async {
        let query = makeQuery()
        let viewModel = RouteCompareViewModel(query: query,
                                              dependencies: TestEnvironment.make(routes: standardRoutes(query)))
        await viewModel.load().value

        viewModel.swapEndpoints()

        #expect(viewModel.query.origin == .place(TestFixtures.tokyo))
        #expect(viewModel.query.destination.coordinate == TestFixtures.currentLocation)
    }

    @Test("タイトルは 出発地 → 目的地")
    func title() {
        let viewModel = RouteCompareViewModel(query: makeQuery(),
                                              dependencies: TestEnvironment.make())
        #expect(viewModel.title == "\(RouteEndpoint.currentLocation.displayName) → 東京駅")
    }

    @Test("ModeFilter は 最適 + 全モードを持つ")
    func modeFilters() {
        let filters = RouteCompareViewModel.ModeFilter.allCases
        #expect(filters.map(\.id) == ["all", "transit", "walking", "driving"])
        #expect(filters.allSatisfy { !$0.displayName.isEmpty && !$0.symbolName.isEmpty })
    }
}
