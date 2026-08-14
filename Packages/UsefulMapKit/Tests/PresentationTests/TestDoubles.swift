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

final class FakeRouteService: RouteProviding, @unchecked Sendable {
    /// モードごとの応答。未設定のモードは `defaultError` を投げる。
    var responses: [TransportMode: [RouteOption]] = [:]
    var errors: [TransportMode: RouteError] = [:]
    var delay: Duration = .zero
    private(set) var receivedQueries: [RouteQuery] = []
    private(set) var receivedOrigins: [Place] = []

    func routes(for query: RouteQuery, resolvedOrigin: Place) async throws -> [RouteOption] {
        receivedQueries.append(query)
        receivedOrigins.append(resolvedOrigin)
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        if let error = errors[query.transportMode] { throw error }
        return responses[query.transportMode] ?? []
    }

    static func option(_ mode: TransportMode,
                       minutes: Double,
                       query: RouteQuery,
                       origin: Place = Place(name: "現在地",
                                             coordinate: TestFixtures.currentLocation),
                       departure: Date? = nil,
                       arrival: Date? = nil) -> RouteOption {
        RouteOption(id: "\(mode.rawValue)-0",
                    query: query,
                    origin: origin,
                    mode: mode,
                    expectedTravelTime: minutes * 60,
                    departureDate: departure,
                    arrivalDate: arrival,
                    distance: 1_000)
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

@MainActor
enum TestEnvironment {
    static func make(search: FakeSearchService = FakeSearchService(),
                     routes: FakeRouteService = FakeRouteService(),
                     location: FakeLocationService = FakeLocationService(),
                     detail: FakeDetailLinking = FakeDetailLinking(),
                     store: FakeStore = FakeStore(),
                     debounce: Duration = .zero) -> AppDependencies {
        AppDependencies(searchService: search,
                        routeService: routes,
                        locationService: location,
                        detailLinking: detail,
                        store: store,
                        now: { TestFixtures.now },
                        searchDebounce: debounce)
    }
}
