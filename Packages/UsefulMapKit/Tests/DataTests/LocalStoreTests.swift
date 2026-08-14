import Domain
import Foundation
import Testing

@testable import Data

@Suite("LocalStore")
struct LocalStoreTests {
    private let tokyo = Place(name: "東京駅", latitude: 35.6812362, longitude: 139.7671248,
                              address: "東京都千代田区丸の内1丁目9")
    private let shinjuku = Place(name: "新宿御苑", latitude: 35.6852, longitude: 139.7100)
    private let shibuya = Place(name: "渋谷スクランブルスクエア", latitude: 35.6580, longitude: 139.7016)

    private func date(_ day: Int, _ hour: Int = 9) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    /// UserDefaults 実装と In-Memory 実装で同じ振る舞いを保証する。
    private func makeStores() -> [(name: String, store: LocalStoring)] {
        let suiteName = "usefulmap.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return [("UserDefaults", UserDefaultsLocalStore(defaults: defaults)),
                ("InMemory", InMemoryLocalStore())]
    }

    @Test("保存地点は新しい順に並び、同じ地点は重複しない")
    func savingPlaces() {
        for (name, store) in makeStores() {
            store.savePlace(tokyo, label: .home, at: date(14))
            store.savePlace(shinjuku, label: .other, at: date(14, 10))
            store.savePlace(tokyo, label: .school, at: date(14, 11))

            #expect(store.savedPlaces.count == 2, "\(name)")
            #expect(store.savedPlaces.first?.place == tokyo, "\(name)")
            // 再保存でラベルが更新される。
            #expect(store.savedPlaces.first?.label == .school, "\(name)")
            #expect(store.isSaved(tokyo), "\(name)")
        }
    }

    @Test("保存地点を削除できる")
    func removingPlaces() {
        for (name, store) in makeStores() {
            store.savePlace(tokyo, label: .other, at: date(14))
            store.removeSavedPlace(id: tokyo.id)
            #expect(store.savedPlaces.isEmpty, "\(name)")
            #expect(!store.isSaved(tokyo), "\(name)")
        }
    }

    @Test("座標が壊れた地点は保存しない")
    func rejectsBrokenPlaces() {
        for (name, store) in makeStores() {
            store.savePlace(Place(name: "壊れた地点", latitude: 0, longitude: 0), label: .other, at: date(14))
            store.recordSearch(Place(name: "", latitude: 0, longitude: 0), at: date(14))
            #expect(store.savedPlaces.isEmpty, "\(name)")
            #expect(store.recentSearches.isEmpty, "\(name)")
        }
    }

    @Test("最近の検索は新しい順で重複排除される")
    func recentSearches() {
        for (name, store) in makeStores() {
            store.recordSearch(tokyo, at: date(14, 9))
            store.recordSearch(shinjuku, at: date(14, 10))
            store.recordSearch(tokyo, at: date(14, 11))

            #expect(store.recentSearches.map(\.place.name) == ["東京駅", "新宿御苑"], "\(name)")
            #expect(store.recentSearches.first?.searchedAt == date(14, 11), "\(name)")
        }
    }

    @Test("最近の検索は上限件数で打ち切る")
    func recentSearchLimit() {
        for (name, store) in makeStores() {
            for index in 0..<(UserDefaultsLocalStore.Limits.recentSearches + 5) {
                let place = Place(name: "地点\(index)", latitude: 35.0 + Double(index) / 1_000, longitude: 139.0)
                store.recordSearch(place, at: date(14, 9))
            }
            #expect(store.recentSearches.count == UserDefaultsLocalStore.Limits.recentSearches, "\(name)")
            #expect(store.recentSearches.first?.place.name
                    == "地点\(UserDefaultsLocalStore.Limits.recentSearches + 4)", "\(name)")
        }
    }

    @Test("最近の経路は 出発地・目的地・モード が同じなら 1 件にまとまる")
    func recentRoutes() {
        for (name, store) in makeStores() {
            store.recordRoute(origin: .currentLocation, destination: tokyo, transportMode: .transit, at: date(14, 9))
            store.recordRoute(origin: .currentLocation, destination: tokyo, transportMode: .transit, at: date(14, 12))
            store.recordRoute(origin: .currentLocation, destination: tokyo, transportMode: .driving, at: date(14, 13))
            store.recordRoute(origin: .place(shinjuku), destination: shibuya, transportMode: .transit, at: date(13))

            #expect(store.recentRoutes.count == 3, "\(name)")
            #expect(store.recentRoutes.first?.usedAt == date(13), "\(name)")
            #expect(store.recentRoutes.contains { $0.transportMode == .driving }, "\(name)")
        }
    }

    @Test("履歴だけを消去し、保存地点は残す")
    func clearHistory() {
        for (name, store) in makeStores() {
            store.savePlace(tokyo, label: .home, at: date(14))
            store.recordSearch(shinjuku, at: date(14))
            store.recordRoute(origin: .currentLocation, destination: tokyo, transportMode: .transit, at: date(14))

            store.clearHistory()

            #expect(store.recentSearches.isEmpty, "\(name)")
            #expect(store.recentRoutes.isEmpty, "\(name)")
            #expect(store.savedPlaces.count == 1, "\(name)")
        }
    }

    @Test("UserDefaults 実装はアプリ再起動後もデータを復元する")
    func persistsAcrossInstances() {
        let suiteName = "usefulmap.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = UserDefaultsLocalStore(defaults: defaults)
        first.savePlace(tokyo, label: .home, at: date(14))
        first.recordSearch(shinjuku, at: date(14, 10))
        first.recordRoute(origin: .currentLocation, destination: tokyo, transportMode: .transit, at: date(14, 11))

        let restored = UserDefaultsLocalStore(defaults: defaults)
        #expect(restored.savedPlaces.map(\.id) == [tokyo.id])
        #expect(restored.savedPlaces.first?.label == .home)
        #expect(restored.recentSearches.map(\.place.name) == ["新宿御苑"])
        #expect(restored.recentRoutes.first?.destination == tokyo)
    }

    @Test("In-Memory 実装はインスタンスを跨いで保持しない")
    func inMemoryIsEphemeral() {
        let store = InMemoryLocalStore()
        store.savePlace(tokyo, label: .other, at: date(14))
        #expect(store.savedPlaces.count == 1)
        #expect(InMemoryLocalStore().savedPlaces.isEmpty)
    }

    @Test("時刻付き Google 内部 URL は永続化しない（保存対象に URL 文字列を持たない）")
    func doesNotPersistGeneratedURLs() throws {
        let suiteName = "usefulmap.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsLocalStore(defaults: defaults)
        store.recordRoute(origin: .currentLocation, destination: tokyo, transportMode: .transit, at: date(14))

        let raw = try #require(defaults.data(forKey: "usefulmap.recentRoutes"))
        let json = try #require(String(data: raw, encoding: .utf8))
        #expect(!json.contains("google.com"))
        #expect(!json.contains("data="))
    }
}
