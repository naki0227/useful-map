import Foundation

/// 区間の同一性を表すキー。
///
/// 添字はノードの挿入・削除でずれるため、区間の両端の地点でロックを持つ。
/// これにより、別の場所を編集してもユーザーの指定が生き残る。
public struct SegmentKey: Hashable, Sendable {
    public let from: Place.ID
    public let to: Place.ID

    public init(from: Place.ID, to: Place.ID) {
        self.from = from
        self.to = to
    }

    public init(_ segment: RouteSegment) {
        self.init(from: segment.from.place.id, to: segment.to.place.id)
    }

    /// 出発地と目的地を入れ替えたときの対応するキー。
    public var reversed: SegmentKey {
        SegmentKey(from: to, to: from)
    }
}

/// ユーザーがその区間について決めたこと。
///
/// 自動推定はこれを上書きしない。別の場所を編集しても、ここで決めた内容は残す。
public struct SegmentLock: Hashable, Sendable {
    /// 「ここは徒歩で行く」のように手段を決めた場合。
    public var mode: TransportMode?
    /// 選んだ便の時刻。
    public var timeAnchor: TimeAnchor?
    /// ユーザーが選んだときの区間の内容。再取得で一致しなくても、これを表示に残す。
    public var leg: RouteLeg?
    /// 選んだときの所要時間。
    ///
    /// MapKit は路線名を返さないが、経路が同じなら所要時間はほぼ変わらない。
    /// そこで所要時間を指紋として扱い、再取得時に同じ長さの便を選び直すことで
    /// 「ユーザーが選んだ経路」を保つ。
    public var duration: TimeInterval?

    public init(mode: TransportMode? = nil,
                timeAnchor: TimeAnchor? = nil,
                duration: TimeInterval? = nil,
                leg: RouteLeg? = nil) {
        self.mode = mode
        self.timeAnchor = timeAnchor
        self.duration = duration
        self.leg = leg
    }

    public var isEmpty: Bool {
        mode == nil && timeAnchor == nil && duration == nil && leg == nil
    }

    /// 所要時間が指紋と一致するとみなせるか。
    public func matchesDuration(_ candidate: TimeInterval, tolerance: DurationTolerance) -> Bool {
        guard let duration else { return true }
        return tolerance.matches(expected: duration, actual: candidate)
    }
}

/// 所要時間の一致判定。相対と絶対の緩い方を使う。
public struct DurationTolerance: Hashable, Sendable {
    public var relative: Double
    public var absolute: TimeInterval

    public init(relative: Double = 0.10, absolute: TimeInterval = 120) {
        self.relative = relative
        self.absolute = absolute
    }

    public static let `default` = DurationTolerance()

    public func matches(expected: TimeInterval, actual: TimeInterval) -> Bool {
        let allowed = max(expected * relative, absolute)
        return abs(actual - expected) <= allowed
    }
}

/// 「ユーザーが選んだ内容」と「今取得できる内容」の食い違い。
///
/// 勝手に置き換えると選択が取り消されたように見えるため、差分として提示し、
/// 更新するかどうかはユーザーに決めてもらう。
public struct PendingSegmentUpdate: Hashable, Sendable {
    public let key: SegmentKey
    /// ユーザーが選んだ内容（画面に出しているもの）。
    public let current: RouteLeg
    /// 今取得できる内容。
    public let proposed: RouteLeg

    public init(key: SegmentKey, current: RouteLeg, proposed: RouteLeg) {
        self.key = key
        self.current = current
        self.proposed = proposed
    }

    /// 提案を受け入れると所要時間がどれだけ変わるか。
    public var durationDelta: TimeInterval {
        proposed.expectedTravelTime - current.expectedTravelTime
    }

    public var isLonger: Bool { durationDelta > 0 }
}
