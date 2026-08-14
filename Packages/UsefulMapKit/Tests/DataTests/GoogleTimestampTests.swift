import Foundation
import Testing

@testable import Data

@Suite("GoogleTimestamp（!8j 値）")
struct GoogleTimestampTests {
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let newYork = TimeZone(identifier: "America/New_York")!

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int, _ minute: Int, in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                  hour: hour, minute: minute))!
    }

    @Test("JST 10:32 は 2026-08-14T10:32Z の epoch になる（固定 fixture）")
    func tokyoGolden() {
        let value = GoogleTimestamp.value(for: date(2026, 8, 14, 10, 32, in: tokyo), timeZone: tokyo)
        #expect(value == 1_786_703_520)
    }

    @Test("到着時刻 fixture も一致する")
    func tokyoArrivalGolden() {
        let value = GoogleTimestamp.value(for: date(2026, 8, 14, 10, 54, in: tokyo), timeZone: tokyo)
        #expect(value == 1_786_704_840)
    }

    @Test("Date.timeIntervalSince1970 をそのまま使った値とは異なる（取り違え防止）")
    func differsFromRawEpoch() {
        let moment = date(2026, 8, 14, 10, 32, in: tokyo)
        let value = GoogleTimestamp.value(for: moment, timeZone: tokyo)
        // JST 10:32 の実時刻は UTC 01:32 なので、素の epoch は 9 時間ぶん小さい。
        #expect(Int(moment.timeIntervalSince1970) == value - 9 * 3_600)
    }

    @Test("同じ壁時計時刻なら、タイムゾーンが違っても同じ !8j 値になる")
    func wallClockIsWhatMatters() {
        let tokyoValue = GoogleTimestamp.value(for: date(2026, 8, 14, 10, 32, in: tokyo), timeZone: tokyo)
        let newYorkValue = GoogleTimestamp.value(for: date(2026, 8, 14, 10, 32, in: newYork), timeZone: newYork)
        #expect(tokyoValue == newYorkValue)
    }

    @Test("UTC では素の epoch と一致する（秒は切り捨て）")
    func utcMatchesRawEpoch() {
        let moment = date(2026, 1, 1, 0, 0, in: utc)
        #expect(GoogleTimestamp.value(for: moment, timeZone: utc) == 1_767_225_600)
        #expect(GoogleTimestamp.value(for: moment, timeZone: utc) == Int(moment.timeIntervalSince1970))
    }

    @Test("秒は切り捨てられ、分単位の値になる")
    func dropsSeconds() {
        let base = date(2026, 8, 14, 10, 32, in: tokyo)
        let withSeconds = base.addingTimeInterval(45)
        #expect(GoogleTimestamp.value(for: withSeconds, timeZone: tokyo)
                == GoogleTimestamp.value(for: base, timeZone: tokyo))
    }

    @Test("日付境界（23:59）でも壁時計がずれない")
    func dayBoundary() {
        let value = GoogleTimestamp.value(for: date(2026, 8, 14, 23, 59, in: tokyo), timeZone: tokyo)
        #expect(value == 1_786_751_940)
    }

    @Test("!8j 値から壁時計成分へ戻せる（契約監視の期待値検証用）")
    func roundTripToComponents() {
        let value = GoogleTimestamp.value(for: date(2026, 8, 14, 10, 32, in: tokyo), timeZone: tokyo)
        let components = GoogleTimestamp.wallClockComponents(from: value)
        #expect(components.year == 2026)
        #expect(components.month == 8)
        #expect(components.day == 14)
        #expect(components.hour == 10)
        #expect(components.minute == 32)
    }
}
