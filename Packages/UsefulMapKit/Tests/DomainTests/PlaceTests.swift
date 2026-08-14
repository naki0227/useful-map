import Foundation
import Testing

@testable import Domain

@Suite("Place")
struct PlaceTests {
    @Test("名前の前後空白・改行・タブを正規化する")
    func normalizesName() {
        let place = Place(name: "  東京\t駅\n ", latitude: 35.68, longitude: 139.76)
        #expect(place.name == "東京 駅")
    }

    @Test("空文字の住所は nil にする")
    func normalizesAddress() {
        #expect(Place(name: "A", latitude: 1, longitude: 1, address: "   ").address == nil)
        #expect(Place(name: "A", latitude: 1, longitude: 1, address: nil).address == nil)
        #expect(Place(name: "A", latitude: 1, longitude: 1, address: " 東京都 ").address == "東京都")
    }

    @Test("ID は名称と座標から決まり、保存の往復でも安定する")
    func stableIdentity() throws {
        let place = Place(name: "東京駅", latitude: 35.6812362, longitude: 139.7671248)
        #expect(place.id == "東京駅@35.6812362,139.7671248")

        let data = try JSONEncoder().encode(place)
        let restored = try JSONDecoder().decode(Place.self, from: data)
        #expect(restored.id == place.id)
        #expect(restored == place)
    }

    @Test("住所だけが違う同一地点は同じ ID（履歴の重複を防ぐ）")
    func identityIgnoresAddress() {
        let a = Place(name: "東京駅", latitude: 35.68, longitude: 139.76, address: "丸の内")
        let b = Place(name: "東京駅", latitude: 35.68, longitude: 139.76, address: nil)
        #expect(a.id == b.id)
    }

    @Test("経路に使えるのは名称と妥当な座標が揃った地点だけ")
    func routingUsability() {
        #expect(Place(name: "東京駅", latitude: 35.68, longitude: 139.76).isUsableForRouting)
        #expect(!Place(name: "", latitude: 35.68, longitude: 139.76).isUsableForRouting)
        #expect(!Place(name: "東京駅", latitude: 0, longitude: 0).isUsableForRouting)
    }

    @Test("名称が無い場合は座標を表示名に使う")
    func displayNameFallback() {
        let place = Place(name: "", latitude: 35.6812362, longitude: 139.7671248)
        #expect(place.displayName == "35.6812362, 139.7671248")
    }
}
