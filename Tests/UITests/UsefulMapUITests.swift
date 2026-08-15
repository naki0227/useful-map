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

    /// タブは iPadOS 26 だとフローティングタブバーになり TabBar / Button 配下に来ないため、
    /// 型を限定せずに引く。ラベル（地図）は地図キャンバスとぶつかるので識別子で引く。
    private func tab(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
    }

    /// 地図ホームの下書き欄で目的地に東京駅を入れる。
    ///
    /// 目的地を選んだ時点で経路が組み上がる。場所詳細を経由しないのは、
    /// 検索前に出発地と時刻を決める画面（RouteDraftView）が入口になったため。
    private func startRouteToTokyoStation() {
        let destination = app.buttons[A11y.searchField]
        XCTAssertTrue(destination.waitForExistence(timeout: timeout()), "目的地の欄が表示されない")
        destination.tap()

        // 押すとその場で入力欄に変わる。目的地は 2 番目のノード。
        let input = app.textFields[A11y.nodeField(1)]
        XCTAssertTrue(input.waitForExistence(timeout: timeout()), "目的地の入力欄が開かない")
        input.tap()
        input.typeText("東京駅")

        let result = app.buttons[A11y.searchResult(0)].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: timeout()), "検索結果が表示されない")
        result.tap()

        XCTAssertTrue(app.buttons[A11y.node(0)].waitForExistence(timeout: timeout()),
                      "目的地を選んでも経路が出ない")
    }

    // MARK: - E2E 1: 検索から区間分割された経路まで

    func testSearchToSegmentedRoute() {
        launch()
        startRouteToTokyoStation()

        // 地図タブのまま、上部にノードの連鎖が出る。
        XCTAssertTrue(app.buttons[A11y.node(0)].waitForExistence(timeout: timeout()),
                      "出発地のノードが表示されない")
        XCTAssertTrue(app.buttons[A11y.node(1)].waitForExistence(timeout: timeout()),
                      "区間が分割されていない（駅ノードが無い）")

        // 区間ごとに移動手段のアイコンが並ぶ。
        XCTAssertTrue(app.buttons[A11y.segmentMode(0)].exists, "区間 0 のモードアイコンが無い")
        XCTAssertTrue(app.buttons[A11y.segmentMode(1)].exists, "区間 1 のモードアイコンが無い")

        // 下部に合計時間が出る。
        XCTAssertTrue(app.descendants(matching: .any)[A11y.planTotal].firstMatch.waitForExistence(timeout: timeout()),
                      "合計時間が表示されない")

        // 地図タブから移動していない。
        XCTAssertTrue(app.buttons["map"].isSelected, "経路のためにタブが切り替わっている")

        // 運賃・乗換回数を Useful Map 自身が推定・表示しないこと。
        let fare = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", ".*[¥￥][0-9].*"))
        XCTAssertEqual(fare.count, 0, "運賃が表示されている")
    }

    // MARK: - E2E 2: 矢印のアイコンで区間ごとに移動手段を変える

    func testTogglingSegmentMode() {
        launch()
        startRouteToTokyoStation()

        let modeButton = app.buttons[A11y.segmentMode(0)]
        XCTAssertTrue(modeButton.waitForExistence(timeout: timeout()))
        let before = modeButton.label

        modeButton.tap()

        // 押すだけで切り替わる（別画面を出さない）。
        let changed = NSPredicate(format: "label != %@", before)
        expectation(for: changed, evaluatedWith: modeButton)
        waitForExpectations(timeout: timeout())
        XCTAssertNotEqual(modeButton.label, before, "移動手段が切り替わっていない")
    }

    // MARK: - E2E 3: 別画面を出さずに地点を編集する

    func testInlinePlaceEditing() {
        launch()
        startRouteToTokyoStation()

        let node = app.buttons[A11y.node(0)]
        XCTAssertTrue(node.waitForExistence(timeout: timeout()))
        node.tap()

        // その場で入力欄が開く。
        let field = app.textFields[A11y.nodeField(0)]
        XCTAssertTrue(field.waitForExistence(timeout: timeout()), "インライン入力欄が出ない")

        // 上部の連鎖はそのまま残っている（画面遷移していない）。
        XCTAssertTrue(app.buttons[A11y.segmentMode(0)].exists, "編集で画面が置き換わっている")

        field.tap()
        field.typeText("新宿")
        // インライン候補は List ではなくボタンとして並ぶ。
        let result = app.buttons[A11y.searchResult(0)].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: timeout()), "候補がその場に出ない")
        result.tap()

        XCTAssertFalse(app.textFields[A11y.nodeField(0)].exists, "選択後に入力欄が閉じない")
    }

    // MARK: - E2E 4: 徒歩ペースをボタン 1 つで切り替える

    func testWalkingPaceToggle() {
        launch()
        startRouteToTokyoStation()

        let paceButton = app.buttons[A11y.walkingPaceButton]
        XCTAssertTrue(paceButton.waitForExistence(timeout: timeout()), "徒歩ペースのボタンが無い")
        let before = paceButton.label

        paceButton.tap()

        let changed = NSPredicate(format: "label != %@", before)
        expectation(for: changed, evaluatedWith: paceButton)
        waitForExpectations(timeout: timeout())
        XCTAssertNotEqual(paceButton.label, before, "徒歩ペースが切り替わっていない")
    }

    // MARK: - E2E 5: 公共交通の詳細 → Google Maps へ時刻付きで遷移

    func testOpensTimedGoogleMapsURL() {
        launch()
        startRouteToTokyoStation()

        // 区間ごとに詳細がある。区間 1（公共交通）の詳細を開く。
        let detailButton = app.buttons[A11y.detailButton(1)]
        XCTAssertTrue(detailButton.waitForExistence(timeout: timeout()), "区間の詳細ボタンが無い")
        detailButton.tap()

        let status = app.descendants(matching: .any)[A11y.lastOpenedURL].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: timeout()), "遷移結果が表示されない")

        let url = status.value as? String ?? ""
        XCTAssertTrue(url.hasPrefix("https://www.google.com/maps/dir/"), "生成 URL が想定と違う: \(url)")
        XCTAssertTrue(url.contains("/data="), "時刻付き Primary URL になっていない: \(url)")
        XCTAssertTrue(url.contains("!6e0"), "出発時刻指定になっていない: \(url)")
        XCTAssertTrue(url.hasSuffix("!3e3"), "公共交通モードになっていない: \(url)")
        // 区間は 2 地点なので、地点ブロックは 2 つ（Google は公共交通の経由地を扱えない）。
        XCTAssertEqual(url.components(separatedBy: "!1m3!2m2!1d").count - 1, 2,
                       "区間の詳細に経由地が混ざっている: \(url)")
        // Place ID を入れると Google が地点を解決できなくなる。
        XCTAssertFalse(url.contains("!1s"), "Place ID が混ざっている: \(url)")
    }

    // MARK: - E2E 6: Primary URL が壊れたときの公式 URL fallback

    func testFallsBackToOfficialURL() {
        launch(scenario: "primaryURLBroken")
        startRouteToTokyoStation()

        let detailButton = app.buttons[A11y.detailButton(1)]
        XCTAssertTrue(detailButton.waitForExistence(timeout: timeout()))
        detailButton.tap()

        let status = app.descendants(matching: .any)[A11y.lastOpenedURL].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: timeout()))

        let url = status.value as? String ?? ""
        XCTAssertFalse(url.contains("/data="), "Primary URL のままになっている: \(url)")
        XCTAssertTrue(url.contains("api=1"), "公式 URL へ fallback していない: \(url)")
        XCTAssertTrue(url.contains("travelmode=transit"), "移動手段が引き継がれていない: \(url)")
    }

    // MARK: - E2E 7: 経路 0 件でも画面は壊れない

    func testShowsMessageWhenNoRoutes() {
        launch(scenario: "noRoutes")
        startRouteToTokyoStation()

        XCTAssertTrue(app.descendants(matching: .any)[A11y.routeError].firstMatch.waitForExistence(timeout: timeout()),
                      "経路なしの案内が出ない")
        // 条件の編集は続けられる。
        XCTAssertTrue(app.buttons[A11y.node(0)].exists, "ノードの編集ができない")
        XCTAssertTrue(app.buttons[A11y.swapButtonInline].exists, "入れ替えボタンが消えている")
    }

    // MARK: - E2E 8: 保存とラベル、履歴からの復元

    func testSavingPlaceWithLabelAndHistory() {
        launch()
        startRouteToTokyoStation()
        XCTAssertTrue(app.descendants(matching: .any)[A11y.planTotal].firstMatch.waitForExistence(timeout: timeout()),
                      "経路が組み上がらない（履歴が記録されない）")

        // 経路を閉じると、いま検索した地点が「最近の検索」に残っている。
        app.buttons[A11y.closeRouteButton].tap()
        let recent = app.buttons[A11y.recentSearch(0)]
        XCTAssertTrue(recent.waitForExistence(timeout: timeout()), "最近の検索が記録されていない")
        recent.tap()

        XCTAssertTrue(app.staticTexts[A11y.placeTitle].waitForExistence(timeout: timeout()),
                      "履歴から場所詳細を開けない")
        let saveButton = app.buttons[A11y.saveButton]
        XCTAssertTrue(saveButton.waitForExistence(timeout: timeout()))
        saveButton.tap()
        // confirmationDialog のボタンは階層上に二重に現れるため firstMatch で解決する。
        app.buttons[A11y.saveLabelOption("home")].firstMatch.tap()
        XCTAssertTrue(app.buttons["自宅"].firstMatch.waitForExistence(timeout: timeout()), "ラベルが反映されない")

        tab("bookmark").tap()
        XCTAssertTrue(app.buttons[A11y.savedPlace(0)].firstMatch.waitForExistence(timeout: timeout()),
                      "保存地点が一覧に出ない")
        XCTAssertTrue(app.staticTexts["自宅"].firstMatch.exists, "保存一覧にラベルが出ない")
        XCTAssertTrue(app.buttons[A11y.recentRoute(0)].exists, "最近の経路が記録されていない")

        // 履歴から経路を開くと地図タブへ戻る。
        app.buttons[A11y.recentRoute(0)].tap()
        XCTAssertTrue(app.buttons[A11y.node(0)].waitForExistence(timeout: timeout()),
                      "履歴から経路を復元できない")
    }
}

