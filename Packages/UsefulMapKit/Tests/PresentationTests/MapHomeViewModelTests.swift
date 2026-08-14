import Domain
import Foundation
import Testing

@testable import Presentation

@Suite("MapHomeViewModel")
@MainActor
struct MapHomeViewModelTests {
    @Test("現在地を取得して保持する")
    func fetchesCurrentLocation() async {
        let location = FakeLocationService()
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make(location: location))

        await viewModel.refreshLocation()

        #expect(viewModel.currentCoordinate == TestFixtures.currentLocation)
        #expect(viewModel.locationMessage == nil)
    }

    @Test("未決定なら権限を要求する")
    func requestsAuthorizationWhenNotDetermined() async {
        let location = FakeLocationService(authorizationStatus: .notDetermined)
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make(location: location))

        await viewModel.refreshLocation()

        #expect(location.authorizationRequestCount == 1)
    }

    @Test("許可済みなら権限を再要求しない")
    func doesNotRerequestAuthorization() async {
        let location = FakeLocationService(authorizationStatus: .authorized)
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make(location: location))

        await viewModel.refreshLocation()

        #expect(location.authorizationRequestCount == 0)
    }

    @Test("拒否時は手動で出発地を指定する導線を案内する")
    func deniedShowsManualOriginGuidance() async {
        let location = FakeLocationService(authorizationStatus: .denied, coordinate: nil, error: .denied)
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make(location: location))

        await viewModel.refreshLocation()

        #expect(viewModel.currentCoordinate == nil)
        #expect(viewModel.needsManualOrigin)
        // 文言はロケールで変わるので、案内が出ていることと拒否状態を確認する。
        #expect(viewModel.locationMessage == L10n.string("map.locationDenied"))
    }

    @Test("取得失敗時はエラーメッセージを出すが、権限拒否とは区別する")
    func unavailableLocation() async {
        let location = FakeLocationService(authorizationStatus: .authorized, coordinate: nil, error: .unavailable)
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make(location: location))

        await viewModel.refreshLocation()

        #expect(viewModel.locationMessage == L10n.string("map.locationUnavailable"))
        #expect(!viewModel.needsManualOrigin)
    }

    @Test("保存地点と最近の検索を読み込む")
    func loadsStoredData() async {
        let store = FakeStore()
        store.savePlace(TestFixtures.tokyo, label: .home, at: TestFixtures.now)
        store.recordSearch(TestFixtures.shinjuku, at: TestFixtures.now)
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make(store: store))

        await viewModel.onAppear()

        #expect(viewModel.savedPlaces.map(\.place.name) == ["東京駅"])
        #expect(viewModel.recentSearches.map(\.place.name) == ["新宿御苑"])
    }

    @Test("地点を選ぶと場所詳細の対象になる")
    func selectingPlace() {
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make())
        viewModel.select(TestFixtures.tokyo)
        #expect(viewModel.selectedPlace == TestFixtures.tokyo)
    }

    @Test("検索から渡す初期条件は 現在地発・公共交通")
    func defaultPlan() {
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make())
        let plan = viewModel.makePlan(destination: TestFixtures.tokyo)
        #expect(plan.origin.isCurrentLocation)
        #expect(plan.destination.place == TestFixtures.tokyo)
        #expect(plan.modes == [.transit])
    }
}

@Suite("検索前の条件（下書き）")
@MainActor
struct RouteDraftTests {
    @Test("既定は 現在地発・いま出発")
    func defaults() {
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make())

        #expect(viewModel.draftOrigin == nil)
        #expect(viewModel.draftOriginName == RouteEndpoint.currentLocation.displayName)
        #expect(viewModel.draftTimePreference == .now)
        #expect(viewModel.draftDate == nil)
        #expect(!viewModel.hasDraftTimeCondition)
    }

    @Test("到着時刻を先に指定してから目的地を決められる")
    func setsArrivalBeforeSearching() {
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make())
        let arrival = TestFixtures.date(11, 0)

        viewModel.setDraftTimePreference(.arriveBy, date: arrival)
        #expect(viewModel.hasDraftTimeCondition)

        let plan = viewModel.makePlan(destination: TestFixtures.tokyo)

        #expect(plan.timePreference == .arriveBy)
        #expect(plan.requestedDate == arrival)
        #expect(plan.destination.place == TestFixtures.tokyo)
    }

    @Test("日時を渡さずに時刻条件だけ変えると現在時刻が入る")
    func fillsDateWhenOmitted() {
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make())

        viewModel.setDraftTimePreference(.departAt, date: nil)

        #expect(viewModel.draftDate == TestFixtures.now)
    }

    @Test("いま出発に戻すと日時は外れる")
    func clearsDateForNow() {
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make())
        viewModel.setDraftTimePreference(.arriveBy, date: TestFixtures.date(11, 0))

        viewModel.setDraftTimePreference(.now, date: nil)

        #expect(viewModel.draftDate == nil)
        #expect(!viewModel.hasDraftTimeCondition)
    }

    @Test("出発地を先に指定できる")
    func setsOriginBeforeSearching() {
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make())

        viewModel.draftOrigin = TestFixtures.shinjuku
        #expect(viewModel.draftOriginName == "新宿御苑")

        let plan = viewModel.makePlan(destination: TestFixtures.tokyo)

        #expect(plan.origin.place == TestFixtures.shinjuku)
        #expect(!plan.origin.isCurrentLocation)
    }

    @Test("出発地を現在地に戻せる")
    func resetsOriginToCurrentLocation() {
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make())
        viewModel.draftOrigin = TestFixtures.shinjuku
        viewModel.editingDraftField = .origin

        viewModel.useCurrentLocationAsDraftOrigin()

        #expect(viewModel.draftOrigin == nil)
        #expect(viewModel.editingDraftField == nil)
        #expect(viewModel.makePlan(destination: TestFixtures.tokyo).origin.isCurrentLocation)
    }

    @Test("現在地が取れていれば出発地の座標に使う")
    func usesCurrentCoordinateForOrigin() async {
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make())
        await viewModel.refreshLocation()

        let plan = viewModel.makePlan(destination: TestFixtures.tokyo)

        #expect(plan.origin.place.coordinate == TestFixtures.currentLocation)
    }
}
