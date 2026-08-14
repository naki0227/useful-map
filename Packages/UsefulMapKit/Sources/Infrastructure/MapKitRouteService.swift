import Domain
import Foundation
import MapKit

/// MKDirections による経路取得（仕様書 5 / 6）。
///
/// - 徒歩・車: `calculate()` で経路（ジオメトリ付き）と代替候補を取得する。
/// - 公共交通: MapKit は経路ジオメトリを返さないため `calculateETA()` を使い、
///   出発時刻・到着時刻・所要時間だけを取得する。運賃・乗換は取得も推定もしない。
/// - 経由地: MKDirections は経由地を直接サポートしないため、区間ごとに計算して合算する。
/// MKDirections による区間単位の経路取得（仕様書 5 / 6）。
///
/// - 徒歩・車: `calculate()` で経路（ジオメトリ付き）を取得する。
/// - 公共交通: MapKit は経路ジオメトリを返さないため `calculateETA()` を使い、
///   出発時刻・到着時刻・所要時間だけを取得する。運賃・乗換は取得も推定もしない。
///
/// 区間の組み立て（乗降地点の推定と分割）は Domain の RoutePlanner が行う。
public struct MapKitRouteService {
    public init() {}
}

// MARK: - 区間単位の取得

extension MapKitRouteService: SegmentRouting {
    /// 1 区間ぶんを取得する。
    /// 公共交通は MapKit が経路を返さないため ETA のみ、徒歩・車は経路線も取る。
    public func leg(from source: Place,
                    to destination: Place,
                    mode: TransportMode,
                    timePreference: TimePreference,
                    requestedDate: Date?) async throws -> RouteLeg {
        let request = MKDirections.Request()
        request.source = source.mapItem
        request.destination = destination.mapItem
        request.transportType = mode.mapKitTransportType
        switch timePreference {
        case .now:
            break
        case .departAt:
            request.departureDate = requestedDate
        case .arriveBy:
            request.arrivalDate = requestedDate
        }

        let directions = MKDirections(request: request)
        do {
            try Task.checkCancellation()
            if mode.providesRouteGeometry {
                let response = try await withTaskCancellationHandler {
                    try await directions.calculate()
                } onCancel: {
                    directions.cancel()
                }
                guard let route = response.routes.first else { throw RouteError.noRoutesFound }
                return RouteLeg(expectedTravelTime: route.expectedTravelTime,
                                distance: route.distance,
                                geometry: route.coordinates)
            }

            let eta = try await withTaskCancellationHandler {
                try await directions.calculateETA()
            } onCancel: {
                directions.cancel()
            }
            return RouteLeg(expectedTravelTime: eta.expectedTravelTime,
                            departureDate: eta.expectedDepartureDate,
                            arrivalDate: eta.expectedArrivalDate,
                            distance: eta.distance > 0 ? eta.distance : nil)
        } catch let error as RouteError {
            throw error
        } catch {
            throw MapKitErrorMapper.routeError(error, mode: mode)
        }
    }
}
