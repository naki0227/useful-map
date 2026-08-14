import Domain
import Foundation
import Testing

@testable import Presentation

@Suite("SavedViewModel")
@MainActor
struct SavedViewModelTests {
    @Test("保存と解除をトグルできる")
    func toggleSave() {
        let store = FakeStore()
        let viewModel = SavedViewModel(dependencies: TestEnvironment.make(store: store))

        viewModel.toggleSave(TestFixtures.tokyo)
        #expect(viewModel.isSaved(TestFixtures.tokyo))
        #expect(viewModel.savedPlaces.map(\.place.name) == ["東京駅"])

        viewModel.toggleSave(TestFixtures.tokyo)
        #expect(!viewModel.isSaved(TestFixtures.tokyo))
        #expect(viewModel.savedPlaces.isEmpty)
    }

    @Test("ラベル付きで保存できる")
    func saveWithLabel() {
        let store = FakeStore()
        let viewModel = SavedViewModel(dependencies: TestEnvironment.make(store: store))

        viewModel.save(TestFixtures.tokyo, label: .home)

        #expect(viewModel.savedPlaces.first?.label == .home)
        #expect(viewModel.savedPlaces.first?.savedAt == TestFixtures.now)
    }

    @Test("保存地点を削除できる")
    func remove() {
        let store = FakeStore()
        let viewModel = SavedViewModel(dependencies: TestEnvironment.make(store: store))
        viewModel.save(TestFixtures.tokyo)

        viewModel.remove(id: TestFixtures.tokyo.id)

        #expect(viewModel.savedPlaces.isEmpty)
    }

    @Test("履歴だけ消去し、保存地点は残す")
    func clearHistory() {
        let store = FakeStore()
        store.recordRoute(origin: .currentLocation, destination: TestFixtures.tokyo,
                          transportMode: .transit, at: TestFixtures.now)
        store.recordSearch(TestFixtures.shinjuku, at: TestFixtures.now)
        let viewModel = SavedViewModel(dependencies: TestEnvironment.make(store: store))
        viewModel.save(TestFixtures.tokyo)

        viewModel.clearHistory()

        #expect(viewModel.recentRoutes.isEmpty)
        #expect(viewModel.recentSearches.isEmpty)
        #expect(viewModel.savedPlaces.count == 1)
    }

    @Test("外部で更新されたストアを refresh で取り込む")
    func refresh() {
        let store = FakeStore()
        let viewModel = SavedViewModel(dependencies: TestEnvironment.make(store: store))
        #expect(viewModel.recentSearches.isEmpty)

        store.recordSearch(TestFixtures.tokyo, at: TestFixtures.now)
        viewModel.refresh()

        #expect(viewModel.recentSearches.map(\.place.name) == ["東京駅"])
    }

    @Test("履歴から経路プランを復元する")
    func planFromHistory() {
        let store = FakeStore()
        let viewModel = SavedViewModel(dependencies: TestEnvironment.make(store: store))
        let route = RecentRoute(origin: .place(TestFixtures.shinjuku),
                                destination: TestFixtures.tokyo,
                                transportMode: .driving,
                                usedAt: TestFixtures.now)

        let plan = viewModel.plan(from: route)

        #expect(plan.origin.place == TestFixtures.shinjuku)
        #expect(plan.destination.place == TestFixtures.tokyo)
        #expect(plan.modes == [.driving])
        #expect(plan.timePreference == .now)
    }

    @Test("現在地発の履歴は現在地として復元する")
    func planFromCurrentLocationHistory() {
        let viewModel = SavedViewModel(dependencies: TestEnvironment.make())
        let route = RecentRoute(origin: .currentLocation,
                                destination: TestFixtures.tokyo,
                                transportMode: .transit,
                                usedAt: TestFixtures.now)

        let plan = viewModel.plan(from: route)

        #expect(plan.origin.isCurrentLocation)
        #expect(plan.destination.place == TestFixtures.tokyo)
    }
}

@Suite("保存地点のラベル付け")
@MainActor
struct SavedPlaceLabelingTests {
    @Test("未保存の地点はラベルを持たない")
    func labelForUnsavedPlace() {
        let viewModel = SavedViewModel(dependencies: TestEnvironment.make())
        #expect(viewModel.label(for: TestFixtures.tokyo) == nil)
    }

    @Test("自宅・学校として保存できる", arguments: [SavedPlace.Label.home, .school, .other])
    func saveWithEachLabel(label: SavedPlace.Label) {
        let viewModel = SavedViewModel(dependencies: TestEnvironment.make())

        viewModel.save(TestFixtures.tokyo, label: label)

        #expect(viewModel.label(for: TestFixtures.tokyo) == label)
        #expect(viewModel.savedPlaces.first?.label == label)
    }

    @Test("保存済み地点のラベルを付け替えられる")
    func changeLabel() {
        let viewModel = SavedViewModel(dependencies: TestEnvironment.make())
        viewModel.save(TestFixtures.tokyo, label: .other)

        viewModel.setLabel(.home, for: TestFixtures.tokyo)

        #expect(viewModel.label(for: TestFixtures.tokyo) == .home)
        #expect(viewModel.savedPlaces.count == 1, "付け替えで重複してはいけない")
    }

    @Test("ラベルを変えても保存日時は維持する")
    func changingLabelKeepsSavedAt() {
        let store = FakeStore()
        store.savePlace(TestFixtures.tokyo, label: .other, at: TestFixtures.date(8, 0, day: 10))
        let viewModel = SavedViewModel(dependencies: TestEnvironment.make(store: store))

        viewModel.setLabel(.school, for: TestFixtures.tokyo)

        #expect(viewModel.savedPlaces.first?.savedAt == TestFixtures.date(8, 0, day: 10))
    }

    @Test("未保存の地点へラベルを付けると、その場で保存される")
    func setLabelOnUnsavedPlaceSaves() {
        let viewModel = SavedViewModel(dependencies: TestEnvironment.make())

        viewModel.setLabel(.home, for: TestFixtures.tokyo)

        #expect(viewModel.isSaved(TestFixtures.tokyo))
        #expect(viewModel.savedPlaces.first?.savedAt == TestFixtures.now)
    }

    @Test("ラベル付きの地点を解除できる")
    func removeLabeledPlace() {
        let viewModel = SavedViewModel(dependencies: TestEnvironment.make())
        viewModel.save(TestFixtures.tokyo, label: .home)

        viewModel.remove(id: TestFixtures.tokyo.id)

        #expect(viewModel.label(for: TestFixtures.tokyo) == nil)
        #expect(viewModel.savedPlaces.isEmpty)
    }
}
