import Domain
import Foundation
import Testing

@testable import Presentation

@Suite("Formatters")
struct FormattersTests {
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

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
        #expect(Formatters.duration(testCase.seconds) == testCase.expected)
    }

    @Test("負の所要時間は 0 分として扱う")
    func negativeDuration() {
        #expect(Formatters.duration(-100) == "0分")
    }

    @Test("カード用に数値と単位を分けて返す")
    func durationParts() {
        #expect(Formatters.durationParts(22 * 60).value == "22")
        #expect(Formatters.durationParts(22 * 60).unit == "分")
        #expect(Formatters.durationParts(60 * 60).value == "1")
        #expect(Formatters.durationParts(60 * 60).unit == "時間")
        #expect(Formatters.durationParts(65 * 60).value == "1:05")
    }

    @Test("時刻は H:mm 表記")
    func clock() {
        #expect(Formatters.clock(TestFixtures.date(10, 32), timeZone: tokyo) == "10:32")
        #expect(Formatters.clock(TestFixtures.date(9, 5), timeZone: tokyo) == "9:05")
        #expect(Formatters.clock(TestFixtures.date(0, 0), timeZone: tokyo) == "0:00")
    }

    @Test("出発と到着が揃えばレンジ表記になる")
    func timeRangeBoth() {
        let range = Formatters.timeRange(departure: TestFixtures.date(10, 32),
                                         arrival: TestFixtures.date(10, 54),
                                         timeZone: tokyo)
        #expect(range == "10:32 - 10:54")
    }

    @Test("片側しか取得できない場合は取れた側だけ表示する")
    func timeRangePartial() {
        #expect(Formatters.timeRange(departure: TestFixtures.date(10, 32), arrival: nil, timeZone: tokyo)
                == "10:32 発")
        #expect(Formatters.timeRange(departure: nil, arrival: TestFixtures.date(10, 54), timeZone: tokyo)
                == "10:54 着")
        #expect(Formatters.timeRange(departure: nil, arrival: nil, timeZone: tokyo) == nil)
    }

    static let distanceCases: [(meters: Double, expected: String)] = [
        (0, "0m"),
        (450, "450m"),
        (999, "999m"),
        (1_000, "1.0km"),
        (6_200, "6.2km")
    ]

    @Test("距離の表記", arguments: FormattersTests.distanceCases)
    func distance(testCase: (meters: Double, expected: String)) {
        #expect(Formatters.distance(testCase.meters) == testCase.expected)
    }

    @Test("不正な距離はプレースホルダを返す")
    func invalidDistance() {
        #expect(Formatters.distance(.nan) == "-")
        #expect(Formatters.distance(-1) == "-")
    }

    @Test("履歴の日時は 今日 / 昨日 / 日付 で表す")
    func historyTimestamp() {
        let now = TestFixtures.date(12, 0, day: 14)
        #expect(Formatters.historyTimestamp(TestFixtures.date(9, 32, day: 14), now: now, timeZone: tokyo)
                == "今日 9:32")
        #expect(Formatters.historyTimestamp(TestFixtures.date(18, 15, day: 13), now: now, timeZone: tokyo)
                == "昨日 18:15")
        #expect(Formatters.historyTimestamp(TestFixtures.date(7, 41, day: 12), now: now, timeZone: tokyo)
                == "8/12 7:41")
    }

    @Test("経路見出しは 出発地 → 目的地")
    func routeTitle() {
        #expect(Formatters.routeTitle(origin: .currentLocation, destination: TestFixtures.tokyo)
                == "現在地 → 東京駅")
        #expect(Formatters.routeTitle(origin: .place(TestFixtures.shinjuku), destination: TestFixtures.tokyo)
                == "新宿御苑 → 東京駅")
    }
}
