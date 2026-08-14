import Foundation

/// 経路上の 1 地点。出発地・駅・経由地・目的地を同じ型で扱う。
public struct RouteNode: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case origin
        case station
        case waypoint
        case destination
    }

    public var place: Place
    public var kind: Kind
    /// 現在地から解決したノードか（表示を「現在地」に保つために使う）。
    public var isCurrentLocation: Bool
    /// 最寄駅として自動推定したノードか。ユーザーが選び直したら false になる。
    public var isInferred: Bool

    public init(place: Place,
                kind: Kind,
                isCurrentLocation: Bool = false,
                isInferred: Bool = false) {
        self.place = place
        self.kind = kind
        self.isCurrentLocation = isCurrentLocation
        self.isInferred = isInferred
    }

    public var id: String { "\(kind.rawValue):\(place.id)" }

    public var displayName: String { place.displayName }
}

/// ノード間の 1 区間。移動手段は区間ごとに持つ。
public struct RouteSegment: Identifiable, Hashable, Sendable {
    public let from: RouteNode
    public let to: RouteNode
    public var mode: TransportMode
    /// 取得済みの実績値（未取得なら nil）。
    public var leg: RouteLeg?

    public init(from: RouteNode, to: RouteNode, mode: TransportMode, leg: RouteLeg? = nil) {
        self.from = from
        self.to = to
        self.mode = mode
        self.leg = leg
    }

    public var id: String { "\(from.id)->\(to.id)" }
}

/// 区間の計算結果。
public struct RouteLeg: Hashable, Sendable {
    public let expectedTravelTime: TimeInterval
    public let departureDate: Date?
    public let arrivalDate: Date?
    public let distance: Double?
    public let geometry: [Coordinate]

    public init(expectedTravelTime: TimeInterval,
                departureDate: Date? = nil,
                arrivalDate: Date? = nil,
                distance: Double? = nil,
                geometry: [Coordinate] = []) {
        self.expectedTravelTime = expectedTravelTime
        self.departureDate = departureDate
        self.arrivalDate = arrivalDate
        self.distance = distance
        self.geometry = geometry
    }
}

/// 経路プラン。ノード列と、その間の移動手段を持つ。
///
/// `現在地 →徒歩→ 最寄駅 →電車→ 到着駅 →徒歩→ 目的地` のように、
/// 区間ごとに移動手段を変えられる。MapKit は公共交通の乗車駅を返さないため、
/// 駅ノードはアプリ側で推定して差し込み、ユーザーが選び直せるようにしている。
public struct RoutePlan: Hashable, Sendable {
    public private(set) var nodes: [RouteNode]
    /// 区間ごとの移動手段。常に `nodes.count - 1` 個。
    public private(set) var modes: [TransportMode]
    public var timePreference: TimePreference
    public var requestedDate: Date?
    /// 取得済みの区間結果（`modes` と同じ並び）。
    public private(set) var legs: [RouteLeg?]
    /// ユーザーが固定した区間の時刻。同時に固定できるのは 1 区間だけ。
    /// 「同じ駅のまま別の便にする」操作に使い、前後の区間はこれを基準に取り直す。
    public private(set) var pinnedTime: TimeAnchor?
    public private(set) var pinnedSegmentIndex: Int?
    /// ユーザーが区間について決めたこと。自動推定はこれを上書きしない。
    public private(set) var locks: [SegmentKey: SegmentLock] = [:]
    /// 選んだ内容と最新の取得結果が食い違っている区間。更新するかはユーザーが決める。
    public private(set) var pendingUpdates: [SegmentKey: PendingSegmentUpdate] = [:]

    public init(nodes: [RouteNode],
                modes: [TransportMode],
                timePreference: TimePreference = .now,
                requestedDate: Date? = nil) {
        precondition(nodes.count >= 2, "ノードは 2 つ以上必要")
        self.nodes = nodes
        self.modes = RoutePlan.normalized(modes, count: nodes.count - 1)
        self.timePreference = timePreference
        self.requestedDate = requestedDate
        self.legs = Array(repeating: nil, count: nodes.count - 1)
        self.pinnedTime = nil
        self.pinnedSegmentIndex = nil
    }

