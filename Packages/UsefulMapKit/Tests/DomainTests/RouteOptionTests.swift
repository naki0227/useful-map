import Foundation
import Testing

@testable import Domain

@Suite("RouteOption")
struct RouteOptionTests {
    private let origin = Place(name: "現在地", latitude: 35.6993, longitude: 139.7649)
    private let tokyo = Place(name: "東京駅", latitude: 35.6812362, longitude: 139.7671248)

    private func option(timePreference: TimePreference,
                        requestedDate: Date? = nil,
                        departure: Date? = nil,
                        arrival: Date? = nil,
                        mode: TransportMode = .transit) -> RouteOption {
        let query = RouteQuery(destination: tokyo,
                               transportMode: mode,
                               timePreference: timePreference,
                               requestedDate: requestedDate)
        return RouteOption(query: query,
                           origin: origin,
                           mode: mode,
                           expectedTravelTime: 22 * 60,
                           departureDate: departure,
                           arrivalDate: arrival)
    }

    @Test(".now は取得できた出発時刻を基準にする")
    func anchorForNow() {
        let departure = TestDates.make(2026, 8, 14, 10, 32)
        let anchor = option(timePreference: .now, departure: departure).timeAnchor
        #expect(anchor?.kind == .depart)
        #expect(anchor?.date == departure)
    }

    @Test(".now で出発時刻が取れなければ時刻付き URL を作らない")
    func anchorForNowWithoutDeparture() {
        #expect(option(timePreference: .now).timeAnchor == nil)
    }

    @Test(".departAt は出発時刻、無ければ指定日時を使う")
    func anchorForDepartAt() {
        let requested = TestDates.make(2026, 8, 14, 9, 0)
        let departure = TestDates.make(2026, 8, 14, 10, 32)

        let withDeparture = option(timePreference: .departAt, requestedDate: requested, departure: departure)
        #expect(withDeparture.timeAnchor == TimeAnchor(kind: .depart, date: departure))

        let withoutDeparture = option(timePreference: .departAt, requestedDate: requested)
        #expect(withoutDeparture.timeAnchor == TimeAnchor(kind: .depart, date: requested))
    }

    @Test(".arriveBy は到着時刻、無ければ指定日時を使う")
    func anchorForArriveBy() {
        let requested = TestDates.make(2026, 8, 14, 11, 0)
        let arrival = TestDates.make(2026, 8, 14, 10, 54)

        let withArrival = option(timePreference: .arriveBy, requestedDate: requested, arrival: arrival)
        #expect(withArrival.timeAnchor == TimeAnchor(kind: .arrive, date: arrival))

        let withoutArrival = option(timePreference: .arriveBy, requestedDate: requested)
        #expect(withoutArrival.timeAnchor == TimeAnchor(kind: .arrive, date: requested))
    }

    @Test("時刻がまったく無ければ anchor は nil（公式 URL へ fallback する条件）")
    func anchorMissing() {
        #expect(option(timePreference: .arriveBy).timeAnchor == nil)
        #expect(option(timePreference: .departAt).timeAnchor == nil)
    }

    @Test("外部詳細を出すのは公共交通だけ")
    func externalDetail() {
        #expect(option(timePreference: .now, mode: .transit).supportsExternalDetail)
        #expect(!option(timePreference: .now, mode: .walking).supportsExternalDetail)
        #expect(!option(timePreference: .now, mode: .driving).supportsExternalDetail)
    }

    @Test("出発・到着が揃って初めて時刻レンジを表示できる")
    func scheduledTimes() {
        let departure = TestDates.make(2026, 8, 14, 10, 32)
        let arrival = TestDates.make(2026, 8, 14, 10, 54)
        #expect(option(timePreference: .now, departure: departure, arrival: arrival).hasScheduledTimes)
        #expect(!option(timePreference: .now, departure: departure).hasScheduledTimes)
        #expect(!option(timePreference: .now, arrival: arrival).hasScheduledTimes)
    }

    @Test("地点列は条件の経由地を含む")
    func orderedPlaces() {
        let waypoint = Place(name: "新宿御苑", latitude: 35.6852, longitude: 139.7100)
        let query = RouteQuery(destination: tokyo, waypoints: [waypoint])
        let option = RouteOption(query: query, origin: origin, mode: .transit, expectedTravelTime: 600)
        #expect(option.orderedPlaces.map(\.name) == ["現在地", "新宿御苑", "東京駅"])
        #expect(option.destination == tokyo)
        #expect(option.waypoints == [waypoint])
    }
}
