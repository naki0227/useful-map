import Domain
import Foundation

/// 経路プランの読み取り。画面がそのまま出せる形へ整えるだけで、状態は変えない。
@MainActor
extension RoutePlanViewModel {
    public var segments: [RouteSegment] { plan.segments }
    public var nodes: [RouteNode] { plan.nodes }
    public var schedule: [(departure: Date, arrival: Date)?] { plan.schedule() }

    public var totalTravelTime: TimeInterval? { plan.totalTravelTime }

    /// 区間ごとに Google へ委譲できる。
    /// 各区間は 2 地点なので、Google が経由地つき公共交通を扱えない制約にも当たらない。
    public func canOpenDetail(at index: Int) -> Bool {
        plan.segments.indices.contains(index)
    }

    public func isLocked(at index: Int) -> Bool { plan.isLocked(at: index) }

    public func pendingUpdate(at index: Int) -> PendingSegmentUpdate? { plan.pendingUpdate(at: index) }

    /// 区間の発着時刻。固定した便を基準に前後へ伸ばした時刻表を使う。
    public func timeRange(at index: Int) -> String? {
        let table = schedule
        guard table.indices.contains(index), let entry = table[index] else { return nil }
        return Formatters.timeRange(departure: entry.departure, arrival: entry.arrival)
    }

    /// 現在のプリセット（全区間が同じ手段のときだけ確定する）。
    public var activePreset: Preset? {
        guard let first = plan.modes.first, plan.modes.allSatisfy({ $0 == first }) else { return nil }
        return Preset.allCases.first { $0.mode == first }
    }

    /// 経路全体の発着時刻。
    public var overallTimeRange: String? {
        let table = schedule
        // schedule は [Entry?] なので、first / last は二重 Optional になる。
        guard let first = table.first.flatMap({ $0 }),
              let last = table.last.flatMap({ $0 }) else { return nil }
        return Formatters.timeRange(departure: first.departure, arrival: last.arrival)
    }

    public var title: String {
        "\(plan.origin.displayName) → \(plan.destination.displayName)"
    }
}
