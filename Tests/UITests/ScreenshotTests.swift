import XCTest

/// App Store 提出用のスクリーンショットを撮る。
///
/// `-UITestMode` で起動してデータを固定するため、実行のたびに同じ画面になる。
/// 撮影結果はテスト結果（xcresult）の添付として残り、`make screenshots` が書き出す。
///
/// E2E とは目的が違う（検証しない）ので、通常のテスト実行では
/// `-skip-testing:UsefulMapUITests/ScreenshotTests` で外す。
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-UITestScenario", "standard"]
        app.launch()
    }

    /// 画面を撮って添付する。名前がそのままファイル名になる。
    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func wait(_ element: XCUIElement, _ seconds: TimeInterval = 20) {
        XCTAssertTrue(element.waitForExistence(timeout: seconds), "要素が出ない: \(element)")
    }

    func testCaptureAppStoreScreenshots() {
        // 1. 地図ホーム（検索前に条件を決められる）
        wait(app.buttons[A11y.searchField])
        capture("01-map-home")

        // 2. 目的地の検索（その場で候補が出る）
        app.buttons[A11y.searchField].tap()
        let field = app.textFields[A11y.nodeField(1)]
        wait(field)
        field.tap()
        field.typeText("東京駅")
        wait(app.buttons[A11y.searchResult(0)].firstMatch)
        capture("02-search")

        // 3. 区間に分かれた経路
        app.buttons[A11y.searchResult(0)].firstMatch.tap()
        wait(app.buttons[A11y.node(0)])
        wait(app.descendants(matching: .any)[A11y.planTotal].firstMatch)
        capture("03-route-segments")

        // 4. 区間ごとの編集（経由地の追加欄を開いた状態）
        app.buttons[A11y.addWaypoint(0)].tap()
        wait(app.textFields[A11y.nodeField(0)])
        capture("04-route-edit")
        app.buttons[A11y.closeRouteButton].tap()

        // 5. 保存とラベル
        wait(app.buttons[A11y.searchField])
        app.buttons[A11y.searchField].tap()
        let again = app.textFields[A11y.nodeField(1)]
        wait(again)
        again.tap()
        again.typeText("東京駅")
        wait(app.buttons[A11y.searchResult(0)].firstMatch)
        app.buttons[A11y.searchResult(0)].firstMatch.tap()
        wait(app.buttons[A11y.node(0)])
        app.buttons[A11y.closeRouteButton].tap()

        tapSavedTab()
        wait(app.staticTexts.firstMatch)
        capture("05-saved")
    }

    /// 保存タブへ移動する。
    /// iPadOS はフローティングタブバーで要素が Cell として出るため、型を限定せず識別子で引く。
    private func tapSavedTab() {
        let saved = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "bookmark"))
            .firstMatch
        wait(saved)
        saved.tap()
    }
}
