import Domain
import Foundation

/// 経路プランの編集と取得。
///
/// 画面遷移を挟まずに、ノード（地点）と区間（移動手段）をその場で編集できるようにする。
/// 取得は編集のたびに走るため、直前のリクエストは破棄する。
@MainActor
public final class RoutePlanViewModel: ObservableObject {
    @Published public private(set) var plan: RoutePlan
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var lastOpenOutcome: DetailOpenOutcome?
    @Published public private(set) var lastOpenedURL: String?
    @Published public var walkingPace: WalkingPace = .normal {
        didSet {
            guard walkingPace != oldValue else { return }
            reload(recomputeAll: true)
        }
    }
    /// インライン編集中のノード。nil なら編集していない。
    @Published public var editingNodeIndex: Int?
    /// 経由地を追加するために、どの区間の途中を編集しているか。
    @Published public var addingWaypointAfterSegment: Int?
    /// 便を選び直している区間。
    @Published public var pickingDepartureAt: Int?

    private let planner: RoutePlanner
    private let locationService: LocationProviding
    private let detailLinking: RouteDetailLinking
    private let store: LocalStoring
    private let now: () -> Date

    private var loadTask: Task<Void, Never>?
    private var generation = 0

    public init(plan: RoutePlan, dependencies: AppDependencies) {
        self.plan = plan
        self.planner = dependencies.planner
        self.locationService = dependencies.locationService
        self.detailLinking = dependencies.detailLinking
        self.store = dependencies.store
        self.now = dependencies.now
    }

    deinit { loadTask?.cancel() }

    // MARK: - 取得

