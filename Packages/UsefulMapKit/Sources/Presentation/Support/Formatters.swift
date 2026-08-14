import Domain
import Foundation

/// 比較カードの表示整形。
///
/// 文言はモジュールの Localizable.strings から引き、日付・時刻・数値は Foundation の
/// ロケール対応フォーマッタに任せる（12 時間制と 24 時間制の違いなどは自動で吸収される）。
/// テストで固定するため、すべての関数がロケールを引数に取る。
public enum Formatters {
    /// 所要時間 → "22分" / "1時間5分" / "22 min" / "1 hr 5 min"
    public static func duration(_ interval: TimeInterval, locale: Locale = .current) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let number = { (value: Int) in value.formatted(.number.locale(locale)) }

        if hours == 0 { return L10n.string("format.minutes", locale: locale, number(minutes)) }
        if minutes == 0 { return L10n.string("format.hours", locale: locale, number(hours)) }
        return L10n.string("format.hoursMinutes", locale: locale, number(hours), number(minutes))
    }

    /// 所要時間の数値部と単位を分けて返す（大きく表示するカード用）。
    public static func durationParts(_ interval: TimeInterval,
                                     locale: Locale = .current) -> (value: String, unit: String) {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        if totalMinutes < 60 {
            return (totalMinutes.formatted(.number.locale(locale)),
                    L10n.string("format.unit.minute", locale: locale))
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let unit = L10n.string("format.unit.hour", locale: locale)
        if minutes == 0 {
            return (hours.formatted(.number.locale(locale)), unit)
        }
        return ("\(hours):\(String(format: "%02d", minutes))", unit)
    }

    /// 時刻 → "10:32"（ロケールにより "10:32 AM" などになる）
    public static func clock(_ date: Date,
                             timeZone: TimeZone = .current,
                             locale: Locale = .current) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.locale = locale
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// 出発・到着 → "10:32 - 10:54"。どちらか欠ける場合は取得できた側だけ返す。
    public static func timeRange(departure: Date?,
                                 arrival: Date?,
                                 timeZone: TimeZone = .current,
                                 locale: Locale = .current) -> String? {
        switch (departure, arrival) {
        case let (departure?, arrival?):
            let start = clock(departure, timeZone: timeZone, locale: locale)
            let end = clock(arrival, timeZone: timeZone, locale: locale)
            return "\(start) - \(end)"
        case let (departure?, nil):
            return L10n.string("format.departure", locale: locale,
                               clock(departure, timeZone: timeZone, locale: locale))
        case let (nil, arrival?):
            return L10n.string("format.arrival", locale: locale,
                               clock(arrival, timeZone: timeZone, locale: locale))
        case (nil, nil):
            return nil
        }
    }

    /// 距離 → "450 m" / "1.2 km"。
    /// 日本国内での利用を前提に、表示ロケールに関わらずメートル法で統一する。
    public static func distance(_ meters: Double, locale: Locale = .current) -> String {
        guard meters.isFinite, meters >= 0 else { return "-" }
        let measurement = meters < 1_000
            ? Measurement(value: meters.rounded(), unit: UnitLength.meters)
            : Measurement(value: (meters / 1_000 * 10).rounded() / 10, unit: UnitLength.kilometers)
        return measurement.formatted(
            .measurement(width: .abbreviated,
                         usage: .asProvided,
                         numberFormatStyle: .number.precision(.fractionLength(meters < 1_000 ? 0 : 1)))
                .locale(locale)
        )
    }

    /// 履歴の相対日時 → "今日 9:32" / "昨日 18:15" / "8/12 7:41"
    public static func historyTimestamp(_ date: Date,
                                        now: Date = Date(),
                                        timeZone: TimeZone = .current,
                                        locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = clock(date, timeZone: timeZone, locale: locale)

        if calendar.isDate(date, inSameDayAs: now) {
            return L10n.string("format.today", locale: locale, time)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return L10n.string("format.yesterday", locale: locale, time)
        }
        var dayStyle = Date.FormatStyle.dateTime.month(.defaultDigits).day()
        dayStyle.locale = locale
        dayStyle.timeZone = timeZone
        let day = date.formatted(dayStyle)
        return "\(day) \(time)"
    }

    /// 経路条件の見出し → "現在地 → 東京駅"
    public static func routeTitle(origin: RouteEndpoint, destination: Place) -> String {
        "\(origin.displayName) → \(destination.displayName)"
    }
}
