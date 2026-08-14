import Foundation
import Testing

@testable import Domain

@Suite("RouteComparator")
struct RouteComparatorTests {
    private let origin = Place(name: "現在地", latitude: 35.6993, longitude: 139.7649)
    private let tokyo = Place(name: "東京駅", latitude: 35.6812362, longitude: 139.7671248)

    private func option(_ id: String,
                        mode: TransportMode,
                        minutes: Double,
                        departure: Date? = nil) -> RouteOption {
        RouteOption(id: id,
                    query: RouteQuery(destination: tokyo, transportMode: mode),
                    origin: origin,
                    mode: mode,
                    expectedTravelTime: minutes * 60,
                    departureDate: departure)
    }

    @Test("所要時間の短い順に並ぶ")
    func sortsByTravelTime() {
        let sorted = RouteComparator.sorted([
            option("walk", mode: .walking, minutes: 62),
            option("transit", mode: .transit, minutes: 22),
            option("drive", mode: .driving, minutes: 26)
        ])
        #expect(sorted.map(\.id) == ["transit", "drive", "walk"])
    }

    @Test("同じ所要時間なら出発が早い方が先")
    func tieBreaksByDeparture() {
        let early = option("early", mode: .transit, minutes: 22,
                           departure: TestDates.make(2026, 8, 14, 10, 32))
        let late = option("late", mode: .transit, minutes: 22,
                          departure: TestDates.make(2026, 8, 14, 10, 40))
        #expect(RouteComparator.sorted([late, early]).map(\.id) == ["early", "late"])
    }

    @Test("出発時刻が無い候補は、ある候補より後ろに置く")
    func tieBreaksWithMissingDeparture() {
        let known = option("known", mode: .transit, minutes: 22,
                           departure: TestDates.make(2026, 8, 14, 10, 32))
        let unknown = option("unknown", mode: .transit, minutes: 22)
        #expect(RouteComparator.sorted([unknown, known]).map(\.id) == ["known", "unknown"])
    }

    @Test("完全に同条件ならモード順（公共交通→徒歩→車）で決定的に並ぶ")
    func tieBreaksByMode() {
        let sorted = RouteComparator.sorted([
            option("d", mode: .driving, minutes: 30),
            option("w", mode: .walking, minutes: 30),
            option("t", mode: .transit, minutes: 30)
        ])
        #expect(sorted.map(\.id) == ["t", "w", "d"])
    }

    @Test("おすすめは所要時間が最短の候補")
    func recommended() {
        let options = [
            option("walk", mode: .walking, minutes: 62),
            option("transit", mode: .transit, minutes: 22)
        ]
        #expect(RouteComparator.recommended(options)?.id == "transit")
        #expect(RouteComparator.recommended([]) == nil)
    }

    @Test("モード別グループは 公共交通 → 徒歩 → 車 の固定順、空モードは含めない")
    func grouping() {
        let grouped = RouteComparator.groupedByMode([
            option("d", mode: .driving, minutes: 26),
            option("t2", mode: .transit, minutes: 30),
            option("t1", mode: .transit, minutes: 22)
        ])
        #expect(grouped.map(\.mode) == [.transit, .driving])
        #expect(grouped[0].options.map(\.id) == ["t1", "t2"])
    }

    @Test("並べ替えは元の配列順に依存しない（決定的である）")
    func stableRegardlessOfInputOrder() {
        let options = [
            option("a", mode: .transit, minutes: 22),
            option("b", mode: .walking, minutes: 22),
            option("c", mode: .driving, minutes: 10)
        ]
        #expect(RouteComparator.sorted(options).map(\.id)
                == RouteComparator.sorted(options.reversed()).map(\.id))
    }
}
