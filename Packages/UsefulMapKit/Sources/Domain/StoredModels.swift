import Foundation

/// 端末内保存データ（仕様書 11）。時刻付き Google 内部 URL は永続化しない。

public struct SavedPlace: Identifiable, Hashable, Codable, Sendable {
    public enum Label: String, Codable, CaseIterable, Sendable {
        case home
        case school
        case other

        public var displayName: String {
            switch self {
            case .home: return "自宅"
            case .school: return "学校"
            case .other: return "保存済み"
            }
        }

        public var symbolName: String {
            switch self {
            case .home: return "house.fill"
            case .school: return "graduationcap.fill"
            case .other: return "bookmark.fill"
            }
        }
    }

    public var place: Place
    public var label: Label
    public var savedAt: Date

    public init(place: Place, label: Label = .other, savedAt: Date) {
        self.place = place
        self.label = label
        self.savedAt = savedAt
    }

    public var id: String { place.id }
}

public struct RecentSearch: Identifiable, Hashable, Codable, Sendable {
    public var place: Place
    public var searchedAt: Date

    public init(place: Place, searchedAt: Date) {
        self.place = place
        self.searchedAt = searchedAt
    }

    public var id: String { place.id }
}

public struct RecentRoute: Identifiable, Hashable, Codable, Sendable {
    public var origin: RouteEndpoint
    public var destination: Place
    public var transportMode: TransportMode
    public var usedAt: Date

    public init(origin: RouteEndpoint, destination: Place, transportMode: TransportMode, usedAt: Date) {
        self.origin = origin
        self.destination = destination
        self.transportMode = transportMode
        self.usedAt = usedAt
    }

    /// 出発地・目的地・モードが同じものは同一経路として扱う（履歴の重複排除に使う）。
    public var id: String {
        "\(origin.place?.id ?? "currentLocation")>\(destination.id)#\(transportMode.rawValue)"
    }
}

/// 端末内ストレージのポート。
public protocol LocalStoring: AnyObject {
    var savedPlaces: [SavedPlace] { get }
    var recentSearches: [RecentSearch] { get }
    var recentRoutes: [RecentRoute] { get }

    func savePlace(_ place: Place, label: SavedPlace.Label, at date: Date)
    func removeSavedPlace(id: SavedPlace.ID)
    func isSaved(_ place: Place) -> Bool

    func recordSearch(_ place: Place, at date: Date)
    func recordRoute(origin: RouteEndpoint, destination: Place, transportMode: TransportMode, at date: Date)
    func clearHistory()
}
