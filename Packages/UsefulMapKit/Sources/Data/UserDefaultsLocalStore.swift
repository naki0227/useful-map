import Combine
import Domain
import Foundation

/// 端末内保存（仕様書 11 / 12）。Backend・クラウド同期は持たない。
///
/// MVP のデータ量（保存地点と直近履歴のみ）では SwiftData を導入する利点が薄いため、
/// UserDefaults + JSON を採用する。差し替えは `LocalStoring` 経由で可能。
public final class UserDefaultsLocalStore: LocalStoring, ObservableObject {
    public enum Limits {
        public static let recentSearches = 20
        public static let recentRoutes = 20
    }

    private enum Key {
        static let savedPlaces = "usefulmap.savedPlaces"
        static let recentSearches = "usefulmap.recentSearches"
        static let recentRoutes = "usefulmap.recentRoutes"
    }

    @Published public private(set) var savedPlaces: [SavedPlace] = []
    @Published public private(set) var recentSearches: [RecentSearch] = []
    @Published public private(set) var recentRoutes: [RecentRoute] = []

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        savedPlaces = load([SavedPlace].self, for: Key.savedPlaces) ?? []
        recentSearches = load([RecentSearch].self, for: Key.recentSearches) ?? []
        recentRoutes = load([RecentRoute].self, for: Key.recentRoutes) ?? []
    }

    // MARK: - 保存地点

    public func savePlace(_ place: Place, label: SavedPlace.Label = .other, at date: Date) {
        guard place.isUsableForRouting else { return }
        StoreMutations.upsert(SavedPlace(place: place, label: label, savedAt: date), into: &savedPlaces)
        persist(savedPlaces, for: Key.savedPlaces)
    }

    public func removeSavedPlace(id: SavedPlace.ID) {
        StoreMutations.remove(id: id, from: &savedPlaces)
        persist(savedPlaces, for: Key.savedPlaces)
    }

    public func isSaved(_ place: Place) -> Bool {
        savedPlaces.contains { $0.id == place.id }
    }

    // MARK: - 履歴

    public func recordSearch(_ place: Place, at date: Date) {
        guard place.isUsableForRouting else { return }
        StoreMutations.upsert(RecentSearch(place: place, searchedAt: date),
                              into: &recentSearches,
                              limit: Limits.recentSearches)
        persist(recentSearches, for: Key.recentSearches)
    }

    public func recordRoute(origin: RouteEndpoint,
                            destination: Place,
                            transportMode: TransportMode,
                            at date: Date) {
        guard destination.isUsableForRouting else { return }
        StoreMutations.upsert(RecentRoute(origin: origin,
                                          destination: destination,
                                          transportMode: transportMode,
                                          usedAt: date),
                              into: &recentRoutes,
                              limit: Limits.recentRoutes)
        persist(recentRoutes, for: Key.recentRoutes)
    }

    public func clearHistory() {
        recentSearches = []
        recentRoutes = []
        persist(recentSearches, for: Key.recentSearches)
        persist(recentRoutes, for: Key.recentRoutes)
    }

    // MARK: - 永続化

    private func persist<T: Encodable>(_ value: T, for key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func load<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
