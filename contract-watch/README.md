# Contract Watch

Google Maps の非公開 `data=` URL 形式が変わったことを、ユーザーより先に検知するための仕組み
（仕様書 8-10）。

## なぜ必要か

時刻付きの遷移は Google の公開 Maps URLs API ではなく、Web UI が生成する内部形式を利用しています。
この形式は予告なく変わりえます。アプリは実行時に公式 URL へ fallback しますが、
「遷移先の UI で条件が解釈されたか」は iOS アプリ側から検知できません（仕様書 7.4）。
そのため CI で定期的に本物の Google Maps を開いて確認します。

## 構成

```
format.json              URL 構造の定義（Swift 実装と共有する真実）
fixtures/fixtures.json   固定 fixture（出発/到着、地域違い、駅以外、座標のみ）
src/dataParam.mjs        data= のトークン分解・整合性検証
src/urlBuilder.mjs       format.json から URL を生成（Swift と同じ結果になる）
src/verify.mjs           Google Maps の画面が条件を保っているかの判定
src/diff.mjs             構造 diff と delta debugging
src/repair.mjs           FAIL → 正解 URL 取得 → 最小差分探索 → 再検証
tests/contract.spec.mjs  Playwright の契約テスト
tests/unit/              ネットワーク不要の単体テスト
```

`format.json` と Swift 実装の一致は Swift 側の `DataTests/URLFormatContractTests` が検証します。
片方だけ直しても CI が落ちるので、乖離したまま進むことはありません。

## 実行

```bash
npm install --no-package-lock
npx playwright install chromium

node --test "tests/unit/*.test.mjs"   # 単体（ネットワーク不要）
npx playwright test                    # 契約テスト（実際に Google を開く）
npx playwright test --grep '\[構造\]'  # 生成側の自己検査だけ
node src/repair.mjs                    # 差分解析・修復の試行（--write で format.json を更新）
```

## PASS 条件（仕様書 8.4）

1. 経路画面が表示される
2. 出発地・目的地が fixture と一致する
3. 公共交通モードになっている
4. arriveBy / departAt が意図どおり
5. 指定した日付・時刻が UI に反映される

## FAIL 時（仕様書 8.5 / 9）

`artifacts/` に screenshot / trace / HTML report / 最終 URL / 期待値と実測値を残したうえで、

1. Google Maps UI を操作して同条件の正解 URL を生成する
2. 現行 URL と正解 URL を **トークン単位** で diff する（文字列 diff ではない）
3. delta debugging で「これだけ当てれば直る」最小変更集合へ縮小する
4. `format.json` へ適用して全 fixture を再実行する
5. **全件 PASS したときだけ** 修正 PR を作る。修復不能なら Issue のみ

## 注意

`src/verify.mjs` と `src/repair.mjs` の DOM 操作は Google の UI に依存するため、
UI 変更で壊れることがあります。壊れた場合は「正解 URL を取得できない」と判定し、
自動修復せず Issue を作る側に倒れます（誤った自動修正を PR にしないため）。