extension UsefulMapUITests {
    // MARK: - E2E 9: 経路を閉じて最初の地図に戻れる

    func testClosingRouteReturnsToMap() {
        launch()
        startRouteToTokyoStation()
        XCTAssertTrue(app.buttons[A11y.node(0)].waitForExistence(timeout: timeout()))

        app.buttons[A11y.closeRouteButton].tap()

        // 最初の検索欄に戻る。
        XCTAssertTrue(app.buttons[A11y.searchField].waitForExistence(timeout: timeout()),
                      "最初の画面に戻れない")
        XCTAssertFalse(app.buttons[A11y.node(0)].exists, "経路が残っている")
    }

    // MARK: - E2E 10: 経由地は押した区間に入り、他のノードは消えない

    func testAddingWaypointKeepsOtherNodes() {
        launch()
        startRouteToTokyoStation()

        XCTAssertTrue(app.buttons[A11y.node(0)].waitForExistence(timeout: timeout()))
        let nodeCountBefore = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                                               "route.node.")).count

        // 先頭の区間に経由地を足す。
        app.buttons[A11y.addWaypoint(0)].tap()

        // 入力欄が出ても、既存のノードは消えない。
        XCTAssertTrue(app.textFields[A11y.nodeField(0)].waitForExistence(timeout: timeout()),
                      "経由地の入力欄が出ない")
        let nodeCountDuring = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@",
                                                               "route.node.")).count
        XCTAssertEqual(nodeCountDuring, nodeCountBefore, "既存のノードが消えている")
    }

    // MARK: - E2E 11: 検索前に出発地と時刻条件を決められる

    func testDraftConditionsAreAvailableBeforeSearching() {
        launch()

        // 目的地を入れる前から、出発地と時刻条件が置いてある。
        XCTAssertTrue(app.buttons[A11y.draftOrigin].waitForExistence(timeout: timeout()),
                      "検索前に出発地を指定できない")
        XCTAssertTrue(app.buttons[A11y.timeCondition].exists, "検索前に時刻条件を指定できない")
        XCTAssertTrue(app.buttons[A11y.searchField].exists, "目的地の欄が無い")

        // 出発地を押すとその場で入力欄になる（別画面へ飛ばない）。
        app.buttons[A11y.draftOrigin].tap()
        XCTAssertTrue(app.textFields[A11y.nodeField(0)].waitForExistence(timeout: timeout()),
                      "出発地がその場で編集できない")
        XCTAssertTrue(app.buttons[A11y.timeCondition].exists, "編集で画面が置き換わっている")
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
    static let lastOpenedURL = "debug.lastOpenedURL"
    static let routeError = "routeCompare.error"
    static let planTotal = "route.total"
    static func detailButton(_ index: Int) -> String { "routeCompare.detail.\(index)" }
    static let walkingPaceButton = "route.walkingPace"
    static let swapButtonInline = "route.swap"
    static let closeRouteButton = "route.close"

    static func addWaypoint(_ index: Int) -> String { "route.addWaypoint.\(index)" }

    static func node(_ index: Int) -> String { "route.node.\(index)" }
    static func nodeField(_ index: Int) -> String { "route.node.field.\(index)" }
    static func segmentMode(_ index: Int) -> String { "route.segment.mode.\(index)" }
    static func saveLabelOption(_ label: String) -> String { "placeDetail.saveLabel.\(label)" }
    static func searchResult(_ index: Int) -> String { "search.result.\(index)" }
    static func savedPlace(_ index: Int) -> String { "saved.place.\(index)" }
    static func recentRoute(_ index: Int) -> String { "saved.route.\(index)" }
    static func recentSearch(_ index: Int) -> String { "map.recentSearch.\(index)" }

    static let draftOrigin = "draft.origin"
    static let timeCondition = "time.condition"
}
