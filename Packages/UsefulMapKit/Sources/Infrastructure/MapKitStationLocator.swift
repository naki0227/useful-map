import Domain
import Foundation
import MapKit

/// MapKit の POI 検索で公共交通の乗降地点を探す。
///
/// MapKit は公共交通の乗車駅を経路として返さないため、地理的な近さで代用する。
/// また POI カテゴリは `.publicTransport` の 1 種類しかなく、駅とバス停を区別できない。
/// 種別の判定は `TransitStopClassifier` が名称から推定し、UI 側でユーザーが選び直せる。
public struct MapKitTransitStopLocator: TransitStopLocating {
    public init() {}

    public func stops(near coordinate: Coordinate,
                      within meters: Double,
                      limit: Int) async throws -> [Place] {
        guard coordinate.isValid, limit > 0 else { return [] }

        let request = MKLocalPointsOfInterestRequest(center: coordinate.clCoordinate, radius: meters)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])

        let search = MKLocalSearch(request: request)
        do {
            try Task.checkCancellation()
            let response = try await withTaskCancellationHandler {
                try await search.start()
            } onCancel: {
                search.cancel()
            }
            let places = response.mapItems
                .compactMap(Place.init(mapItem:))
                .sorted { $0.coordinate.distance(to: coordinate) < $1.coordinate.distance(to: coordinate) }
            return Array(places.prefix(limit))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // 停留所が取れなくても経路比較自体は続けたいので、失敗は「見つからない」として扱う。
            if MapKitErrorMapper.searchError(error) == .cancelled { throw CancellationError() }
            return []
        }
    }
}
