# Useful Map

MapKit で移動手段ごとの所要時間を比較し、公共交通の詳細だけ Google Maps へ渡す iOS アプリ。

- **Useful Map** = 「どの移動手段で行くか」を比較して決める場所
- **Google Maps** = 選んだ公共交通経路の運賃・乗換・駅構内などの詳細を見る場所

企画書 `Useful_Map_企画書_改訂版.docx` / 仕様書 `Useful_Map_仕様書_改訂版.docx` に基づく実装です。

## 構成

責務分離は SwiftPM のモジュール境界で**コンパイル時に**保証しています。許可されていない依存は
そもそもビルドが通りません。

```
App/                                composition root（実装の組み立てはここだけ）
Packages/UsefulMapKit/
  Sources/Domain/                   モデル・ポリシー・ポート（Foundation のみ）
  Sources/Data/            → Domain 永続化 / Google Maps URL 契約
  Sources/Infrastructure/  → Domain, Data   MapKit・Core Location・UIApplication 境界
  Sources/Presentation/    → Domain SwiftUI 画面と ViewModel
contract-watch/                     Playwright による外部 URL 仕様の契約監視
```

| 層 | 依存できる先 | 触ってよい SDK |
|---|---|---|
| Domain | （なし） | Foundation |
| Data | Domain | Foundation, Combine |
| Infrastructure | Domain, Data | MapKit, CoreLocation, UIKit |
| Presentation | Domain | SwiftUI, MapKit |

`ArchitectureTests` が import 文を静的に検査し、依存方向・SDK 範囲・Google 内部 URL 形式の
隔離（非機能要件 14）を継続的に監視します。

### 画面

| ID | 画面 | 実装 |
|---|---|---|
| S01 | 地図ホーム | `Presentation/Map/MapHomeView.swift` |
| S02 | 検索 | `Presentation/Search/SearchView.swift` |
| S03 | 場所詳細 | `Presentation/PlaceDetail/PlaceDetailView.swift` |
| S04 | 経路比較 | `Presentation/Route/RouteCompareView.swift` |
| S05 | 経路編集 | `Presentation/Route/RouteEditorView.swift` |
| S06 | 保存・履歴 | `Presentation/Saved/SavedView.swift` |

保存地点には `自宅 / 学校 / 保存だけする` のラベルを付けられます（S03 の「保存」でラベルを選択、
S06 の「・・・」メニューで付け替え・解除）。ラベル付きの地点は地図ホーム上部のチップに並びます。

## 対応言語

日本語・英語・簡体字中国語・韓国語・タイ語。端末の言語設定に従って自動的に切り替わります。

日本語しか用意しないと、日本国内を移動する訪日・在日の利用者のうち
「その言語しか読めない層」が使えないため、この 4 言語を追加しています。

| 対象 | 場所 |
|---|---|
| 画面の文言 | `Packages/UsefulMapKit/Sources/Presentation/Resources/*.lproj/Localizable.strings` |
| モデルの表示名・エラー文言 | `Packages/UsefulMapKit/Sources/Domain/Resources/*.lproj/Localizable.strings` |
| 位置情報の用途（権限ダイアログ） | `App/Resources/*.lproj/InfoPlist.strings` |

日付・時刻・数値・距離は Foundation のロケール対応フォーマッタに任せているため、
12 時間制と 24 時間制の違いなどは自動で吸収されます。
`LocalizationTests` が「未翻訳のキー」「空の翻訳」「書式指定子の数の不一致」
「日本語のまま残っている行」を検出します。

## アプリアイコン

`App/Assets.xcassets/AppIcon.appiconset/` に 1024×1024 の PNG を置くと反映されます。

| ファイル名 | 必須 | 用途 |
|---|---|---|
| `AppIcon-1024.png` | 必須 | 通常（ライト） |
| `AppIcon-1024-Dark.png` | 任意 | iOS 18 のダーク外観 |
| `AppIcon-1024-Tinted.png` | 任意 | iOS 18 の色合い調整外観（グレースケール） |

要件: 1024×1024、sRGB、**アルファチャンネルなし**、角丸は付けない（システムが丸めます）、
文字は入れない（小サイズで潰れます）。任意の 2 枚が無くてもビルドは通ります（警告のみ）。

## セットアップ

```bash
make setup      # xcodegen / swiftlint / periphery / playwright
make project    # UsefulMap.xcodeproj を生成
open UsefulMap.xcodeproj
```

## テスト

```bash
make unit          # Swift Testing 195 件（単体 + アーキテクチャ + ローカライズ）
make contract-unit # 契約監視の単体テスト 19 件（ネットワーク不要）
make e2e           # XCUITest 7 本（シミュレータ内で完結）
make all           # PR 前の一式（+ SwiftLint, jscpd）
```

### テストの構成

