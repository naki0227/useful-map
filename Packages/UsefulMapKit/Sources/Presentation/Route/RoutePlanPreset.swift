import Domain

extension RoutePlanViewModel {
    /// 上部タブのプリセット。押すと全区間をその手段で組み直す。
    public enum Preset: Hashable, Identifiable, CaseIterable {
        case transit
        case walking
        case driving

        public var id: String { mode.rawValue }
        public var mode: TransportMode {
            switch self {
            case .transit: return .transit
            case .walking: return .walking
            case .driving: return .driving
            }
        }

        public var displayName: String { mode.displayName }
        public var symbolName: String { mode.symbolName }
    }
}
