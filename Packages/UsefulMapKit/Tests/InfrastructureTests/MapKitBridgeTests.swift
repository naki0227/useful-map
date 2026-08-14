import CoreLocation
import Domain
import Foundation
import MapKit
import Testing

@testable import Infrastructure

@Suite("MapKit 境界")
struct MapKitBridgeTests {
    @Test("CLLocationCoordinate2D と Coordinate を相互変換できる")
    func coordinateBridging() {
        let cl = CLLocationCoordinate2D(latitude: 35.6812362, longitude: 139.7671248)
        let coordinate = Coordinate(cl)
        #expect(coordinate.latitude == cl.latitude)
        #expect(coordinate.longitude == cl.longitude)
        #expect(coordinate.clCoordinate.latitude == cl.latitude)
        #expect(coordinate.clCoordinate.longitude == cl.longitude)
    }

    @Test("MKMapItem から内部 Place へ正規化する")
    func placeFromMapItem() throws {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 35.6812362,
                                                                      longitude: 139.7671248))
        let item = MKMapItem(placemark: placemark)
        item.name = "東京駅"

        let place = try #require(Place(mapItem: item))
        #expect(place.name == "東京駅")
        #expect(place.coordinate.latitude == 35.6812362)
        #expect(place.coordinate.longitude == 139.7671248)
    }

    @Test("座標が不正な MKMapItem は取り込まない")
    func rejectsInvalidMapItem() {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0))
        let item = MKMapItem(placemark: placemark)
        item.name = "座標なし"
        #expect(Place(mapItem: item) == nil)
    }

    @Test("Place から MKMapItem を作れる（経路リクエスト用）")
    func mapItemFromPlace() {
        let place = Place(name: "東京駅", latitude: 35.6812362, longitude: 139.7671248)
        let item = place.mapItem
        #expect(item.name == "東京駅")
        #expect(item.placemark.coordinate.latitude == 35.6812362)
    }

    @Test("TransportMode は MapKit の transportType に対応する")
    func transportTypeMapping() {
        #expect(TransportMode.transit.mapKitTransportType == .transit)
        #expect(TransportMode.walking.mapKitTransportType == .walking)
        #expect(TransportMode.driving.mapKitTransportType == .automobile)
    }

    // MARK: - エラー写像

    @Test("経路が見つからない場合、公共交通は地域非対応として扱う")
    func routeErrorForTransit() {
        let error = NSError(domain: MKErrorDomain, code: Int(MKError.Code.directionsNotFound.rawValue))
        #expect(MapKitErrorMapper.routeError(error, mode: .transit) == .unsupportedInRegion(.transit))
        #expect(MapKitErrorMapper.routeError(error, mode: .driving) == .noRoutesFound)
    }

    @Test("スロットリングは再試行を促すメッセージにする")
    func routeErrorThrottled() {
        let error = NSError(domain: MKErrorDomain, code: Int(MKError.Code.loadingThrottled.rawValue))
        guard case let .failed(message) = MapKitErrorMapper.routeError(error, mode: .driving) else {
            Issue.record("failed 以外になった")
            return
        }
        #expect(message.contains("制限"))
    }

    @Test("キャンセルは cancelled として扱い、UI にエラーを出さない")
    func routeErrorCancellation() {
        #expect(MapKitErrorMapper.routeError(CancellationError(), mode: .transit) == .cancelled)
        let urlCancel = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        #expect(MapKitErrorMapper.routeError(urlCancel, mode: .transit) == .cancelled)
        #expect(MapKitErrorMapper.searchError(CancellationError()) == .cancelled)
    }

    @Test("未知のエラーはメッセージを保って failed にする")
    func routeErrorUnknown() {
        let error = NSError(domain: "Test", code: 42,
                            userInfo: [NSLocalizedDescriptionKey: "通信に失敗しました"])
        #expect(MapKitErrorMapper.routeError(error, mode: .driving) == .failed("通信に失敗しました"))
        #expect(MapKitErrorMapper.searchError(error) == .failed("通信に失敗しました"))
    }

    @Test("検索で地点が見つからない場合は結果なしのメッセージにする")
    func searchErrorPlacemarkNotFound() {
        let error = NSError(domain: MKErrorDomain, code: Int(MKError.Code.placemarkNotFound.rawValue))
        #expect(MapKitErrorMapper.searchError(error) == .failed("検索結果が見つかりませんでした"))
    }

    @Test("RouteError の表示文言が空にならない")
    func errorMessages() {
        let errors: [RouteError] = [.noRoutesFound, .unsupportedInRegion(.transit), .cancelled, .failed("x")]
        for error in errors {
            #expect(!error.localizedMessage.isEmpty)
        }
        #expect(RouteError.unsupportedInRegion(.transit).localizedMessage.contains("公共交通"))
    }
}

@Suite("MapKit 検索サービス")
struct MapKitPlaceSearchServiceTests {
    @Test("空文字・空白だけの検索はネットワークへ出ず 0 件を返す")
    func emptyQueryShortCircuits() async throws {
        let service = MapKitPlaceSearchService()
        #expect(try await service.search(query: "", around: nil).isEmpty)
        #expect(try await service.search(query: "   \n", around: nil).isEmpty)
    }
}
