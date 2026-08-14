import Foundation

/// 徒歩の速さ。歩く速度は人によって違うので、利用者が切り替えられるようにする。
///
/// MapKit に歩行速度を指定する API は無いため、MapKit が返した所要時間を係数で補正する。
/// つまり「MapKit の想定（時速 5km 前後）に対する倍率」であり、絶対値の保証ではない。
public enum WalkingPace: String, CaseIterable, Codable, Sendable, Identifiable {
    case slow
    case normal
    case fast

    public var id: String { rawValue }

    /// MapKit の所要時間に掛ける倍率。
    public var multiplier: Double {
        switch self {
        case .slow: return 1.25
        case .normal: return 1.0
        case .fast: return 0.8
        }
    }

    public var displayName: String {
        switch self {
        case .slow: return L10n.string("pace.slow")
        case .normal: return L10n.string("pace.normal")
        case .fast: return L10n.string("pace.fast")
        }
    }

    public var symbolName: String {
        switch self {
        case .slow: return "tortoise.fill"
        case .normal: return "figure.walk"
        case .fast: return "hare.fill"
        }
    }

    /// ボタン 1 つで切り替えるための順序。
    public var next: WalkingPace {
        switch self {
        case .normal: return .fast
        case .fast: return .slow
        case .slow: return .normal
        }
    }

    /// 徒歩区間にだけ倍率を掛ける。
    public func adjusted(_ leg: RouteLeg, mode: TransportMode) -> RouteLeg {
        guard mode == .walking, self != .normal else { return leg }
        return RouteLeg(expectedTravelTime: leg.expectedTravelTime * multiplier,
                        departureDate: leg.departureDate,
                        arrivalDate: leg.arrivalDate,
                        distance: leg.distance,
                        geometry: leg.geometry)
    }
}
