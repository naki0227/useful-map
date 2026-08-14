import Domain
import Foundation

/// S04 経路比較 / S05 経路編集。
///
/// 表示するのは所要時間（+ 公共交通は出発 / 到着時刻）だけで、運賃・乗換回数は扱わない（仕様書 6）。
@MainActor
public final class RouteCompareViewModel: ObservableObject {
    /// 比較タブ。`.all` は全モード横断比較（モックの「最適」）。
    public enum ModeFilter: Hashable, Identifiable {
        case all
        case mode(TransportMode)

        public var id: String {
            switch self {
            case .all: return "all"
            case let .mode(mode): return mode.rawValue
            }
        }

        public var displayName: String {
            switch self {
            case .all: return "最適"
            case let .mode(mode): return mode.displayName
            }
        }

        public var symbolName: String {
            switch self {
            case .all: return "sparkles"
            case let .mode(mode): return mode.symbolName
            }
        }

        public static let allCases: [ModeFilter] = [.all] + TransportMode.allCases.map(ModeFilter.mode)

        var modes: [TransportMode] {
            switch self {
            case .all: return TransportMode.allCases
            case let .mode(mode): return [mode]
            }
        }
    }

    @Published public private(set) var query: RouteQuery
    @Published public private(set) var options: [RouteOption] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var lastOpenOutcome: DetailOpenOutcome?
    /// 直近に開いた外部 URL（デバッグ表示と E2E 検証用）。
    @Published public private(set) var lastOpenedURL: String?
    @Published public var modeFilter: ModeFilter = .all {
        didSet {
            guard modeFilter != oldValue else { return }
            query.transportMode = modeFilter.modes.first ?? .transit
            load()
        }
    }

    private let routeService: RouteProviding
    private let locationService: LocationProviding
    private let detailLinking: RouteDetailLinking
    private let store: LocalStoring
    private let now: () -> Date

    private var loadTask: Task<Void, Never>?
    private var generation = 0

    public init(query: RouteQuery, dependencies: AppDependencies) {
        self.query = query
        self.modeFilter = .mode(query.transportMode)
        self.routeService = dependencies.routeService
        self.locationService = dependencies.locationService
        self.detailLinking = dependencies.detailLinking
        self.store = dependencies.store
        self.now = dependencies.now
    }

    deinit {
        loadTask?.cancel()
    }

    public var title: String {
        Formatters.routeTitle(origin: query.origin, destination: query.destination)
    }

    public var showsEmptyState: Bool {
        !isLoading && options.isEmpty && errorMessage == nil
    }

    public var recommendedID: RouteOption.ID? {
        RouteComparator.recommended(options)?.id
    }

    // MARK: - 取得

    @discardableResult
    public func load() -> Task<Void, Never> {
        loadTask?.cancel()
        generation += 1
        let currentGeneration = generation
        isLoading = true
        errorMessage = nil

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(generation: currentGeneration)
        }
        loadTask = task
        return task
    }

    private func performLoad(generation currentGeneration: Int) async {
        let requestedQuery = query
        let modes = modeFilter.modes

        let resolvedOrigin: Place
        do {
            resolvedOrigin = try await resolveOrigin(for: requestedQuery)
        } catch {
            guard currentGeneration == generation else { return }
            isLoading = false
            options = []
            errorMessage = "現在地を取得できませんでした。出発地を検索して指定してください"
            return
        }

        var collected: [RouteOption] = []
        var failures: [RouteError] = []

        for mode in modes {
            guard !Task.isCancelled else { return }
            var modeQuery = requestedQuery
            modeQuery.transportMode = mode
            do {
                let found = try await routeService.routes(for: modeQuery, resolvedOrigin: resolvedOrigin)
                collected += found
            } catch let error as RouteError {
                if case .cancelled = error { return }
                failures.append(error)
            } catch {
                failures.append(.failed(error.localizedDescription))
            }
        }

        guard currentGeneration == generation, !Task.isCancelled else { return }

        isLoading = false
        options = RouteComparator.sorted(collected)

        if collected.isEmpty {
            // 全モードが失敗した場合だけエラーを出す。一部モードだけ非対応なら比較は継続する。
            errorMessage = failures.first?.localizedMessage ?? RouteError.noRoutesFound.localizedMessage
        } else {
            errorMessage = nil
            store.recordRoute(origin: requestedQuery.origin,
                              destination: requestedQuery.destination,
                              transportMode: requestedQuery.transportMode,
                              at: now())
        }
    }

    private func resolveOrigin(for query: RouteQuery) async throws -> Place {
        switch query.origin {
        case let .place(place):
            return place
        case .currentLocation:
            let coordinate = try await locationService.currentCoordinate()
            return Place(name: "現在地", coordinate: coordinate)
        }
    }

    // MARK: - 外部詳細遷移

    /// 公共交通候補の「詳細」。Primary → 失敗時 official の順で Google Maps を開く。
    public func openDetail(for option: RouteOption) async {
        guard option.supportsExternalDetail else { return }
        let outcome = await detailLinking.open(option)
        lastOpenOutcome = outcome
        switch outcome {
        case .openedPrimary:
            lastOpenedURL = detailLinking.primaryURL(for: option)?.absoluteString
        case .openedFallback:
            lastOpenedURL = detailLinking.officialURL(for: option)?.absoluteString
        case .failed:
            lastOpenedURL = nil
            errorMessage = "Google Maps を開けませんでした"
        }
    }

    // MARK: - 経路編集（S05）

    public func setOrigin(_ endpoint: RouteEndpoint) {
        query.origin = endpoint
        load()
    }

    public func setDestination(_ place: Place) {
        query.destination = place
        load()
    }

    public func addWaypoint(_ place: Place) {
        query.addWaypoint(place)
        load()
    }

    public func removeWaypoint(id: Place.ID) {
        query.removeWaypoint(id: id)
        load()
    }

    public func moveWaypoints(fromOffsets source: IndexSet, toOffset destination: Int) {
        query.moveWaypoints(fromOffsets: source, toOffset: destination)
        load()
    }

    public func swapEndpoints() {
        let resolved = options.first?.origin
        query.swapOriginAndDestination(resolvedCurrentLocation: resolved)
        load()
    }

    public func setTimePreference(_ preference: TimePreference, date: Date?) {
        query.timePreference = preference
        query.requestedDate = preference.requiresDate ? (date ?? now()) : nil
        load()
    }
}
