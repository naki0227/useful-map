import Foundation

/// テスト全体で使う固定日時ヘルパ。実行環境のタイムゾーンに影響されないようにする。
enum TestDates {
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    static let utc = TimeZone(secondsFromGMT: 0)!

    static func make(_ year: Int,
                     _ month: Int,
                     _ day: Int,
                     _ hour: Int = 0,
                     _ minute: Int = 0,
                     timeZone: TimeZone = tokyo) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                  hour: hour, minute: minute))!
    }
}