    @discardableResult
    public func reload(recomputeAll: Bool = false) -> Task<Void, Never> {
        loadTask?.cancel()
        generation += 1
        let currentGeneration = generation
        isLoading = true
        errorMessage = nil

        var target = plan
        if recomputeAll { target.clearLegs() }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(target, generation: currentGeneration)
        }
        loadTask = task
        return task
    }

    /// 現在地のノードは、取得のたびに実際の座標へ解決する。
    private func resolvedOriginNode(_ node: RouteNode) async -> RouteNode {
        guard node.isCurrentLocation else { return node }
        guard let coordinate = try? await locationService.currentCoordinate() else { return node }
        var resolved = node
        resolved.place = Place(name: RouteEndpoint.currentLocation.displayName, coordinate: coordinate)
        return resolved
    }

    private func recordHistory(for plan: RoutePlan) {
        store.recordRoute(origin: plan.origin.isCurrentLocation
                            ? .currentLocation
                            : .place(plan.origin.place),
                          destination: plan.destination.place,
                          transportMode: plan.modes.first ?? .transit,
                          at: now())
    }

    private func performLoad(_ target: RoutePlan, generation currentGeneration: Int) async {
        do {
            let configured = planner.withWalkingPace(walkingPace)
            // 区間を取り直したあと、常にノードを自動で振り分け直す。
            // ユーザーが決めた区間はロックされているので触られない。
            let computed = try await configured.refine(configured.computeLegs(target),
                                                       depth: RouteRefinementPolicy.default.maxDepth)
            guard currentGeneration == generation, !Task.isCancelled else { return }

            plan = computed
            isLoading = false
            if computed.segments.allSatisfy({ $0.leg == nil }) {
                errorMessage = RouteError.noRoutesFound.localizedMessage
            } else {
                errorMessage = nil
                recordHistory(for: computed)
            }
        } catch is CancellationError {
            return
        } catch {
            guard currentGeneration == generation else { return }
            isLoading = false
            errorMessage = (error as? RouteError)?.localizedMessage ?? error.localizedDescription
        }
    }

    /// 出発地・目的地から組み直す（駅の推定と再帰分割をやり直す）。
    @discardableResult
    public func rebuild(preset: TransportMode) -> Task<Void, Never> {
        loadTask?.cancel()
        generation += 1
        let currentGeneration = generation
        isLoading = true
        errorMessage = nil

        let origin = plan.origin
        let destination = plan.destination
        let timePreference = plan.timePreference
        let requestedDate = plan.requestedDate

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                // 現在地発なら、まず実際の座標を解決してから組み立てる。
                let resolvedOrigin = await self.resolvedOriginNode(origin)
                let rebuilt = try await self.planner
                    .withWalkingPace(self.walkingPace)
                    .makePlan(origin: resolvedOrigin,
                              destination: destination,
                              preset: preset,
                              timePreference: timePreference,
                              requestedDate: requestedDate)
                guard currentGeneration == self.generation, !Task.isCancelled else { return }
                self.plan = rebuilt
                self.isLoading = false
                // 1 区間も取れなければ、経路なしとして案内する。
                if rebuilt.segments.allSatisfy({ $0.leg == nil }) {
                    self.errorMessage = RouteError.noRoutesFound.localizedMessage
                } else {
                    self.errorMessage = nil
                    self.recordHistory(for: rebuilt)
                }
            } catch is CancellationError {
                return
            } catch {
                guard currentGeneration == self.generation else { return }
                self.isLoading = false
                self.errorMessage = (error as? RouteError)?.localizedMessage ?? error.localizedDescription
            }
        }
        loadTask = task
        return task
    }

    // MARK: - 編集（すべてその場で完結し、画面遷移を挟まない）

    /// 矢印のアイコンを押したときの区間モード切り替え。
    public func toggleMode(at index: Int) {
        plan.cycleMode(at: index)
        reload()
    }

    public func setMode(_ mode: TransportMode, at index: Int) {
        plan.setMode(mode, at: index)
        reload()
    }

    /// 上部タブのプリセット。
    public func applyPreset(_ preset: Preset) {
        rebuild(preset: preset.mode)
    }

    public func updatePlace(_ place: Place, at index: Int) {
        plan.updatePlace(place, at: index)
        editingNodeIndex = nil
        reload()
    }

    /// 区間の途中に経由地を足す。
    public func insertWaypoint(_ place: Place, afterSegment index: Int) {
        plan.insertNode(RouteNode(place: place, kind: .waypoint), afterSegment: index)
        addingWaypointAfterSegment = nil
        editingNodeIndex = nil
        reload()
    }

    /// 指定した区間の途中に経由地を足し始める。
    /// 既存のノードは隠さず、区間の間に新しい入力欄を差し込む。
    public func beginAddingWaypoint(afterSegment index: Int) {
        guard plan.segments.indices.contains(index) else { return }
        addingWaypointAfterSegment = index
        editingNodeIndex = nil
    }

    public func cancelAddingWaypoint() {
        addingWaypointAfterSegment = nil
    }

    /// 便の選び直しを始める。
    public func beginPickingDeparture(at index: Int) {
        let list = plan.segments
        guard list.indices.contains(index), list[index].mode == .transit else { return }
        pickingDepartureAt = index
    }

    public func cancelPickingDeparture() {
        pickingDepartureAt = nil
    }

    /// 差分の提案を受け入れる / 退ける。
    public func acceptUpdate(at index: Int) {
        plan.acceptUpdate(at: index)
    }

    public func dismissUpdate(at index: Int) {
        plan.dismissUpdate(at: index)
    }

    /// 編集中のノードへ地点を反映する。経由地の追加中なら挿入する。
    public func commitPlace(_ place: Place, at index: Int) {
        if let segment = addingWaypointAfterSegment {
            insertWaypoint(place, afterSegment: segment)
        } else {
            updatePlace(place, at: index)
        }
    }

    /// ノードを外す。
    ///
    /// 自動で推定した駅を外した場合は「ここは通らない」という意思表示なので、
    /// 統合後の区間をロックして再推定の対象から外す。
    /// ユーザーが足した経由地を外した場合はロックせず、自動推定に戻す。
    public func removeNode(at index: Int) {
        let wasInferred = plan.nodes[safeIndex: index]?.isInferred ?? false
        plan.removeNode(at: index)
        if wasInferred, index > 0 {
            plan.lockSegment(at: index - 1)
        }
        reload()
    }

    /// 出発地と目的地の入れ替え（ワンボタン）。
    public func swapEndpoints() {
        plan.reverse()
        reload(recomputeAll: true)
    }

    /// 出発地を現在地にする（ワンボタン）。
    @discardableResult
    public func useCurrentLocation(at index: Int = 0) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            do {
                let coordinate = try await self.locationService.currentCoordinate()
                let place = Place(name: RouteEndpoint.currentLocation.displayName, coordinate: coordinate)
                self.plan.setCurrentLocation(place, at: index)
                self.editingNodeIndex = nil
                await self.reload().value
            } catch {
                self.errorMessage = L10n.string("route.error.location")
            }
        }
    }

    /// 徒歩ペースをボタン 1 つで切り替える。
    public func cycleWalkingPace() {
        walkingPace = walkingPace.next
    }

    /// 便を選び直す（駅は同じまま時刻だけ変える）。前後の区間は取り直す。
    @discardableResult
    public func pinTime(_ anchor: TimeAnchor, at index: Int) -> Task<Void, Never> {
        loadTask?.cancel()
        generation += 1
        let currentGeneration = generation
        isLoading = true

        let target = plan
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await self.planner
                    .withWalkingPace(self.walkingPace)
                    .applyPin(anchor, at: index, to: target)
                guard currentGeneration == self.generation, !Task.isCancelled else { return }
                self.plan = updated
                self.isLoading = false
            } catch {
                guard currentGeneration == self.generation else { return }
                self.isLoading = false
            }
        }
        loadTask = task
        return task
    }

    public func clearPin() {
        plan.clearPin()
        reload(recomputeAll: true)
    }

    public func setTimePreference(_ preference: TimePreference, date: Date?) {
        plan.timePreference = preference
        plan.requestedDate = preference.requiresDate ? (date ?? now()) : nil
        plan.clearPin()
        reload(recomputeAll: true)
    }

    // MARK: - 外部詳細遷移

    /// 指定した区間を Google Maps へ委譲する。
    public func openDetail(at index: Int) async {
        guard let option = detailOption(at: index) else { return }
        let outcome = await detailLinking.open(option)
        lastOpenOutcome = outcome
        switch outcome {
        case .openedPrimary:
            lastOpenedURL = detailLinking.primaryURL(for: option)?.absoluteString
        case .openedFallback:
            lastOpenedURL = detailLinking.officialURL(for: option)?.absoluteString
        case .failed:
            lastOpenedURL = nil
            errorMessage = L10n.string("route.open.failed")
        }
    }

    /// 区間を Google Maps へ渡すための表現へ変換する。
    ///
    /// 区間は 2 地点なので経由地を持たない。時刻はその区間の発着時刻を使うため、
    /// 「この電車の詳細」をそのまま開ける。
    func detailOption(at index: Int) -> RouteOption? {
        let list = plan.segments
        guard list.indices.contains(index) else { return nil }
        let segment = list[index]
        let entry = schedule[safeIndex: index].flatMap { $0 }

        let query = RouteQuery(origin: segment.from.isCurrentLocation
                                ? .currentLocation
                                : .place(segment.from.place),
                               destination: segment.to.place,
                               transportMode: segment.mode,
                               timePreference: entry == nil ? plan.timePreference : .departAt,
                               requestedDate: entry?.departure ?? plan.requestedDate)
        return RouteOption(id: "segment-\(index)",
                           query: query,
                           origin: segment.from.place,
                           mode: segment.mode,
                           expectedTravelTime: segment.leg?.expectedTravelTime ?? 0,
                           departureDate: entry?.departure ?? segment.leg?.departureDate,
                           arrivalDate: entry?.arrival ?? segment.leg?.arrivalDate,
                           distance: segment.leg?.distance,
                           geometry: segment.leg?.geometry ?? [])
    }
}

extension Array {
    /// 範囲外でも落ちない添字アクセス。
    subscript(safeIndex index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
