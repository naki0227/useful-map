#if DEBUG
import Data
import Domain
import Foundation
import Presentation

/// E2E（XCUITest）用の決定的な環境。
/// 起動引数 `-UITestMode` で有効になり、MapKit / Core Location / 外部遷移をスタブへ差し替える。
/// 本番ビルド（Release）には含まれない。
enum UITestConfiguration {
    enum Scenario: String {
        /// 通常。公共交通・徒歩・車の候補が返る。
        case standard
        /// 経路 0 件。
        case noRoutes
        /// 時刻付き Primary URL が開けず、公式 URL へ fallback する。
        case primaryURLBroken
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestMode")
    }

    static var scenario: Scenario {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-UITestScenario"),
              index + 1 < arguments.count,
              let scenario = Scenario(rawValue: arguments[index + 1]) else {
            return .standard
        }
        return scenario
    }

    /// 固定時刻 2026-08-14 10:00 (JST)。
    static let fixedNow: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Fixtures.timeZone
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 10, minute: 0)) ?? Date()
    }()

    static func makeDependencies() -> AppDependencies {
        let opener = StubURLOpener(rejectsPrimary: scenario == .primaryURLBroken)
        return AppDependencies(searchService: StubPlaceSearchService(),
                               routeService: StubRouteService(scenario: scenario, now: fixedNow),
                               locationService: StubLocationService(),
                               detailLinking: GoogleMapsURLBuilder(timeZone: Fixtures.timeZone, opener: opener),
                               store: InMemoryLocalStore(),
                               now: { fixedNow },
                               // デバウンス待ちで E2E が不安定になるのを避ける。
                               searchDebounce: .zero)
    }

    enum Fixtures {
        static let timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current

        static let currentLocation = Coordinate(latitude: 35.6993, longitude: 139.7649)

        static let tokyoStation = Place(name: "東京駅",
                                        latitude: 35.6812362,
                                        longitude: 139.7671248,
                                        address: "東京都千代田区丸の内1丁目9")
        static let yaesu = Place(name: "東京駅 八重洲口",
                                 latitude: 35.6809,
                                 longitude: 139.7690,
                                 address: "東京都中央区八重洲2丁目1")
        static let shinjukuGyoen = Place(name: "新宿御苑",
                                         latitude: 35.6852,
                                         longitude: 139.7100,
                                         address: "東京都新宿区内藤町11")
    }
}

// MARK: - スタブ

struct StubPlaceSearchService: PlaceSearching {
    func search(query: String, around: Coordinate?) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.contains("ありえない") { return [] }
        let all = [UITestConfiguration.Fixtures.tokyoStation,
                   UITestConfiguration.Fixtures.yaesu,
                   UITestConfiguration.Fixtures.shinjukuGyoen]
        let matched = all.filter { $0.name.contains(trimmed) }
        return matched.isEmpty ? all : matched
    }
}

struct StubRouteService: RouteProviding {
    let scenario: UITestConfiguration.Scenario
    let now: Date

    func routes(for query: RouteQuery, resolvedOrigin: Place) async throws -> [RouteOption] {
        if scenario == .noRoutes { throw RouteError.noRoutesFound }

        switch query.transportMode {
        case .transit:
            // 10:32 発 → 10:54 着（22 分）
            let departure = now.addingTimeInterval(32 * 60)
            return [RouteOption(id: "transit-0",
                                query: query,
                                origin: resolvedOrigin,
                                mode: .transit,
                                expectedTravelTime: 22 * 60,
                                departureDate: departure,
                                arrivalDate: departure.addingTimeInterval(22 * 60),
                                distance: 6_200)]
        case .walking:
            return [RouteOption(id: "walking-0",
                                query: query,
                                origin: resolvedOrigin,
                                mode: .walking,
                                expectedTravelTime: 62 * 60,
                                distance: 4_800,
                                geometry: [resolvedOrigin.coordinate, query.destination.coordinate])]
        case .driving:
            return [RouteOption(id: "driving-0",
                                query: query,
                                origin: resolvedOrigin,
                                mode: .driving,
                                expectedTravelTime: 26 * 60,
                                distance: 7_100,
                                geometry: [resolvedOrigin.coordinate, query.destination.coordinate])]
        }
    }
}

final class StubLocationService: LocationProviding {
    var authorizationStatus: LocationAuthorizationStatus { .authorized }
    func requestAuthorization() {}
    func currentCoordinate() async throws -> Coordinate {
        UITestConfiguration.Fixtures.currentLocation
    }
}

/// 実際には遷移せず、開こうとした URL を記録するだけの opener。
/// E2E をシミュレータ内で完結させ、生成 URL をそのまま検証できるようにする。
final class StubURLOpener: URLOpening, @unchecked Sendable {
    private let rejectsPrimary: Bool
    private(set) var openedURLs: [URL] = []

    init(rejectsPrimary: Bool) {
        self.rejectsPrimary = rejectsPrimary
    }

    func open(_ url: URL) async -> Bool {
        // 時刻付き内部 URL は data= を含む。壊れたシナリオではこれを開けない扱いにする。
        if rejectsPrimary, url.absoluteString.contains("/data=") { return false }
        openedURLs.append(url)
        return true
    }
}
#endif