| 種別 | 場所 | 内容 |
|---|---|---|
| 単体（Swift Testing） | `Packages/UsefulMapKit/Tests/{Domain,Data,Infrastructure,Presentation}Tests` | モデル、URL 生成、時刻変換、保存、ViewModel の状態遷移・キャンセル・エラー |
| アーキテクチャ | `Tests/ArchitectureTests` | 依存方向、SDK 範囲、内部 URL 形式の隔離、ViewModel の MainActor |
| ローカライズ | `PresentationTests/LocalizationTests` | 5 言語の翻訳漏れ・書式指定子・ロケール解決 |
| 契約（Swift ↔ 監視） | `DataTests/URLFormatContractTests` | Swift の生成結果と `contract-watch/format.json` の一致 |
| E2E（XCUITest） | `Tests/UITests` | 検索→比較、モード切替、時刻付き遷移、fallback、0 件、保存・履歴、ラベル付け |
| 契約監視（Playwright） | `contract-watch/tests` | 実際に Google Maps を開いて条件が保たれるか |

E2E は起動引数 `-UITestMode` で MapKit / Core Location / 外部遷移をスタブへ差し替えるため、
ネットワークにも実機の位置情報にも依存せず決定的に動きます（`App/UITestConfiguration.swift`）。

## Google Maps への外部詳細遷移

公共交通の「詳細」を押すと、地点（名称・緯度経度）と選択した経路の時刻条件から
Google Maps の URL を機械生成します。Google の API へは一切通信しません。

- **Primary**: 時刻付きの内部 `data=` 形式（非公開仕様）。`!6e0` 出発指定 / `!6e1` 到着指定、`!8j` に時刻。
- **Fallback**: 公式 Maps URLs の Directions 形式。時刻条件は保証されませんが地点と移動手段は引き継ぎます。

内部形式の知識は Data 層の Google 系ファイルにのみ存在し、アプリ本体の経路取得はこれに依存しません。
形式が壊れても比較機能は動き続けます。

形式そのもの（トークンの並びと定数値）は `contract-watch/format.json` を単一の真実として
`GoogleMapsURLFormat+Generated.swift` へ生成します。`GoogleMapsURLBuilder` が持つのは
「地点の数だけブロックを並べ、ブロック長を数え、パスを組む」手続きだけです。

```bash
make generate-format   # format.json から Swift を再生成
make verify-format     # 生成物がずれていないか確認（CI でも実行）
```

### `!8j` の時刻値について

実測では `!8j` は「ローカル表示したい年月日時分を、そのまま UTC の壁時計として epoch 化した値」でした。
`Date.timeIntervalSince1970` をそのまま入れるとタイムゾーン分ずれます。この変換は
`GoogleTimestamp` にのみ隔離し、固定 fixture で回帰テストしています。

## 契約監視（GitHub Actions）

`.github/workflows/google-maps-url-watch.yml` が毎日 1 回 fixture を実際の Google Maps で開き、
地点・公共交通モード・出発/到着指定・日付時刻が維持されるかを確認します。

```
FAIL → 診断 Artifact（screenshot / trace / HTML report / 最終 URL）
     → Google Maps UI から正解 URL を取得
     → data= をトークン単位で構造 diff
     → delta debugging で最小変更集合へ縮小
     → format.json へ適用して全 fixture 再実行
     → 全件 PASS したときだけ修正 PR / それ以外は Issue のみ
```

「FAIL した」だけでは PR を作りません（仕様書 9）。
PR には `format.json` と生成された Swift の両方の差分が載るため、マージすればアプリ側も追随します。
形式が変わると `GoogleMapsURLBuilderTests` のスナップショットが意図的に落ちるので、
そこが「形式変更を人間が承認する場所」になります。

## 品質ハーネス

| ツール | 目的 | 実行 |
|---|---|---|
| Swift Testing | 振る舞いテスト | `make unit` |
| ArchitectureTests | 依存方向・責務分離 | `make unit` |
| SwiftLint | style / complexity / 禁止パターン | `make lint` |
| Periphery | 未使用コード検出 | `make dead-code` |
| jscpd | コード重複検出 | `make dup` |

SwiftLint にはカスタムルール `no_google_url_outside_builder`（内部 URL 形式の漏れ検出）を入れています。

## App Store 提出

`docs/app-store-submission.md` に、アプリ名の ASO 方針、5 言語の説明文・キーワード、
審査メモ、プライバシーポリシー、スクリーンショット要件、チェックリストをまとめてあります。

## MVP でやらないこと

独自の経路探索エンジン、Google API の利用、運賃・乗換回数・路線名の独自表示、
アカウント／クラウド同期／Backend、ターンバイターンナビゲーション。

## 実装上の注意

- `RouteOption` は仕様書の `mapRoute: MKRoute` の代わりに描画用の座標列 `geometry` を持ちます。
  Domain を MapKit から独立させるためで、変換は Infrastructure が行います。
- MapKit の公共交通は `MKDirections.calculate()` が経路を返さないため `calculateETA()` を使い、
  出発時刻・到着時刻・所要時間だけを取得します。運賃・乗換は取得も推定もしません。
- 経由地は MKDirections が直接対応しないため、区間ごとに計算して合算します。
- `data=` の構造は実測に基づく再現です。実機で Google Maps へ遷移して時刻条件が反映されることを
  確認してください（仕様書 16 の実装順序 7）。契約監視はその後の破壊的変更を検知するためのものです。
