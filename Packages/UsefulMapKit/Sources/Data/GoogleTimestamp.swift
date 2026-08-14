import Foundation

/// Google Maps 内部 URL の `!8j` 値を作る（仕様書 7.3）。
///
/// 実測では `!8j` は「ローカル表示したい年月日時分を、そのまま UTC の壁時計として epoch 化した値」と
/// 一致した。`Date.timeIntervalSince1970` をそのまま入れると表示時刻がタイムゾーン分ずれるため、
/// 変換をこの型だけに隔離し、固定 fixture で回帰テストする。
public enum GoogleTimestamp {
    /// - Parameters:
    ///   - date: 絶対時刻。
    ///   - timeZone: その絶対時刻を「何時として見せたいか」を決めるタイムゾーン。
    public static func value(for date: Date, timeZone: TimeZone) -> Int {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        let wallClock = localCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = utc
        var components = DateComponents()
        components.year = wallClock.year
        components.month = wallClock.month
        components.day = wallClock.day
        components.hour = wallClock.hour
        components.minute = wallClock.minute
        components.second = 0

        guard let shifted = utcCalendar.date(from: components) else {
            // 変換できないケースは実質存在しないが、壊れるより素の epoch を返す。
            return Int(date.timeIntervalSince1970.rounded(.down))
        }
        return Int(shifted.timeIntervalSince1970)
    }

    /// `!8j` 値を元の壁時計時刻へ戻す（契約監視の期待値検証・デバッグ用）。
    public static func wallClockComponents(from value: Int) -> DateComponents {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = utc
        let date = Date(timeIntervalSince1970: TimeInterval(value))
        return utcCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    private static let utc = TimeZone(secondsFromGMT: 0) ?? .gmt
}
