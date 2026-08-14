import Domain
import Foundation
import Testing

@testable import Presentation

@Suite("Formatters")
struct FormattersTests {
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    /// 表示ロケールを固定する。実行環境の言語設定に結果が左右されないようにする。
    private let ja = Locale(identifier: "ja_JP")

    static let durationCases: [(seconds: Double, expected: String)] = [
        (0, "0分"),
        (59, "1分"),
        (1_320, "22分"),
        (3_600, "1時間"),
        (3_900, "1時間5分"),
        (7_200, "2時間")
    ]

    @Test("所要時間の表記", arguments: FormattersTests.durationCases)
    func duration(testCase: (seconds: Double, expected: String)) {
        #expect(Formatters.duration(testCase.seconds, locale: ja) == testCase.expected)
    }

    @Test("負の所要時間は 0 分として扱う")
    func negativeDuration() {
        #expect(Formatters.duration(-100, locale: ja) == "0分")
    }

    @Test("カード用に数値と単位を分けて返す")
    func durationParts() {
        #expect(Formatters.durationParts(22 * 60, locale: ja).value == "22")
        #expect(Formatters.durationParts(22 * 60, locale: ja).unit == "分")
        #expect(Formatters.durationParts(60 * 60, locale: ja).value == "1")
        #expect(Formatters.durationParts(60 * 60, locale: ja).unit == "時間")
        #expect(Formatters.durationParts(65 * 60, locale: ja).value == "1:05")
    }

    @Test("時刻は H:mm 表記")
    func clock() {
        #expect(Formatters.clock(TestFixtures.date(10, 32), timeZone: tokyo, locale: ja) == "10:32")
        #expect(Formatters.clock(TestFixtures.date(9, 5), timeZone: tokyo, locale: ja) == "9:05")
        #expect(Formatters.clock(TestFixtures.date(0, 0), timeZone: tokyo, locale: ja) == "0:00")
    }

    @Test("出発と到着が揃えばレンジ表記になる")
    func timeRangeBoth() {
        let range = Formatters.timeRange(departure: TestFixtures.date(10, 32),
                                         arrival: TestFixtures.date(10, 54),
                                         timeZone: tokyo,
                                         locale: ja)
        #expect(range == "10:32 - 10:54")
    }

    @Test("片側しか取得できない場合は取れた側だけ表示する")
    func timeRangePartial() {
        #expect(Formatters.timeRange(departure: TestFixtures.date(10, 32), arrival: nil,
                                     timeZone: tokyo, locale: ja) == "10:32 発")
        #expect(Formatters.timeRange(departure: nil, arrival: TestFixtures.date(10, 54),
                                     timeZone: tokyo, locale: ja) == "10:54 着")
        #expect(Formatters.timeRange(departure: nil, arrival: nil, timeZone: tokyo, locale: ja) == nil)
    }

    static let distanceCases: [(meters: Double, expected: String)] = [
        (0, "0 m"),
        (450, "450 m"),
        (999, "999 m"),
        (1_000, "1.0 km"),
        (6_200, "6.2 km")
    ]

    @Test("距離の表記", arguments: FormattersTests.distanceCases)
    func distance(testCase: (meters: Double, expected: String)) {
        #expect(Formatters.distance(testCase.meters, locale: ja) == testCase.expected)
    }

    @Test("不正な距離はプレースホルダを返す")
    func invalidDistance() {
        #expect(Formatters.distance(.nan, locale: ja) == "-")
        #expect(Formatters.distance(-1, locale: ja) == "-")
    }

    @Test("履歴の日時は 今日 / 昨日 / 日付 で表す")
    func historyTimestamp() {
        let now = TestFixtures.date(12, 0, day: 14)
        #expect(Formatters.historyTimestamp(TestFixtures.date(9, 32, day: 14),
                                            now: now, timeZone: tokyo, locale: ja) == "今日 9:32")
        #expect(Formatters.historyTimestamp(TestFixtures.date(18, 15, day: 13),
                                            now: now, timeZone: tokyo, locale: ja) == "昨日 18:15")
        #expect(Formatters.historyTimestamp(TestFixtures.date(7, 41, day: 12),
                                            now: now, timeZone: tokyo, locale: ja) == "8/12 7:41")
    }

    @Test("経路見出しは 出発地 → 目的地")
    func routeTitle() {
        // 「現在地」は表示ロケールで変わるため、モデル側の表示名を基準に組み立てて比較する。
        let currentLocation = RouteEndpoint.currentLocation.displayName
        #expect(Formatters.routeTitle(origin: .currentLocation, destination: TestFixtures.tokyo)
                == "\(currentLocation) → 東京駅")
        #expect(Formatters.routeTitle(origin: .place(TestFixtures.shinjuku), destination: TestFixtures.tokyo)
                == "新宿御苑 → 東京駅")
    }
}
