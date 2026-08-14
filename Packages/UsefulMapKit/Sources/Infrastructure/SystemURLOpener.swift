import Domain
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// OS へ URL を渡す（Google Maps アプリ / ブラウザ）。
///
/// 遷移先で 404 になったか、UI 上で条件が解釈されたかはアプリ側から判定できない（仕様書 7.4）。
/// このため戻り値は「OS が open を受理したか」までを表し、形式破壊の検出は CI の契約監視が担う。
public struct SystemURLOpener: URLOpening {
    public init() {}

    public func open(_ url: URL) async -> Bool {
        #if canImport(UIKit)
        return await MainActor.run {
            guard UIApplication.shared.canOpenURL(url) else { return false }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return true
        }
        #else
        return false
        #endif
    }
}
