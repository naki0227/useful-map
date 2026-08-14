import Foundation

/// 出発地は「現在地」か検索済みの地点のいずれか（仕様書 5.2）。
public enum RouteEndpoint: Hashable, Codable, Sendable {
    case currentLocation
    case place(Place)

    public var place: Place? {
        if case let .place(place) = self { return place }
        return nil
    }

    public var isCurrentLocation: Bool {
        self == .currentLocation
    }

    public var displayName: String {
        switch self {
        case .currentLocation: return L10n.string("endpoint.currentLocation")
        case let .place(place): return place.displayName
        }
    }
}

/// 時刻条件（仕様書 5.2）。
public enum TimePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case now
    case departAt
    case arriveBy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .now: return L10n.string("time.now")
        case .departAt: return L10n.string("time.departAt")
        case .arriveBy: return L10n.string("time.arriveBy")
        }
    }

    public var requiresDate: Bool { self != .now }
}

/// 経路検索条件。
public struct RouteQuery: Hashable, Codable, Sendable {
    public var origin: RouteEndpoint
    public var destination: Place
    public var waypoints: [Place]
    public var transportMode: TransportMode
    public var timePreference: TimePreference
    public var requestedDate: Date?

    public init(origin: RouteEndpoint = .currentLocation,
                destination: Place,
                waypoints: [Place] = [],
                transportMode: TransportMode = .transit,
                timePreference: TimePreference = .now,
                requestedDate: Date? = nil) {
        self.origin = origin
        self.destination = destination
        self.waypoints = waypoints
        self.transportMode = transportMode
        self.timePreference = timePreference
        self.requestedDate = requestedDate
    }

    /// timePreference が .now の場合は日時条件を持たない。
    public var effectiveDate: Date? {
        timePreference.requiresDate ? requestedDate : nil
    }

    public var isValid: Bool {
        guard destination.isUsableForRouting else { return false }
        guard waypoints.allSatisfy({ $0.isUsableForRouting }) else { return false }
        if case let .place(origin) = origin, !origin.isUsableForRouting { return false }
        if timePreference.requiresDate && requestedDate == nil { return false }
        return true
    }

    // MARK: - 経路編集（S05）

    public mutating func addWaypoint(_ place: Place) {
        guard !waypoints.contains(where: { $0.id == place.id }) else { return }
        waypoints.append(place)
    }

    public mutating func removeWaypoint(id: Place.ID) {
        waypoints.removeAll { $0.id == id }
    }

    /// SwiftUI の `onMove` と同じ意味論で並べ替える（SwiftUI に依存せず Domain 内で実装する）。
    public mutating func moveWaypoints(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { waypoints.indices.contains($0) }
        guard !valid.isEmpty, (0...waypoints.count).contains(destination) else { return }
        let moving = valid.map { waypoints[$0] }
        // 挿入位置は「取り除く前」の基準なので、先に抜ける要素数だけ前へずらす。
        let insertionIndex = destination - valid.filter { $0 < destination }.count
        var remaining = waypoints
        for index in valid.sorted(by: >) {
            remaining.remove(at: index)
        }
        remaining.insert(contentsOf: moving, at: max(0, min(insertionIndex, remaining.count)))
        waypoints = remaining
    }

    /// 出発地と目的地を入れ替える。
    /// 現在地出発の場合は、解決済みの現在地地点が渡された時だけ入れ替える。
    public mutating func swapOriginAndDestination(resolvedCurrentLocation: Place? = nil) {
        switch origin {
        case let .place(originPlace):
            origin = .place(destination)
            destination = originPlace
        case .currentLocation:
            guard let resolvedCurrentLocation else { return }
            origin = .place(destination)
            destination = resolvedCurrentLocation
        }
        waypoints.reverse()
    }

    /// 経路計算に使う地点列（出発地は解決済みの Place を渡す）。
    public func orderedPlaces(resolvedOrigin: Place) -> [Place] {
        [resolvedOrigin] + waypoints + [destination]
    }
}
