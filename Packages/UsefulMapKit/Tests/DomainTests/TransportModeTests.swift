import Foundation
import Testing

@testable import Domain

@Suite("TransportMode")
struct TransportModeTests {
    @Test("外部詳細へ委譲するのは公共交通だけ")
    func detailDelegation() {
        #expect(TransportMode.transit.delegatesDetailToGoogleMaps)
        #expect(!TransportMode.walking.delegatesDetailToGoogleMaps)
        #expect(!TransportMode.driving.delegatesDetailToGoogleMaps)
    }

    @Test("経路ジオメトリを持つのは徒歩・車、時刻を持つのは公共交通")
    func capabilities() {
        #expect(!TransportMode.transit.providesRouteGeometry)
        #expect(TransportMode.walking.providesRouteGeometry)
        #expect(TransportMode.driving.providesRouteGeometry)
        #expect(TransportMode.transit.supportsScheduledTimes)
        #expect(!TransportMode.driving.supportsScheduledTimes)
    }

    @Test("表示名とアイコンが全モードに揃っている")
    func presentationMetadata() {
        for mode in TransportMode.allCases {
            #expect(!mode.displayName.isEmpty)
            #expect(!mode.symbolName.isEmpty)
            #expect(mode.id == mode.rawValue)
        }
    }
}
