import Domain
import Foundation
import MapKit

/// MKLocalSearch による場所検索（仕様書 S02）。
public struct MapKitPlaceSearchService: PlaceSearching {
    /// 検索範囲の初期スパン（現在地周辺 ≒ 20km）。
    private let regionSpanMeters: CLLocationDistance

    public init(regionSpanMeters: CLLocationDistance = 20_000) {
        self.regionSpanMeters = regionSpanMeters
    }

    public func search(query: String, around center: Coordinate?) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let center, center.isValid {
            request.region = MKCoordinateRegion(center: center.clCoordinate,
                                                latitudinalMeters: regionSpanMeters,
                                                longitudinalMeters: regionSpanMeters)
        }

        let search = MKLocalSearch(request: request)
        do {
            try Task.checkCancellation()
            let response = try await withTaskCancellationHandler {
                try await search.start()
            } onCancel: {
                search.cancel()
            }
            try Task.checkCancellation()
            return response.mapItems.compactMap(Place.init(mapItem:))
        } catch {
            throw MapKitErrorMapper.searchError(error)
        }
    }
}
