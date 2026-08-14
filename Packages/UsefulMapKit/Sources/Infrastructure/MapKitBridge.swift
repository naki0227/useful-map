import CoreLocation
import Domain
import Foundation
import MapKit

/// Domain 型と MapKit / CoreLocation 型の相互変換。
/// Domain を Foundation だけに保つため、変換はこの層に閉じる。

extension Coordinate {
    public init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    public var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension Place {
    /// MKMapItem から Google 固有 ID を持たない内部モデルへ正規化する（仕様書 5.1）。
    public init?(mapItem: MKMapItem) {
        let coordinate = Coordinate(mapItem.placemark.coordinate)
        guard coordinate.isValid else { return nil }
        let name = mapItem.name ?? mapItem.placemark.name ?? ""
        self.init(name: name, coordinate: coordinate, address: Place.address(from: mapItem.placemark))
    }

    public var mapItem: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate.clCoordinate))
        item.name = name
        return item
    }

    static func address(from placemark: MKPlacemark) -> String? {
        let parts: [String?] = [
            placemark.administrativeArea,
            placemark.locality,
            placemark.subLocality,
            placemark.thoroughfare,
            placemark.subThoroughfare
        ]
        let joined = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined()
        return joined.isEmpty ? placemark.title : joined
    }
}

extension TransportMode {
    public var mapKitTransportType: MKDirectionsTransportType {
        switch self {
        case .transit: return .transit
        case .walking: return .walking
        case .driving: return .automobile
        }
    }
}

extension MKRoute {
    /// 地図描画用の座標列へ落とす。
    var coordinates: [Coordinate] {
        let count = polyline.pointCount
        guard count > 0 else { return [] }
        var points = [CLLocationCoordinate2D](repeating: .init(), count: count)
        polyline.getCoordinates(&points, range: NSRange(location: 0, length: count))
        return points.map(Coordinate.init)
    }
}

enum MapKitErrorMapper {
    static func routeError(_ error: Error, mode: TransportMode) -> RouteError {
        if error is CancellationError { return .cancelled }
        let nsError = error as NSError
        if nsError.domain == MKErrorDomain {
            switch MKError.Code(rawValue: UInt(nsError.code)) {
            case .directionsNotFound, .placemarkNotFound:
                // MapKit の公共交通は対応地域が限られるため、モードとして扱い分ける。
                return mode == .transit ? .unsupportedInRegion(.transit) : .noRoutesFound
            case .loadingThrottled:
                return .failed("読み込みが制限されました。少し待ってから再試行してください")
            default:
                break
            }
        }
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return .cancelled
        }
        return .failed(nsError.localizedDescription)
    }

    static func searchError(_ error: Error) -> PlaceSearchError {
        if error is CancellationError { return .cancelled }
        let nsError = error as NSError
        if nsError.domain == MKErrorDomain, MKError.Code(rawValue: UInt(nsError.code)) == .placemarkNotFound {
            return .failed("検索結果が見つかりませんでした")
        }
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return .cancelled
        }
        return .failed(nsError.localizedDescription)
    }
}
