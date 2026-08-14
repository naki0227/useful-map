@preconcurrency import CoreLocation
import Domain
import Foundation

/// 座標から地点名を引く（地図をタップして地点を選ぶときに使う）。
///
/// 名称が取れない場所もあるため、失敗しても座標そのものを名前にした地点を返し、
/// 操作を止めない。
public struct CoreLocationPlaceResolver: PlaceResolving {
    private let geocoder: CLGeocoder

    public init(geocoder: CLGeocoder = CLGeocoder()) {
        self.geocoder = geocoder
    }

    public func place(at coordinate: Coordinate) async -> Place {
        let fallback = Place(name: "", coordinate: coordinate)
        guard coordinate.isValid else { return fallback }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return fallback
        }
        return Place(name: placemark.name ?? placemark.thoroughfare ?? "",
                     coordinate: coordinate,
                     address: Self.address(from: placemark))
    }

    static func address(from placemark: CLPlacemark) -> String? {
        let parts: [String?] = [
            placemark.administrativeArea,
            placemark.locality,
            placemark.subLocality,
            placemark.thoroughfare,
            placemark.subThoroughfare
        ]
        let joined = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined()
        return joined.isEmpty ? nil : joined
    }
}
