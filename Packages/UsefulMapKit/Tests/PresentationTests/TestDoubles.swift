import Domain
import Foundation

@testable import Presentation

// Presentation のテストは Domain のポートだけを差し替える。
// （Data / Infrastructure に依存しないことでレイヤ境界をテスト側でも守る）

enum TestFixtures {
    static let timeZone = TimeZone(identifier: "Asia/Tokyo")!

    static let currentLocation = Coordinate(latitude: 35.6993, longitude: 139.7649)
    static let tokyo = Place(name: "東京駅", latitude: 35.6812362, longitude: 139.7671248,
                             address: "東京都千代田区丸の内1丁目9")
    static let shinjuku = Place(name: "新宿御苑", latitude: 35.6852, longitude: 139.7100)
    static let shibuya = Place(name: "渋谷スクランブルスクエア", latitude: 35.6580, longitude: 139.7016)

    static func date(_ hour: Int, _ minute: Int = 0, day: Int = 14) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: day,
                                                  hour: hour, minute: minute))!
    }

    static let now = date(10)
}

final class FakeSearchService: PlaceSearching, @unchecked Sendable {
    var results: [Place]
    var error: PlaceSearchError?
    /// 応答を遅らせて、キャンセルや順序入れ替わりを再現する。
    var delay: Duration = .zero
    private(set) var receivedQueries: [String] = []
    private(set) var receivedCenters: [Coordinate?] = []

    init(results: [Place] = [TestFixtures.tokyo], error: PlaceSearchError? = nil) {
        self.results = results
        self.error = error
    }

    func search(query: String, around center: Coordinate?) async throws -> [Place] {
        receivedQueries.append(query)
        receivedCenters.append(center)
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        try Task.checkCancellation()
        if let error { throw error }
        return results
    }
}

final class FakeLocationService: LocationProviding, @unchecked Sendable {
    var authorizationStatus: LocationAuthorizationStatus
    var coordinate: Coordinate?
    var error: LocationError?
    private(set) var authorizationRequestCount = 0

    init(authorizationStatus: LocationAuthorizationStatus = .authorized,
         coordinate: Coordinate? = TestFixtures.currentLocation,
         error: LocationError? = nil) {
        self.authorizationStatus = authorizationStatus
        self.coordinate = coordinate
        self.error = error
    }

    func requestAuthorization() {
        authorizationRequestCount += 1
    }

    func currentCoordinate() async throws -> Coordinate {
        if let error { throw error }
        guard let coordinate else { throw LocationError.unavailable }
        return coordinate
    }
}

final class FakeDetailLinking: RouteDetailLinking, @unchecked Sendable {
    var outcome: DetailOpenOutcome = .openedPrimary
    var primary: URL? = URL(string: "https://www.google.com/maps/dir/A/B/data=!4m18!3e3")
    var official: URL? = URL(string: "https://www.google.com/maps/dir/?api=1&travelmode=transit")
    private(set) var openedOptions: [RouteOption] = []

    func primaryURL(for option: RouteOption) -> URL? { primary }
    func officialURL(for option: RouteOption) -> URL? { official }

    func open(_ option: RouteOption) async -> DetailOpenOutcome {
        openedOptions.append(option)
        return outcome
    }
}

final class FakeStore: LocalStoring {
    private(set) var savedPlaces: [SavedPlace] = []
    private(set) var recentSearches: [RecentSearch] = []
    private(set) var recentRoutes: [RecentRoute] = []

    func savePlace(_ place: Place, label: SavedPlace.Label, at date: Date) {
        savedPlaces.removeAll { $0.id == place.id }
        savedPlaces.insert(SavedPlace(place: place, label: label, savedAt: date), at: 0)
    }

    func removeSavedPlace(id: SavedPlace.ID) {
        savedPlaces.removeAll { $0.id == id }
    }

    func isSaved(_ place: Place) -> Bool {
        savedPlaces.contains { $0.id == place.id }
    }

    func recordSearch(_ place: Place, at date: Date) {
        recentSearches.removeAll { $0.id == place.id }
        recentSearches.insert(RecentSearch(place: place, searchedAt: date), at: 0)
    }

    func recordRoute(origin: RouteEndpoint, destination: Place, transportMode: TransportMode, at date: Date) {
        let entry = RecentRoute(origin: origin, destination: destination,
                                transportMode: transportMode, usedAt: date)
        recentRoutes.removeAll { $0.id == entry.id }
        recentRoutes.insert(entry, at: 0)
    }

    func clearHistory() {
        recentSearches = []
        recentRoutes = []
    }
}

/// 座標をそのまま地点にする逆引き（地図タップのテスト用）。
struct FakePlaceResolver: PlaceResolving {
    var name = "選んだ地点"
    func place(at coordinate: Coordinate) async -> Place {
        Place(name: name, coordinate: coordinate)
    }
}

/// 指定した座標の近くに停留所がある状況を作る。
final class FakeStopLocator: TransitStopLocating, @unchecked Sendable {
    var table: [(center: Coordinate, stops: [Place])] = []

    func stops(near coordinate: Coordinate, within meters: Double, limit: Int) async throws -> [Place] {
        let matched = table
            .filter { $0.center.distance(to: coordinate) <= meters }
            .flatMap(\.stops)
            .filter { $0.coordinate.distance(to: coordinate) <= meters }
        return Array(matched.prefix(limit))
    }
}

/// 停留所を返さない既定のロケータ（プラン分割を伴わないテスト用）。
struct EmptyStopLocator: TransitStopLocating {
    func stops(near coordinate: Coordinate, within meters: Double, limit: Int) async throws -> [Place] { [] }
}

/// 距離から所要時間を機械的に決める区間ルーティング。
/// MapKit と同じく、公共交通にだけ発着時刻を返す（徒歩・車は時刻を返さない）。
struct SimpleSegmentRouting: SegmentRouting {
    func leg(from: Place, to: Place, mode: TransportMode,
             timePreference: TimePreference, requestedDate: Date?) async throws -> RouteLeg {
        let distance = from.coordinate.distance(to: to.coordinate)
        let speed: Double = mode == .walking ? 1.2 : (mode == .transit ? 12 : 8)
        let duration = distance / speed
        guard mode == .transit else {
            return RouteLeg(expectedTravelTime: duration, distance: distance)
        }
        let departure = requestedDate ?? TestFixtures.now
        return RouteLeg(expectedTravelTime: duration,
                        departureDate: departure,
                        arrivalDate: departure.addingTimeInterval(duration),
                        distance: distance)
    }
}

@MainActor
enum TestEnvironment {
    static func make(search: FakeSearchService = FakeSearchService(),
                     planner: RoutePlanner = RoutePlanner(stops: EmptyStopLocator(),
                                                          routing: SimpleSegmentRouting()),
                     location: FakeLocationService = FakeLocationService(),
                     placeResolver: PlaceResolving = FakePlaceResolver(),
                     detail: FakeDetailLinking = FakeDetailLinking(),
                     store: FakeStore = FakeStore(),
                     debounce: Duration = .zero) -> AppDependencies {
        AppDependencies(searchService: search,
                        planner: planner,
                        locationService: location,
                        placeResolver: placeResolver,
                        detailLinking: detail,
                        store: store,
                        now: { TestFixtures.now },
                        searchDebounce: debounce)
    }
}
