import Combine
import Domain
import Foundation

/// 永続化しないストア。UI テストの初期状態固定や、権限なしでの一時利用に使う。
public final class InMemoryLocalStore: LocalStoring, ObservableObject {
    @Published public private(set) var savedPlaces: [SavedPlace] = []
    @Published public private(set) var recentSearches: [RecentSearch] = []
    @Published public private(set) var recentRoutes: [RecentRoute] = []

    public init(savedPlaces: [SavedPlace] = [],
                recentSearches: [RecentSearch] = [],
                recentRoutes: [RecentRoute] = []) {
        self.savedPlaces = savedPlaces
        self.recentSearches = recentSearches
        self.recentRoutes = recentRoutes
    }

    public func savePlace(_ place: Place, label: SavedPlace.Label, at date: Date) {
        guard place.isUsableForRouting else { return }
        StoreMutations.upsert(SavedPlace(place: place, label: label, savedAt: date), into: &savedPlaces)
    }

    public func removeSavedPlace(id: SavedPlace.ID) {
        StoreMutations.remove(id: id, from: &savedPlaces)
    }

    public func isSaved(_ place: Place) -> Bool {
        savedPlaces.contains { $0.id == place.id }
    }

    public func recordSearch(_ place: Place, at date: Date) {
        guard place.isUsableForRouting else { return }
        StoreMutations.upsert(RecentSearch(place: place, searchedAt: date),
                              into: &recentSearches,
                              limit: UserDefaultsLocalStore.Limits.recentSearches)
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
                              limit: UserDefaultsLocalStore.Limits.recentRoutes)
    }

    public func clearHistory() {
        recentSearches = []
        recentRoutes = []
    }
}
