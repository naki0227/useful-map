import Domain
import Foundation
import MapKit

/// MKDirections による経路取得（仕様書 5 / 6）。
///
/// - 徒歩・車: `calculate()` で経路（ジオメトリ付き）と代替候補を取得する。
/// - 公共交通: MapKit は経路ジオメトリを返さないため `calculateETA()` を使い、
///   出発時刻・到着時刻・所要時間だけを取得する。運賃・乗換は取得も推定もしない。
/// - 経由地: MKDirections は経由地を直接サポートしないため、区間ごとに計算して合算する。
public struct MapKitRouteService: RouteProviding {
    /// 徒歩・車で返す候補の最大数。
    private let maxAlternatives: Int

    public init(maxAlternatives: Int = 3) {
        self.maxAlternatives = maxAlternatives
    }

    public func routes(for query: RouteQuery, resolvedOrigin: Place) async throws -> [RouteOption] {
        let places = query.orderedPlaces(resolvedOrigin: resolvedOrigin)
        guard places.count >= 2 else { throw RouteError.noRoutesFound }

        if query.transportMode.providesRouteGeometry {
            return try await geometryRoutes(query: query, origin: resolvedOrigin, places: places)
        }
        return try await transitRoutes(query: query, origin: resolvedOrigin, places: places)
    }

    // MARK: - 徒歩・車

    private func geometryRoutes(query: RouteQuery, origin: Place, places: [Place]) async throws -> [RouteOption] {
        // 経由地が無い場合のみ代替候補を並べる。経由地ありは区間合算で 1 候補にする。
        if places.count == 2 {
            let response = try await calculate(query: query, from: places[0], to: places[1], alternates: true)
            let routes = Array(response.routes.prefix(maxAlternatives))
            guard !routes.isEmpty else { throw RouteError.noRoutesFound }
            return routes.enumerated().map { index, route in
                makeOption(query: query,
                           origin: origin,
                           index: index,
                           travelTime: route.expectedTravelTime,
                           distance: route.distance,
                           geometry: route.coordinates,
                           routeName: route.name.isEmpty ? nil : route.name)
            }
        }

        var totalTime: TimeInterval = 0
        var totalDistance: CLLocationDistance = 0
        var geometry: [Coordinate] = []
        for index in 0..<(places.count - 1) {
            let response = try await calculate(query: query,
                                               from: places[index],
                                               to: places[index + 1],
                                               alternates: false)
            guard let route = response.routes.first else { throw RouteError.noRoutesFound }
            totalTime += route.expectedTravelTime
            totalDistance += route.distance
            geometry += route.coordinates
        }
        return [makeOption(query: query,
                           origin: origin,
                           index: 0,
                           travelTime: totalTime,
                           distance: totalDistance,
                           geometry: geometry,
                           routeName: nil)]
    }

    private func calculate(query: RouteQuery,
                           from source: Place,
                           to destination: Place,
                           alternates: Bool) async throws -> MKDirections.Response {
        let request = makeRequest(query: query, from: source, to: destination)
        request.requestsAlternateRoutes = alternates
        let directions = MKDirections(request: request)
        do {
            try Task.checkCancellation()
            return try await withTaskCancellationHandler {
                try await directions.calculate()
            } onCancel: {
                directions.cancel()
            }
        } catch {
            throw MapKitErrorMapper.routeError(error, mode: query.transportMode)
        }
    }

    // MARK: - 公共交通

    private func transitRoutes(query: RouteQuery, origin: Place, places: [Place]) async throws -> [RouteOption] {
        var totalTime: TimeInterval = 0
        var totalDistance: CLLocationDistance = 0
        var departure: Date?
        var arrival: Date?

        for index in 0..<(places.count - 1) {
            let request = makeRequest(query: query, from: places[index], to: places[index + 1])
            let directions = MKDirections(request: request)
            let eta: MKDirections.ETAResponse
            do {
                try Task.checkCancellation()
                eta = try await withTaskCancellationHandler {
                    try await directions.calculateETA()
                } onCancel: {
                    directions.cancel()
                }
            } catch {
                throw MapKitErrorMapper.routeError(error, mode: query.transportMode)
            }
            totalTime += eta.expectedTravelTime
            totalDistance += eta.distance
            if index == 0 { departure = eta.expectedDepartureDate }
            arrival = eta.expectedArrivalDate
        }

        guard totalTime > 0 else { throw RouteError.noRoutesFound }
        return [makeOption(query: query,
                           origin: origin,
                           index: 0,
                           travelTime: totalTime,
                           distance: totalDistance > 0 ? totalDistance : nil,
                           geometry: [],
                           routeName: nil,
                           departure: departure,
                           arrival: arrival)]
    }

    // MARK: - 共通

    private func makeRequest(query: RouteQuery, from source: Place, to destination: Place) -> MKDirections.Request {
        let request = MKDirections.Request()
        request.source = source.mapItem
        request.destination = destination.mapItem
        request.transportType = query.transportMode.mapKitTransportType
        switch query.timePreference {
        case .now:
            break
        case .departAt:
            request.departureDate = query.requestedDate
        case .arriveBy:
            request.arrivalDate = query.requestedDate
        }
        return request
    }

    private func makeOption(query: RouteQuery,
                            origin: Place,
                            index: Int,
                            travelTime: TimeInterval,
                            distance: CLLocationDistance?,
                            geometry: [Coordinate],
                            routeName: String?,
                            departure: Date? = nil,
                            arrival: Date? = nil) -> RouteOption {
        RouteOption(id: "\(query.transportMode.rawValue)-\(index)",
                    query: query,
                    origin: origin,
                    mode: query.transportMode,
                    expectedTravelTime: travelTime,
                    departureDate: departure,
                    arrivalDate: arrival,
                    distance: distance,
                    geometry: geometry,
                    routeName: routeName)
    }
}
