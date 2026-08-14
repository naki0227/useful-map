import Domain
import Foundation

/// 比較カードの表示整形。ロケール差で表示が揺れないよう日本語表記を固定で組み立てる。
public enum Formatters {
    /// 所要時間 → "22分" / "1時間5分" / "2時間"
    public static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)分" }
        if minutes == 0 { return "\(hours)時間" }
        return "\(hours)時間\(minutes)分"
    }

    /// 所要時間の数値部と単位を分けて返す（大きく表示するカード用）。
    public static func durationParts(_ interval: TimeInterval) -> (value: String, unit: String) {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        if totalMinutes < 60 { return ("\(totalMinutes)", "分") }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? ("\(hours)", "時間") : ("\(hours):\(String(format: "%02d", minutes))", "時間")
    }

    /// 時刻 → "10:32"
    public static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return "\(hour):\(String(format: "%02d", minute))"
    }

    /// 出発・到着 → "10:32 - 10:54"。どちらか欠ける場合は取得できた側だけ返す。
    public static func timeRange(departure: Date?, arrival: Date?, timeZone: TimeZone = .current) -> String? {
        switch (departure, arrival) {
        case let (departure?, arrival?):
            return "\(clock(departure, timeZone: timeZone)) - \(clock(arrival, timeZone: timeZone))"
        case let (departure?, nil):
            return "\(clock(departure, timeZone: timeZone)) 発"
        case let (nil, arrival?):
            return "\(clock(arrival, timeZone: timeZone)) 着"
        case (nil, nil):
            return nil
        }
    }

    /// 距離 → "450m" / "1.2km"
    public static func distance(_ meters: Double) -> String {
        guard meters.isFinite, meters >= 0 else { return "-" }
        if meters < 1_000 { return "\(Int(meters.rounded()))m" }
        return String(format: "%.1fkm", meters / 1_000)
    }

    /// 履歴の相対日時 → "今日 9:32" / "昨日 18:15" / "8/12 7:41"
    public static func historyTimestamp(_ date: Date,
                                        now: Date = Date(),
                                        timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = clock(date, timeZone: timeZone)
        if calendar.isDate(date, inSameDayAs: now) { return "今日 \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨日 \(time)"
        }
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0) \(time)"
    }

    /// 経路条件の見出し → "現在地 → 東京駅"
    public static func routeTitle(origin: RouteEndpoint, destination: Place) -> String {
        "\(origin.displayName) → \(destination.displayName)"
    }
}
