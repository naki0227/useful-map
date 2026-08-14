import Foundation
import Testing

@testable import Domain

@Suite("保存モデル")
struct StoredModelsTests {
    private let tokyo = Place(name: "東京駅", latitude: 35.6812362, longitude: 139.7671248)
    private let shinjuku = Place(name: "新宿御苑", latitude: 35.6852, longitude: 139.7100)

    @Test("SavedPlace の ID は地点 ID と一致する")
    func savedPlaceIdentity() {
        let saved = SavedPlace(place: tokyo, label: .home, savedAt: TestDates.make(2026, 8, 14))
        #expect(saved.id == tokyo.id)
    }

    @Test("SavedPlace.Label は表示名とアイコンを持つ")
    func labels() {
        for label in SavedPlace.Label.allCases {
            #expect(!label.displayName.isEmpty)
            #expect(!label.symbolName.isEmpty)
        }
        // 具体的な文字列は表示ロケールで変わるため、区別可能であることだけを保証する。
        let names = Set(SavedPlace.Label.allCases.map(\.displayName))
        #expect(names.count == SavedPlace.Label.allCases.count)
    }

    @Test("RecentRoute は 出発地・目的地・モードで同一視される")
    func recentRouteIdentity() {
        let base = RecentRoute(origin: .currentLocation,
                               destination: tokyo,
                               transportMode: .transit,
                               usedAt: TestDates.make(2026, 8, 14, 9, 32))
        let sameLater = RecentRoute(origin: .currentLocation,
                                    destination: tokyo,
                                    transportMode: .transit,
                                    usedAt: TestDates.make(2026, 8, 14, 18, 0))
        let differentMode = RecentRoute(origin: .currentLocation,
                                        destination: tokyo,
                                        transportMode: .driving,
                                        usedAt: base.usedAt)
        let differentOrigin = RecentRoute(origin: .place(shinjuku),
                                          destination: tokyo,
                                          transportMode: .transit,
                                          usedAt: base.usedAt)

        #expect(base.id == sameLater.id)
        #expect(base.id != differentMode.id)
        #expect(base.id != differentOrigin.id)
    }

    @Test("Codable 往復で保存データが壊れない")
    func codableRoundTrip() throws {
        let saved = SavedPlace(place: tokyo, label: .school, savedAt: TestDates.make(2026, 8, 14))
        let search = RecentSearch(place: shinjuku, searchedAt: TestDates.make(2026, 8, 13, 18, 15))
        let route = RecentRoute(origin: .place(shinjuku),
                                destination: tokyo,
                                transportMode: .driving,
                                usedAt: TestDates.make(2026, 8, 13, 7, 41))

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        #expect(try decoder.decode(SavedPlace.self, from: encoder.encode(saved)) == saved)
        #expect(try decoder.decode(RecentSearch.self, from: encoder.encode(search)) == search)
        #expect(try decoder.decode(RecentRoute.self, from: encoder.encode(route)) == route)
    }
}
