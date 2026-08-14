import XCTest

/// E2E（XCUITest）。
///
/// MapKit / Core Location / 外部遷移はアプリ側の `-UITestMode` でスタブへ差し替わるため、
/// ネットワークにも実機の位置情報にも依存せず、シミュレータ内で完結して決定的に動く。
/// 単体テストが層ごとの契約を守るのに対し、ここでは「画面をまたいだ導線」だけを検証する。
final class UsefulMapUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(scenario: String = "standard") {
        app.launchArguments = ["-UITestMode", "-UITestScenario", scenario]
        app.launch()
    }

    private func timeout() -> TimeInterval { 20 }

    // MARK: - ヘルパ

    /// 地図ホーム → 検索 → 東京駅を選択 → 場所詳細まで進む。
    private func searchAndOpenTokyoStation() {
        let searchField = app.buttons[A11y.searchField]
        XCTAssertTrue(searchField.waitForExistence(timeout: timeout()), "検索フィールドが表示されない")
        searchField.tap()

        let input = app.textFields[A11y.searchField]
        XCTAssertTrue(input.waitForExistence(timeout: timeout()), "検索入力が表示されない")
        input.tap()
        input.typeText("東京駅")

        let firstResult = app.otherElements[A11y.searchResult(0)]
            .firstMatch
        let fallback = app.staticTexts["東京駅"].firstMatch
        if firstResult.waitForExistence(timeout: 5) {
            firstResult.tap()
        } else {
            XCTAssertTrue(fallback.waitForExistence(timeout: timeout()), "検索結果が表示されない")
            fallback.tap()
        }

        XCTAssertTrue(app.staticTexts[A11y.placeTitle].waitForExistence(timeout: timeout()),
                      "場所詳細が表示されない")
    }

    /// 場所詳細 → 経路比較。
    private func openRouteCompare() {
        let routeButton = app.buttons[A11y.routeButton]
        XCTAssertTrue(routeButton.waitForExistence(timeout: timeout()), "経路ボタンが無い")
        routeButton.tap()
    }

    // MARK: - E2E 1: 検索から移動手段比較まで

    func testSearchToRouteComparison() {
        launch()
        searchAndOpenTokyoStation()
        openRouteCompare()

        let firstCard = app.otherElements[A11y.routeCard(0)]
        XCTAssertTrue(firstCard.waitForExistence(timeout: timeout()), "比較カードが表示されない")

        // 公共交通は所要時間に加えて出発 / 到着時刻を表示する（受け入れ条件 15）。
        XCTAssertTrue(app.staticTexts["22"].exists, "所要時間が表示されていない")
        XCTAssertTrue(app.staticTexts["10:32 - 10:54"].waitForExistence(timeout: timeout()),
                      "出発 / 到着時刻が表示されていない")

        // 運賃・乗換回数を Useful Map 自身が推定・表示しないこと（受け入れ条件 15）。
        // 注意書きの文言ではなく「値」が出ていないことを見る。
        let fare = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*[¥￥][0-9].*"))
        XCTAssertEqual(fare.count, 0, "運賃が表示されている")
        let transfers = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*乗換 ?[0-9]+ ?回.*"))
        XCTAssertEqual(transfers.count, 0, "乗換回数が表示されている")
    }

    // MARK: - E2E 2: 移動手段の切り替え

    func testSwitchingTransportModeUpdatesComparison() {
        launch()
        searchAndOpenTokyoStation()
        openRouteCompare()

        XCTAssertTrue(app.otherElements[A11y.routeCard(0)].waitForExistence(timeout: timeout()))

        // 「最適」で全モード横断比較。所要時間順に 公共交通 22 分 → 車 26 分 → 徒歩 62 分。
        app.buttons[A11y.modeFilter("all")].tap()
        XCTAssertTrue(app.otherElements[A11y.routeCard(2)].waitForExistence(timeout: timeout()),
                      "全モードの候補が並ばない")
        XCTAssertEqual(app.otherElements[A11y.routeCard(0)].label, "公共交通 22分")
        XCTAssertEqual(app.otherElements[A11y.routeCard(2)].label, "徒歩 1時間2分")

        // 徒歩だけに絞ると候補が 1 件になる。
        app.buttons[A11y.modeFilter("walking")].tap()
        XCTAssertTrue(app.otherElements[A11y.routeCard(0)].waitForExistence(timeout: timeout()))
        XCTAssertEqual(app.otherElements[A11y.routeCard(0)].label, "徒歩 1時間2分")
        XCTAssertFalse(app.otherElements[A11y.routeCard(1)].exists, "徒歩以外の候補が残っている")
    }

    // MARK: - E2E 3: 公共交通の詳細 → Google Maps へ時刻付きで遷移

    func testTransitDetailOpensTimedGoogleMapsURL() {
        launch()
        searchAndOpenTokyoStation()
        openRouteCompare()

        let detailButton = app.buttons[A11y.detailButton(0)]
        XCTAssertTrue(detailButton.waitForExistence(timeout: timeout()), "詳細ボタンが無い")
        detailButton.tap()

        let status = app.descendants(matching: .any)[A11y.lastOpenedURL].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: timeout()), "遷移結果が表示されない")

        let url = status.value as? String ?? ""
        XCTAssertTrue(url.hasPrefix("https://www.google.com/maps/dir/"), "生成 URL が想定と違う: \(url)")
        // 時刻付き内部形式（出発時刻指定 10:32 JST = !8j1786703520）。
        XCTAssertTrue(url.contains("/data="), "時刻付き Primary URL になっていない: \(url)")
        XCTAssertTrue(url.contains("!6e0"), "出発時刻指定になっていない: \(url)")
        XCTAssertTrue(url.contains("!8j1786703520"), "指定した出発時刻が反映されていない: \(url)")
        XCTAssertTrue(url.hasSuffix("!3e3"), "公共交通モードになっていない: \(url)")
    }

    // MARK: - E2E 4: Primary URL が壊れたときの公式 URL fallback

    func testFallsBackToOfficialURLWhenPrimaryFails() {
        launch(scenario: "primaryURLBroken")
        searchAndOpenTokyoStation()
        openRouteCompare()

        let detailButton = app.buttons[A11y.detailButton(0)]
        XCTAssertTrue(detailButton.waitForExistence(timeout: timeout()))
        detailButton.tap()

        let status = app.descendants(matching: .any)[A11y.lastOpenedURL].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: timeout()))

        let url = status.value as? String ?? ""
        XCTAssertFalse(url.contains("/data="), "Primary URL のままになっている: \(url)")
        XCTAssertTrue(url.contains("api=1"), "公式 URL へ fallback していない: \(url)")
        XCTAssertTrue(url.contains("travelmode=transit"), "移動手段が引き継がれていない: \(url)")
        XCTAssertTrue(url.contains("destination=35.6812362,139.7671248"), "目的地が引き継がれていない: \(url)")
    }

    // MARK: - E2E 5: 経路 0 件でも比較機能自体は壊れない

    func testShowsEmptyStateWhenNoRoutes() {
        launch(scenario: "noRoutes")
        searchAndOpenTokyoStation()
        openRouteCompare()

        let error = app.staticTexts["経路を取得できません"]
        XCTAssertTrue(error.waitForExistence(timeout: timeout()), "経路なしの案内が出ない")
        // 条件編集への導線は残っている。
        XCTAssertTrue(app.buttons[A11y.editRouteButton].exists, "経路編集へ戻れない")
    }

    // MARK: - E2E 6: 保存と履歴が端末内に残る

    func testSavingPlaceAndRouteHistory() {
        launch()
        searchAndOpenTokyoStation()

        let saveButton = app.buttons[A11y.saveButton]
        XCTAssertTrue(saveButton.waitForExistence(timeout: timeout()))
        saveButton.tap()
        // confirmationDialog のボタンは階層上に二重に現れるため firstMatch で解決する。
        app.buttons[A11y.saveLabelOption("other")].firstMatch.tap()

        openRouteCompare()
        XCTAssertTrue(app.otherElements[A11y.routeCard(0)].waitForExistence(timeout: timeout()))

        app.tabBars.buttons["保存"].tap()

        XCTAssertTrue(app.buttons[A11y.savedPlace(0)].waitForExistence(timeout: timeout()),
                      "保存地点が一覧に出ない")
        XCTAssertTrue(app.buttons[A11y.recentRoute(0)].waitForExistence(timeout: timeout()),
                      "最近の経路が記録されていない")
        XCTAssertTrue(app.staticTexts["現在地 → 東京駅"].exists, "経路履歴の内容が違う")
    }

    // MARK: - E2E 7: 自宅ラベルを付けて保存し、地図ホームから再利用する

    func testSavingPlaceWithHomeLabel() {
        launch()
        searchAndOpenTokyoStation()

        let saveButton = app.buttons[A11y.saveButton]
        XCTAssertTrue(saveButton.waitForExistence(timeout: timeout()))
        saveButton.tap()

        // 保存時にラベルを選ぶ。
        let homeOption = app.buttons[A11y.saveLabelOption("home")].firstMatch
        XCTAssertTrue(homeOption.waitForExistence(timeout: timeout()), "ラベル選択が出ない")
        homeOption.tap()

        // 場所詳細のボタンがラベル表示に変わる。
        XCTAssertTrue(app.buttons["自宅"].waitForExistence(timeout: timeout()), "保存後のラベルが反映されない")

        // 場所詳細シートを閉じてからタブを移動する。
        app.buttons["閉じる"].firstMatch.tap()

        // 保存タブにラベル付きで並ぶ。
        app.tabBars.buttons["保存"].tap()
        XCTAssertTrue(app.buttons[A11y.savedPlace(0)].waitForExistence(timeout: timeout()))
        XCTAssertTrue(app.staticTexts["自宅"].exists, "保存一覧にラベルが出ない")
        XCTAssertTrue(app.buttons[A11y.savedPlaceMenu(0)].exists, "ラベル変更メニューが無い")

        // 地図ホームのクイックチップからも再利用できる（モック S01）。
        app.tabBars.buttons["地図"].tap()
        XCTAssertTrue(app.buttons[A11y.savedPlace(0)].waitForExistence(timeout: timeout()),
                      "地図ホームに保存地点のチップが出ない")
    }
}

/// Presentation の A11y 識別子と同じ値。
/// UI テストターゲットはアプリのモジュールを import しないため、ここで定義を持つ。
/// （値がずれた場合は E2E が落ちるので、実質的な同期チェックになる）
enum A11y {
    static let searchField = "search.field"
    static let placeTitle = "placeDetail.title"
    static let routeButton = "placeDetail.route"
    static let saveButton = "placeDetail.save"
    static let editRouteButton = "routeCompare.edit"
    static let lastOpenedURL = "debug.lastOpenedURL"

    static func saveLabelOption(_ label: String) -> String { "placeDetail.saveLabel.\(label)" }
    static func savedPlaceMenu(_ index: Int) -> String { "saved.place.menu.\(index)" }
    static func searchResult(_ index: Int) -> String { "search.result.\(index)" }
    static func modeFilter(_ id: String) -> String { "routeCompare.mode.\(id)" }
    static func routeCard(_ index: Int) -> String { "routeCompare.card.\(index)" }
    static func detailButton(_ index: Int) -> String { "routeCompare.detail.\(index)" }
    static func savedPlace(_ index: Int) -> String { "saved.place.\(index)" }
    static func recentRoute(_ index: Int) -> String { "saved.route.\(index)" }
}
