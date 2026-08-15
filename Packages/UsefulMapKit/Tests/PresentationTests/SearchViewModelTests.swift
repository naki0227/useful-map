import Domain
import Foundation
import Testing

@testable import Presentation

@Suite("SearchViewModel")
@MainActor
struct SearchViewModelTests {
    @Test("入力すると候補が返る")
    func search() async {
        let service = FakeSearchService(results: [TestFixtures.tokyo, TestFixtures.shinjuku])
        let viewModel = SearchViewModel(dependencies: TestEnvironment.make(search: service))

        await viewModel.updateQuery("東京").value

        #expect(viewModel.results.map(\.name) == ["東京駅", "新宿御苑"])
        #expect(!viewModel.isSearching)
        #expect(viewModel.errorMessage == nil)
        #expect(service.receivedQueries == ["東京"])
    }

    @Test("前後の空白は落として検索する")
    func trimsQuery() async {
        let service = FakeSearchService()
        let viewModel = SearchViewModel(dependencies: TestEnvironment.make(search: service))

        await viewModel.updateQuery("  東京駅  ").value

        #expect(service.receivedQueries == ["東京駅"])
    }

    @Test("現在地を検索の中心として渡す")
    func passesCenter() async {
        let service = FakeSearchService()
        let viewModel = SearchViewModel(dependencies: TestEnvironment.make(search: service),
                                        centerProvider: { TestFixtures.currentLocation })

        await viewModel.updateQuery("東京").value

        #expect(service.receivedCenters == [TestFixtures.currentLocation])
    }

    @Test("空入力にすると結果を消し、検索もしない")
    func emptyQueryResets() async {
        let service = FakeSearchService()
        let viewModel = SearchViewModel(dependencies: TestEnvironment.make(search: service))

        await viewModel.updateQuery("東京").value
        #expect(!viewModel.results.isEmpty)

        await viewModel.updateQuery("").value
        #expect(viewModel.results.isEmpty)
        #expect(!viewModel.hasCompletedSearch)
        #expect(service.receivedQueries == ["東京"])
    }

    @Test("0 件なら結果なしを表示する")
    func emptyState() async {
        let service = FakeSearchService(results: [])
        let viewModel = SearchViewModel(dependencies: TestEnvironment.make(search: service))

        await viewModel.updateQuery("ありえない場所").value

        #expect(viewModel.results.isEmpty)
        #expect(viewModel.showsEmptyState)
    }

    @Test("失敗時はメッセージを出し、結果なし表示にはしない")
    func failure() async {
        let service = FakeSearchService(error: .failed("通信に失敗しました"))
        let viewModel = SearchViewModel(dependencies: TestEnvironment.make(search: service))

        await viewModel.updateQuery("東京").value

        #expect(viewModel.errorMessage == "通信に失敗しました")
        #expect(!viewModel.showsEmptyState)
        #expect(!viewModel.isSearching)
    }

    @Test("キャンセルされた検索では UI を書き換えない")
    func cancelledSearchKeepsUI() async {
        let service = FakeSearchService(results: [TestFixtures.tokyo])
        let viewModel = SearchViewModel(dependencies: TestEnvironment.make(search: service))
        await viewModel.updateQuery("東京").value

        service.error = .cancelled
        await viewModel.updateQuery("東京駅").value

        #expect(viewModel.results.map(\.name) == ["東京駅"])
        #expect(viewModel.errorMessage == nil)
    }

    @Test("入力を変えると古い Task はキャンセルされ、遅れた応答で上書きされない")
    func staleResponseDoesNotOverwrite() async {
        let service = FakeSearchService(results: [TestFixtures.shinjuku])
        service.delay = .milliseconds(120)
        let viewModel = SearchViewModel(dependencies: TestEnvironment.make(search: service))

        let stale = viewModel.updateQuery("新宿")
        service.results = [TestFixtures.tokyo]
        service.delay = .zero
        let fresh = viewModel.updateQuery("東京")

        await fresh.value
        await stale.value

        #expect(viewModel.results.map(\.name) == ["東京駅"])
        #expect(viewModel.queryText == "東京")
    }

    @Test("デバウンス中に入力が変われば、古いクエリは検索されない")
    func debounceSkipsIntermediateInput() async {
        let service = FakeSearchService()
        let viewModel = SearchViewModel(dependencies: TestEnvironment.make(search: service,
                                                                           debounce: .milliseconds(80)))

        let first = viewModel.updateQuery("東")
        let second = viewModel.updateQuery("東京")
        await second.value
        await first.value

        #expect(service.receivedQueries == ["東京"])
    }

    @Test("searchNow はデバウンスを挟まず即座に検索する")
    func searchNow() async {
        let service = FakeSearchService()
        let viewModel = SearchViewModel(dependencies: TestEnvironment.make(search: service,
                                                                           debounce: .seconds(10)))
        viewModel.queryText = "東京駅"
        await viewModel.searchNow().value

        #expect(service.receivedQueries == ["東京駅"])
        #expect(!viewModel.isSearching)
    }

    @Test("空入力で searchNow しても検索しない")
    func searchNowIgnoresEmpty() async {
        let service = FakeSearchService()
        let viewModel = SearchViewModel(dependencies: TestEnvironment.make(search: service))
        await viewModel.searchNow().value
        #expect(service.receivedQueries.isEmpty)
    }

    @Test("クリアで状態が初期化される")
    func clear() async {
        let viewModel = SearchViewModel(dependencies: TestEnvironment.make())
        await viewModel.updateQuery("東京").value

        viewModel.clear()

        #expect(viewModel.queryText.isEmpty)
        #expect(viewModel.results.isEmpty)
        #expect(!viewModel.hasCompletedSearch)
        #expect(!viewModel.showsEmptyState)
    }

    @Test("候補を選ぶと最近の検索へ記録する")
    func selectRecordsHistory() {
        let store = FakeStore()
        let viewModel = SearchViewModel(dependencies: TestEnvironment.make(store: store))

        viewModel.select(TestFixtures.tokyo)

        #expect(store.recentSearches.map(\.place.name) == ["東京駅"])
        #expect(store.recentSearches.first?.searchedAt == TestFixtures.now)
    }
}
