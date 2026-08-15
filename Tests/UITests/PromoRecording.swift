import XCTest

/// PV 用の操作を再生する。検証が目的ではないので、通常のテスト実行からは外す。
///
/// `-UITestMode` を付けない。スタブではなく本物の MapKit で動かし、
/// 実際に返ってくる経路をそのまま映すため。
/// 現在地は `xcrun simctl location` で外から与える（東京ディズニーランド）。
final class PromoRecording: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
    }

    /// 画面の変化を追える間を置く。人が読める速さにするため。
    private func beat(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func wait(_ element: XCUIElement, _ seconds: TimeInterval = 30) {
        XCTAssertTrue(element.waitForExistence(timeout: seconds), "要素が出ない: \(element)")
    }

    /// 東京ディズニーランドから道頓堀まで。
    /// 長距離なので公共交通の計算に時間がかかる。待たずに次を触ると計算中の画が撮れてしまう。
    func testRecordTokyoDisneylandToDotonbori() {
        wait(app.buttons[A11y.searchField])
        beat(2.5)

        app.buttons[A11y.searchField].tap()
        let field = app.textFields[A11y.nodeField(1)]
        wait(field)
        field.tap()
        // 一文字ずつ打ち、候補が絞られる様子を見せる。
        for character in "道頓堀" {
            field.typeText(String(character))
            beat(0.6)
        }
        beat(1.5)

        let result = app.buttons[A11y.searchResult(0)].firstMatch
        wait(result)
        result.tap()

        // 区間に分かれるまで待つ。到着側の駅ノードが出たら組み上がっている。
        wait(app.buttons[A11y.node(0)], 90)
        wait(app.buttons[A11y.node(2)], 90)
        wait(app.descendants(matching: .any)[A11y.planTotal].firstMatch, 90)
        // 徒歩 → 電車 → 徒歩 と分かれた行程を読ませる。
        beat(6)

        // 公共交通の区間だけ Google マップへ渡す。運賃と乗換はあちらで見る、という導線。
        let detail = app.buttons[A11y.detailButton(1)]
        wait(detail)
        detail.tap()

        // Safari が開いて Google マップが表示されるまで映す。
        beat(12)
    }
}
