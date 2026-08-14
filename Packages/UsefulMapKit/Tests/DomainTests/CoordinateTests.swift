import Foundation
import Testing

@testable import Domain

@Suite("Coordinate")
struct CoordinateTests {
    @Test("妥当な座標は isValid が true")
    func validCoordinate() {
        #expect(Coordinate(latitude: 35.6812362, longitude: 139.7671248).isValid)
        #expect(Coordinate(latitude: -33.8688, longitude: 151.2093).isValid)
    }

    @Test("範囲外・NaN・(0,0) は URL 生成に使わない",
          arguments: [
            Coordinate(latitude: 91, longitude: 0),
            Coordinate(latitude: -91, longitude: 0),
            Coordinate(latitude: 0, longitude: 181),
            Coordinate(latitude: 0, longitude: -181),
            Coordinate(latitude: .nan, longitude: 139.7),
            Coordinate(latitude: 35.6, longitude: .infinity),
            Coordinate(latitude: 0, longitude: 0)
          ])
    func invalidCoordinate(coordinate: Coordinate) {
        #expect(!coordinate.isValid)
    }

    @Test("固定精度 7 桁で文字列化する")
    func formatting() {
        let coordinate = Coordinate(latitude: 35.6812362, longitude: 139.7671248)
        #expect(coordinate.latitudeString == "35.6812362")
        #expect(coordinate.longitudeString == "139.7671248")
    }

    @Test("桁が短い値もゼロ埋めされ、URL の見た目が安定する")
    func formattingPadsDigits() {
        #expect(Coordinate(latitude: 35.5, longitude: 139.0).latitudeString == "35.5000000")
        #expect(Coordinate(latitude: 35.5, longitude: 139.0).longitudeString == "139.0000000")
    }

    @Test("非有限値は 0 として文字列化し、URL を壊さない")
    func formattingNonFinite() {
        #expect(Coordinate.format(.nan) == "0")
        #expect(Coordinate.format(.infinity) == "0")
    }

    @Test("球面距離が概算と一致する（東京駅〜新宿御苑 ≒ 5.6km）")
    func distance() {
        let tokyo = Coordinate(latitude: 35.6812362, longitude: 139.7671248)
        let shinjuku = Coordinate(latitude: 35.6852, longitude: 139.7100)
        let meters = tokyo.distance(to: shinjuku)
        #expect(meters > 5_000 && meters < 6_200)
        #expect(tokyo.distance(to: tokyo) == 0)
    }

    @Test("Codable で往復しても値が変わらない")
    func codableRoundTrip() throws {
        let coordinate = Coordinate(latitude: 35.6812362, longitude: 139.7671248)
        let data = try JSONEncoder().encode(coordinate)
        #expect(try JSONDecoder().decode(Coordinate.self, from: data) == coordinate)
    }
}
