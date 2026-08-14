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
        #expect(viewModel.locationMessage?.contains("出発地") == true)
    }

    @Test("取得失敗時はエラーメッセージを出すが、権限拒否とは区別する")
    func unavailableLocation() async {
        let location = FakeLocationService(authorizationStatus: .authorized, coordinate: nil, error: .unavailable)
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make(location: location))

        await viewModel.refreshLocation()

        #expect(viewModel.locationMessage == "現在地を取得できませんでした")
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

    @Test("場所詳細から渡す初期条件は 現在地発・公共交通")
    func defaultQuery() {
        let viewModel = MapHomeViewModel(dependencies: TestEnvironment.make())
        let query = viewModel.defaultQuery(for: TestFixtures.tokyo)
        #expect(query.origin == .currentLocation)
        #expect(query.destination == TestFixtures.tokyo)
        #expect(query.transportMode == .transit)
    }
}