    /// 出発地・目的地の 2 点だけの素朴なプラン。
    public static func simple(origin: RouteNode,
                              destination: RouteNode,
                              mode: TransportMode = .transit,
                              timePreference: TimePreference = .now,
                              requestedDate: Date? = nil) -> RoutePlan {
        RoutePlan(nodes: [origin, destination],
                  modes: [mode],
                  timePreference: timePreference,
                  requestedDate: requestedDate)
    }

    private static func normalized(_ modes: [TransportMode], count: Int) -> [TransportMode] {
        guard count > 0 else { return [] }
        if modes.count == count { return modes }
        if modes.count > count { return Array(modes.prefix(count)) }
        return modes + Array(repeating: modes.last ?? .walking, count: count - modes.count)
    }

    // MARK: - 参照

    public var origin: RouteNode { nodes[0] }
    public var destination: RouteNode { nodes[nodes.count - 1] }

    public var segments: [RouteSegment] {
        (0..<modes.count).map { index in
            RouteSegment(from: nodes[index],
                         to: nodes[index + 1],
                         mode: modes[index],
                         leg: legs[index])
        }
    }

    /// 全区間が揃っているときだけ合計を返す。
    public var totalTravelTime: TimeInterval? {
        let values = legs.compactMap { $0?.expectedTravelTime }
        guard values.count == legs.count, !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    public var totalDistance: Double? {
        let values = legs.compactMap { $0?.distance }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    /// 経路全体の出発時刻と到着時刻。
    ///
    /// MapKit は徒歩区間に時刻を返さないため、最初の区間が徒歩だと時刻が取れない。
    /// 時刻表（schedule）は公共交通の時刻を起点に前後へ伸ばすので、そちらを使う。
    public var departureDate: Date? { schedule().first??.departure }
    public var arrivalDate: Date? { schedule().last??.arrival }

    /// Google Maps へ詳細を渡せるか（公共交通区間を含むこと）。
    public var includesTransit: Bool {
        modes.contains(.transit)
    }

    public var isValid: Bool {
        nodes.count >= 2
            && nodes.allSatisfy { $0.place.isUsableForRouting }
            && modes.count == nodes.count - 1
            && (!timePreference.requiresDate || requestedDate != nil)
    }

    // MARK: - ユーザーの指定（ロック）

    public func lock(at index: Int) -> SegmentLock? {
        guard let key = segmentKey(at: index) else { return nil }
        return locks[key]
    }

    public func segmentKey(at index: Int) -> SegmentKey? {
        guard modes.indices.contains(index) else { return nil }
        return SegmentKey(from: nodes[index].place.id, to: nodes[index + 1].place.id)
    }

    public func isLocked(at index: Int) -> Bool {
        lock(at: index).map { !$0.isEmpty } ?? false
    }

    mutating func updateLock(at index: Int, _ transform: (inout SegmentLock) -> Void) {
        guard let key = segmentKey(at: index) else { return }
        var lock = locks[key] ?? SegmentLock()
        transform(&lock)
        if lock.isEmpty {
            locks.removeValue(forKey: key)
        } else {
            locks[key] = lock
        }
    }

    /// 区間の指定を解除して、自動推定に戻す。
    public mutating func clearLock(at index: Int) {
        guard let key = segmentKey(at: index) else { return }
        locks.removeValue(forKey: key)
        pendingUpdates.removeValue(forKey: key)
        legs[index] = nil
    }

    // MARK: - 食い違いの提示

    public func pendingUpdate(at index: Int) -> PendingSegmentUpdate? {
        guard let key = segmentKey(at: index) else { return nil }
        return pendingUpdates[key]
    }

    /// 「ここが違います」として提示する。表示は現在の内容のまま変えない。
    public mutating func proposeUpdate(_ proposed: RouteLeg, at index: Int) {
        guard let key = segmentKey(at: index), let current = legs[index] else { return }
        guard abs(proposed.expectedTravelTime - current.expectedTravelTime) > 1 else {
            pendingUpdates.removeValue(forKey: key)
            return
        }
        pendingUpdates[key] = PendingSegmentUpdate(key: key, current: current, proposed: proposed)
    }

    /// 提案を受け入れる。以後はこの内容が「ユーザーの選択」になる。
    public mutating func acceptUpdate(at index: Int) {
        guard let key = segmentKey(at: index), let update = pendingUpdates[key] else { return }
        legs[index] = update.proposed
        updateLock(at: index) { lock in
            lock.leg = update.proposed
            lock.duration = update.proposed.expectedTravelTime
            if let departure = update.proposed.departureDate {
                lock.timeAnchor = TimeAnchor(kind: .depart, date: departure)
            }
        }
        pendingUpdates.removeValue(forKey: key)
    }

    /// 提案を退けて、選んだ内容のまま続ける。
    public mutating func dismissUpdate(at index: Int) {
        guard let key = segmentKey(at: index) else { return }
        pendingUpdates.removeValue(forKey: key)
    }

    public mutating func clearAllLocks() {
        locks.removeAll()
    }

    // MARK: - 編集

    /// 区間の移動手段を差し替える。ユーザー操作なので指定として記録する。
    public mutating func setMode(_ mode: TransportMode, at index: Int, byUser: Bool = true) {
        guard modes.indices.contains(index) else { return }
        modes[index] = mode
        legs[index] = nil
        if byUser {
            updateLock(at: index) { lock in
                lock.mode = mode
                // 手段が変われば以前の便と所要時間は意味を失う。
                lock.timeAnchor = nil
                lock.duration = nil
            }
        }
    }

    /// 区間の移動手段を順に切り替える（矢印のアイコンを押したときの挙動）。
    public mutating func cycleMode(at index: Int) {
        guard modes.indices.contains(index) else { return }
        setMode(modes[index].next, at: index)
    }

    /// 全区間を 1 つの手段に揃える（上部タブのプリセット）。
    /// ユーザーが手段を決めた区間は変えない。
    public mutating func applyPreset(_ mode: TransportMode) {
        for index in modes.indices {
            if lock(at: index)?.mode != nil { continue }
            modes[index] = mode
            legs[index] = nil
        }
    }

    /// ノードの地点を差し替える。推定駅を選び直した場合は推定フラグを外す。
    public mutating func updatePlace(_ place: Place, at index: Int) {
        guard nodes.indices.contains(index) else { return }
        nodes[index].place = place
        nodes[index].isInferred = false
        nodes[index].isCurrentLocation = false
        invalidateLegs(around: index)
    }

    /// ノードを現在地に切り替える。
    public mutating func setCurrentLocation(_ place: Place, at index: Int) {
        guard nodes.indices.contains(index) else { return }
        nodes[index].place = place
        nodes[index].isCurrentLocation = true
        nodes[index].isInferred = false
        invalidateLegs(around: index)
    }

    /// 指定区間の途中にノードを挿し込む。挿入前の区間の手段を引き継ぐ。
    public mutating func insertNode(_ node: RouteNode, afterSegment index: Int) {
        guard modes.indices.contains(index) else { return }
        nodes.insert(node, at: index + 1)
        modes.insert(modes[index], at: index)
        legs.insert(nil, at: index)
        legs[index + 1] = nil
    }

    /// 中間ノードを削除する（出発地と目的地は消せない）。
    public mutating func removeNode(at index: Int) {
        guard nodes.indices.contains(index), index > 0, index < nodes.count - 1 else { return }
        nodes.remove(at: index)
        // 前後 2 区間が 1 区間に統合される。手前の手段を残す。
        modes.remove(at: index)
        legs.remove(at: index)
        legs[index - 1] = nil
    }

    /// 出発地と目的地を入れ替える。区間の並びも反転する。
    /// ユーザーの指定は向きを反転させて引き継ぐ（入れ替えても設定が消えないように）。
    public mutating func reverse() {
        nodes.reverse()
        modes.reverse()
        legs = Array(repeating: nil, count: modes.count)
        locks = Dictionary(uniqueKeysWithValues: locks.map { ($0.key.reversed, $0.value) })
        for index in nodes.indices {
            switch index {
            case 0: nodes[index].kind = .origin
            case nodes.count - 1: nodes[index].kind = .destination
            default: break
            }
        }
    }

    /// 自動推定した駅ノードをすべて取り除く（推定し直す前に呼ぶ）。
    public mutating func removeInferredStations() {
        for index in nodes.indices.reversed() where nodes[index].isInferred && index > 0 && index < nodes.count - 1 {
            removeNode(at: index)
        }
    }

    // MARK: - 便の指定

    /// 区間の時刻を固定する。前後の区間は取り直す必要があるので結果を捨てる。
    /// 選んだときの所要時間も記録し、次の取得で同じ長さの便を選び直せるようにする。
    public mutating func pinTime(_ anchor: TimeAnchor, at index: Int) {
        guard modes.indices.contains(index) else { return }
        pinnedTime = anchor
        pinnedSegmentIndex = index
        let chosenLeg = legs[index]
        updateLock(at: index) { lock in
            lock.timeAnchor = anchor
            lock.duration = chosenLeg?.expectedTravelTime
            lock.leg = chosenLeg
        }
        for position in legs.indices where position != index {
            legs[position] = nil
        }
    }

    public mutating func clearPin() {
        pinnedTime = nil
        pinnedSegmentIndex = nil
    }

    /// 区間ごとの時刻表。固定した区間を基準に、前後を所要時間で前後へ伸ばす。
    /// 表示用であり、実際の便の時刻は取得結果（leg の departureDate）が優先される。
    public func schedule() -> [(departure: Date, arrival: Date)?] {
        // 固定した便があればそこを起点にする。
        if let pinnedSegmentIndex, let pinnedTime, let pinnedLeg = legs[pinnedSegmentIndex] {
            let departure: Date
            switch pinnedTime.kind {
            case .depart: departure = pinnedTime.date
            case .arrive: departure = pinnedTime.date.addingTimeInterval(-pinnedLeg.expectedTravelTime)
            }
            return schedule(anchorIndex: pinnedSegmentIndex, anchorDeparture: departure)
        }

        // 固定していない場合は、時刻を持つ最初の区間（通常は公共交通）を起点にする。
        // 徒歩区間は時刻を返さないので、その所要時間で前後へ伸ばす。
        guard let anchorIndex = legs.firstIndex(where: { $0?.departureDate != nil }),
              let anchorDeparture = legs[anchorIndex]?.departureDate else {
            return Array(repeating: nil, count: legs.count)
        }
        return schedule(anchorIndex: anchorIndex, anchorDeparture: anchorDeparture)
    }

    /// 起点の区間から前後へ、所要時間ぶんだけ時刻を伸ばす。
    private func schedule(anchorIndex: Int, anchorDeparture: Date) -> [(departure: Date, arrival: Date)?] {
        var result = [(departure: Date, arrival: Date)?](repeating: nil, count: legs.count)
        guard let anchorLeg = legs[anchorIndex] else { return result }

        let anchorArrival = anchorDeparture.addingTimeInterval(anchorLeg.expectedTravelTime)
        result[anchorIndex] = (anchorDeparture, anchorArrival)

        var cursor = anchorDeparture
        for index in stride(from: anchorIndex - 1, through: 0, by: -1) {
            guard let leg = legs[index] else { break }
            let departure = cursor.addingTimeInterval(-leg.expectedTravelTime)
            result[index] = (departure, cursor)
            cursor = departure
        }

        cursor = anchorArrival
        for index in (anchorIndex + 1)..<legs.count {
            guard let leg = legs[index] else { break }
            let arrival = cursor.addingTimeInterval(leg.expectedTravelTime)
            result[index] = (cursor, arrival)
            cursor = arrival
        }
        return result
    }

    // MARK: - 結果の反映

    public mutating func setLeg(_ leg: RouteLeg?, at index: Int) {
        guard legs.indices.contains(index) else { return }
        legs[index] = leg
    }

    public mutating func clearLegs() {
        legs = Array(repeating: nil, count: modes.count)
    }

    private mutating func invalidateLegs(around index: Int) {
        if legs.indices.contains(index - 1) { legs[index - 1] = nil }
        if legs.indices.contains(index) { legs[index] = nil }
    }
}

extension TransportMode {
    /// トグル用の並び。公共交通 → 徒歩 → 車 → 公共交通。
    public var next: TransportMode {
        switch self {
        case .transit: return .walking
        case .walking: return .driving
        case .driving: return .transit
        }
    }
}

extension Array {
    /// 範囲外でも落ちない添字アクセス（時刻表の前後参照で使う）。
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
