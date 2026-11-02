import Domain

extension RoutePlanViewModel {
    /// 上部タブのプリセット。押すと全区間をその手段で組み直す。
    enum Preset: Hashable, Identifiable, CaseIterable {
        case transit
        case walking
        case driving

        var id: String { mode.rawValue }
        var mode: TransportMode {
            switch self {
            case .transit: return .transit
            case .walking: return .walking
            case .driving: return .driving
            }
        }

        var displayName: String { mode.displayName }
        var symbolName: String { mode.symbolName }
    }
}
