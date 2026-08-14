import Foundation
import Testing

@testable import Domain

@Suite("RouteQuery")
struct RouteQueryTests {
    private let tokyo = Place(name: "東京駅", latitude: 35.6812362, longitude: 139.7671248)
    private let shinjuku = Place(name: "新宿御苑", latitude: 35.6852, longitude: 139.7100)
    private let shibuya = Place(name: "渋谷スクランブルスクエア", latitude: 35.6580, longitude: 139.7016)

    @Test("既定は現在地出発・公共交通・現在時刻")
    func defaults() {
        let query = RouteQuery(destination: tokyo)
        #expect(query.origin == .currentLocation)
        #expect(query.transportMode == .transit)
        #expect(query.timePreference == .now)
        #expect(query.effectiveDate == nil)
        #expect(query.isValid)
    }

    @Test(".now では requestedDate があっても時刻条件として扱わない")
    func effectiveDateIgnoredForNow() {
        var query = RouteQuery(destination: tokyo)
        query.requestedDate = TestDates.make(2026, 8, 14, 10, 32)
        #expect(query.effectiveDate == nil)

        query.timePreference = .departAt
        #expect(query.effectiveDate == TestDates.make(2026, 8, 14, 10, 32))
    }

    @Test("時刻指定なのに日時が無い条件は不正")
    func requiresDateWhenScheduled() {
        var query = RouteQuery(destination: tokyo, timePreference: .arriveBy)
        #expect(!query.isValid)
        query.requestedDate = TestDates.make(2026, 8, 14, 11, 0)
        #expect(query.isValid)
    }

    @Test("座標が壊れた地点を含む条件は不正")
    func rejectsBrokenPlaces() {
        let broken = Place(name: "壊れた地点", latitude: 0, longitude: 0)
        #expect(!RouteQuery(destination: broken).isValid)
        #expect(!RouteQuery(origin: .place(broken), destination: tokyo).isValid)
        #expect(!RouteQuery(destination: tokyo, waypoints: [broken]).isValid)
    }

    @Test("経由地は追加・重複排除・削除できる")
    func waypointEditing() {
        var query = RouteQuery(destination: tokyo)
        query.addWaypoint(shinjuku)
        query.addWaypoint(shinjuku)
        #expect(query.waypoints.count == 1)

        query.addWaypoint(shibuya)
        #expect(query.waypoints.map(\.name) == ["新宿御苑", "渋谷スクランブルスクエア"])

        query.removeWaypoint(id: shinjuku.id)
        #expect(query.waypoints.map(\.name) == ["渋谷スクランブルスクエア"])
    }

    @Test("経由地の並べ替えは SwiftUI の onMove と同じ意味論")
    func waypointReordering() {
        var query = RouteQuery(destination: tokyo, waypoints: [shinjuku, shibuya])
        query.moveWaypoints(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(query.waypoints.map(\.name) == ["渋谷スクランブルスクエア", "新宿御苑"])

        query.moveWaypoints(fromOffsets: IndexSet(integer: 0), toOffset: 2)
        #expect(query.waypoints.map(\.name) == ["新宿御苑", "渋谷スクランブルスクエア"])
    }

    @Test("範囲外の並べ替え指定は無視する")
    func waypointReorderingOutOfRange() {
        var query = RouteQuery(destination: tokyo, waypoints: [shinjuku])
        query.moveWaypoints(fromOffsets: IndexSet(integer: 5), toOffset: 0)
        query.moveWaypoints(fromOffsets: IndexSet(integer: 0), toOffset: 9)
        #expect(query.waypoints.map(\.name) == ["新宿御苑"])
    }

    @Test("地点出発なら出発地と目的地を入れ替えられる")
    func swapWithPlaceOrigin() {
        var query = RouteQuery(origin: .place(shinjuku), destination: tokyo, waypoints: [shibuya])
        query.swapOriginAndDestination()
        #expect(query.origin == .place(tokyo))
        #expect(query.destination == shinjuku)
        #expect(query.waypoints == [shibuya])
    }

    @Test("現在地出発は解決済み地点が無いと入れ替えない")
    func swapWithCurrentLocation() {
        var query = RouteQuery(origin: .currentLocation, destination: tokyo)
        query.swapOriginAndDestination()
        #expect(query.origin == .currentLocation)
        #expect(query.destination == tokyo)

        let resolved = Place(name: "現在地", latitude: 35.6993, longitude: 139.7649)
        query.swapOriginAndDestination(resolvedCurrentLocation: resolved)
        #expect(query.origin == .place(tokyo))
        #expect(query.destination == resolved)
    }

    @Test("経路計算に渡す地点列は 出発地 → 経由地 → 目的地 の順")
    func orderedPlaces() {
        let query = RouteQuery(destination: tokyo, waypoints: [shinjuku, shibuya])
        let origin = Place(name: "現在地", latitude: 35.6993, longitude: 139.7649)
        #expect(query.orderedPlaces(resolvedOrigin: origin).map(\.name)
                == ["現在地", "新宿御苑", "渋谷スクランブルスクエア", "東京駅"])
    }

    @Test("Codable で往復しても条件が壊れない")
    func codableRoundTrip() throws {
        let query = RouteQuery(origin: .place(shinjuku),
                               destination: tokyo,
                               waypoints: [shibuya],
                               transportMode: .driving,
                               timePreference: .arriveBy,
                               requestedDate: TestDates.make(2026, 8, 14, 11, 30))
        let data = try JSONEncoder().encode(query)
        #expect(try JSONDecoder().decode(RouteQuery.self, from: data) == query)
    }

    @Test("RouteEndpoint の表示名")
    func endpointDisplayName() {
        // 地点名は翻訳せずそのまま出す。現在地はロケールに応じて訳される。
        #expect(RouteEndpoint.place(tokyo).displayName == "東京駅")
        #expect(!RouteEndpoint.currentLocation.displayName.isEmpty)
        #expect(RouteEndpoint.currentLocation.place == nil)
        #expect(RouteEndpoint.place(tokyo).place == tokyo)
        #expect(RouteEndpoint.currentLocation.isCurrentLocation)
    }

    @Test("TimePreference の日時要否")
    func timePreferenceRequirements() {
        #expect(!TimePreference.now.requiresDate)
        #expect(TimePreference.departAt.requiresDate)
        #expect(TimePreference.arriveBy.requiresDate)
    }
}
