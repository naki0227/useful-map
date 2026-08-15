# App Store 審査提出用ドキュメント

App Store Connect に入力する文言・設定を全部まとめたもの。
コピペしてそのまま使える形にしてある。

- **アプリ名（確定）**: `Useful Map 経路比較`
- **プライバシーポリシー URL**: https://naki0227.github.io/useful-map/
- **Bundle ID**: `com.usefulmap.UsefulMap`
- **主要市場**: 日本（MapKit の公共交通が使える地域）
- **想定利用者**: 日本国内を移動する人。特に**日本語を読めない訪日・在日の利用者**を
  中国語・韓国語・タイ語・英語で支える

---

## 1. アプリ名（ASO 方針）

### 考え方

App Store の検索インデックスは **アプリ名 + サブタイトル + キーワード** から作られる。
名前は「ブランド + 最重要キーワード 1 つ」に絞り、残りはサブタイトルとキーワード欄へ回す。
名前にキーワードを詰め込むと 4.3（スパム）や 2.3.7（不適切なメタデータ）で差し戻される。

このアプリの検索需要は「**経路**」「**乗換**」「**所要時間**」「**比較**」に集中する。
`Useful Map` だけでは "map" の巨大な競合に埋もれるため、名前に「経路比較」を入れる。

### 決定

**`Useful Map 経路比較`** を採用する。

理由:

- `Useful Map` だけでは "map" の巨大な競合に埋もれ、指名検索でしか当たらない
- 日本語圏の検索需要は「経路」「乗換」「所要時間」「比較」に集中する。
  このうち名前に入れるのは 1 語だけにして、残りはサブタイトルとキーワードへ回す
  （名前に詰め込むとガイドライン 4.3 / 2.3.7 で差し戻される）
- 「経路比較」はこのアプリの独自性そのもの。Google マップや Yahoo!乗換案内が
  「1 つの最適解を出す」のに対し、こちらは「並べて比べて決める」ことが売りなので、
  名前が機能をそのまま説明している
- 全ロケールで `Useful Map` を先頭に固定し、ブランドの一貫性を保つ

### 各言語の名前・サブタイトル

| 言語 | アプリ名（30 字以内） | サブタイトル（30 字以内） |
|---|---|---|
| 日本語 | `Useful Map 経路比較` | `電車・徒歩・車の所要時間を比較` |
| English | `Useful Map: Route Compare` | `Transit, walk & drive times` |
| 简体中文 | `Useful Map 路线比较` | `一屏比较电车、步行与驾车时间` |
| 한국어 | `Useful Map 경로 비교` | `전철·도보·자동차 소요시간 비교` |
| ไทย | `Useful Map เทียบเส้นทาง` | `เทียบเวลารถไฟ เดิน และขับรถ` |

> アプリ名は全ロケールで `Useful Map` を先頭に固定する。ブランドの一貫性が保て、
> 「Useful Map」での指名検索も拾える。

### キーワード欄（100 字以内・カンマ区切り・スペース無し）

**名前とサブタイトルに入れた語は繰り返さない**（重複しても順位は上がらない）。

```
日本語:
経路検索,乗換案内,ルート,時刻表,地図,ナビ,移動手段,バス,地下鉄,通勤,通学,旅行,観光,運賃

English:
route,transit,commute,japan,train,subway,bus,navigation,directions,map,travel,tourist,timetable

简体中文:
路线,换乘,通勤,日本,地铁,公交,导航,地图,旅行,观光,时刻表,出行,交通

한국어:
경로,환승,통근,일본,지하철,버스,내비게이션,지도,여행,관광,시간표,교통

ไทย:
เส้นทาง,รถไฟ,รถไฟใต้ดิน,รถเมล์,ญี่ปุ่น,แผนที่,นำทาง,เดินทาง,ท่องเที่ยว,ตารางเวลา
```

---

## 2. App Information（全ロケール共通）

| 項目 | 値 |
|---|---|
| Primary Category | Navigation |
| Secondary Category | Travel |
| Content Rights | 第三者コンテンツを含まない |
| Age Rating | **4+**（すべての項目を「なし」で回答） |
| Price | Free |
| In-App Purchase | なし |
| Sign-In Required | **不要** |

---

## 3. 各ロケールの説明文

### 日本語

**プロモーションテキスト（170 字以内）**
```
目的地までの移動手段を、同じ画面で並べて比較。電車・徒歩・車の所要時間が一目で分かります。運賃や乗換の詳細はGoogleマップで確認できます。
```

**説明文**
```
Useful Map は「今、どの移動手段で行くか」を決めるための地図アプリです。

目的地を検索すると、電車・徒歩・車の所要時間が同じ画面に並びます。モードを切り替えて何度も調べ直す必要はありません。

■ 判断に必要な情報だけ
表示するのは所要時間が中心です。公共交通では出発時刻と到着時刻も確認できます。情報量を絞ることで、「あと何分かかるのか」「何時に着くのか」がすぐ分かります。

■ 詳細はGoogleマップへ
運賃・乗換駅・路線・ホームなどの詳しい情報は、このアプリでは扱いません。公共交通の候補で「詳細」を押すと、同じ地点と時刻の条件を引き継いだままGoogleマップが開きます。比較はUseful Mapで、詳細はGoogleマップで。役割を分けています。

■ 条件を変えてすぐ再比較
出発地を現在地から任意の場所へ変更したり、経由地を追加したり、出発時刻・到着時刻を指定したりできます。

■ 端末の中で完結
保存した場所と最近の検索・経路は端末内にのみ保存されます。アカウント登録は不要です。位置情報が独自のサーバーへ送信されることはありません。

■ 対応言語
日本語・英語・簡体字中国語・韓国語・タイ語

地図・検索・経路の取得にはAppleのMapKitを使用しています。公共交通の情報が取得できる範囲はAppleの提供状況に依存します。
```

**What's New（初回リリース）**
```
Useful Map の最初のバージョンです。
・電車・徒歩・車の所要時間をまとめて比較
・公共交通は出発時刻と到着時刻を表示
・「詳細」からGoogleマップへ時刻条件を引き継いで移動
・場所の保存と履歴（自宅・学校のラベル付け）
・日本語・英語・中国語・韓国語・タイ語に対応
```

### English

**Promotional Text**
```
Compare how long it takes by train, on foot, or by car — all on one screen. Open Google Maps for fares and transfer details when you need them.
```

**Description**
```
Useful Map helps you decide how to get there right now.

Search for a destination and see travel times for transit, walking, and driving side by side. No more switching modes and checking one at a time.

■ Only what you need to decide
The focus is travel time. For public transit, departure and arrival times are shown as well. Less clutter means you know "how much longer" and "what time I arrive" at a glance.

■ Details in Google Maps
Fares, transfer stations, lines, and platforms are not reproduced here. Tap "Details" on a transit option and Google Maps opens with the same places and time conditions carried over. Compare in Useful Map, dig into details in Google Maps.

■ Change conditions, compare again
Set the origin to your current location or any searched place, add stops along the way, and specify a departure or arrival time.

■ Everything stays on your device
Saved places and recent searches are stored only on your device. No account is required. Your location is never sent to our servers.

■ Languages
Japanese, English, Simplified Chinese, Korean, Thai

Maps, search, and routing use Apple MapKit. Public transit coverage depends on what Apple provides in your area.
```

**What's New**
```
The first version of Useful Map.
- Compare travel times for transit, walking, and driving
- Departure and arrival times for public transit
- Hand off to Google Maps with your time conditions intact
- Save places and revisit recent routes (Home / School labels)
- Available in Japanese, English, Chinese, Korean, and Thai
```

### 简体中文

**推广文本**
```
在同一屏幕上比较电车、步行、驾车所需的时间。需要票价和换乘详情时，一键跳转谷歌地图。
```

**说明**
```
Useful Map 帮你决定"现在该用哪种方式出行"。

搜索目的地后，电车、步行、驾车的所需时间会并排显示，不必逐个切换查看。

■ 只显示做决定需要的信息
以所需时间为主。公共交通还会显示出发时刻和到达时刻。信息精简，让你立刻知道"还要多久""几点能到"。

■ 详情交给谷歌地图
本应用不提供票价、换乘车站、线路、站台等详细信息。在公共交通选项中点击"详情"，谷歌地图会带着相同的地点和时间条件打开。比较用 Useful Map，详情看谷歌地图。

■ 改变条件，立即重新比较
可以把出发地设为当前位置或任意搜索到的地点，添加途经点，并指定出发或到达时刻。

■ 全部在设备内完成
收藏的地点和最近的搜索、路线仅保存在本机。无需注册账号。位置信息不会被发送到我们的服务器。

■ 支持语言
日语、英语、简体中文、韩语、泰语

地图、搜索和路线使用 Apple MapKit。公共交通信息的覆盖范围取决于 Apple 在当地的提供情况。
```

**新功能**
```
Useful Map 的首个版本。
・比较电车、步行、驾车的所需时间
・公共交通显示出发与到达时刻
・从"详情"跳转谷歌地图，保留时间条件
・收藏地点与历史记录（可标记住家、学校）
・支持日语、英语、中文、韩语、泰语
```

### 한국어

**프로모션 텍스트**
```
전철·도보·자동차의 소요시간을 한 화면에서 비교하세요. 요금과 환승 정보가 필요할 때는 구글 지도로 바로 이동합니다.
```

**설명**
```
Useful Map은 "지금 어떤 방법으로 갈지"를 정하기 위한 지도 앱입니다.

목적지를 검색하면 전철·도보·자동차의 소요시간이 같은 화면에 나란히 표시됩니다. 이동수단을 하나씩 바꿔가며 확인할 필요가 없습니다.

■ 판단에 필요한 정보만
소요시간이 중심입니다. 대중교통은 출발 시각과 도착 시각도 함께 표시됩니다. 정보를 줄여서 "얼마나 더 걸리는지" "몇 시에 도착하는지"를 바로 알 수 있습니다.

■ 자세한 정보는 구글 지도에서
요금·환승역·노선·승강장 같은 상세 정보는 이 앱에서 다루지 않습니다. 대중교통 후보에서 "상세"를 누르면 같은 지점과 시각 조건을 그대로 넘긴 채 구글 지도가 열립니다. 비교는 Useful Map에서, 상세는 구글 지도에서.

■ 조건을 바꿔 다시 비교
출발지를 현재 위치나 검색한 장소로 바꾸고, 경유지를 추가하고, 출발 시각·도착 시각을 지정할 수 있습니다.

■ 기기 안에서 완결
저장한 장소와 최근 검색·경로는 기기 안에만 저장됩니다. 계정 등록이 필요 없습니다. 위치 정보가 자체 서버로 전송되지 않습니다.

■ 지원 언어
일본어·영어·중국어 간체·한국어·태국어

지도, 검색, 경로에는 Apple MapKit을 사용합니다. 대중교통 정보의 제공 범위는 Apple의 제공 상황에 따릅니다.
```

**새로운 기능**
```
Useful Map의 첫 번째 버전입니다.
・전철·도보·자동차의 소요시간을 한 번에 비교
・대중교통은 출발 시각과 도착 시각을 표시
・"상세"에서 시각 조건을 유지한 채 구글 지도로 이동
・장소 저장과 기록 (집·학교 라벨)
・일본어·영어·중국어·한국어·태국어 지원
```

### ไทย

**ข้อความโปรโมท**
```
เทียบเวลาเดินทางด้วยรถไฟ เดิน และขับรถ ในหน้าจอเดียว เมื่อต้องการดูค่าโดยสารและการเปลี่ยนสาย เปิด Google Maps ได้ทันที
```

**คำอธิบาย**
```
Useful Map ช่วยให้คุณตัดสินใจว่า "ตอนนี้ควรไปด้วยวิธีไหน"

ค้นหาปลายทาง แล้วเวลาที่ใช้เดินทางด้วยรถไฟ การเดิน และการขับรถ จะแสดงเรียงกันในหน้าจอเดียว ไม่ต้องสลับดูทีละแบบ

■ แสดงเฉพาะข้อมูลที่ใช้ตัดสินใจ
เน้นที่เวลาที่ใช้เดินทาง สำหรับขนส่งสาธารณะจะแสดงเวลาออกเดินทางและเวลาถึงด้วย ข้อมูลที่กระชับทำให้รู้ทันทีว่า "อีกนานแค่ไหน" และ "ถึงกี่โมง"

■ รายละเอียดดูใน Google Maps
ค่าโดยสาร สถานีเปลี่ยนสาย เส้นทาง และชานชาลา ไม่ได้แสดงในแอปนี้ แตะ "รายละเอียด" ที่ตัวเลือกขนส่งสาธารณะ แล้ว Google Maps จะเปิดขึ้นโดยคงสถานที่และเงื่อนไขเวลาเดิมไว้

■ เปลี่ยนเงื่อนไขแล้วเทียบใหม่ได้ทันที
ตั้งจุดออกเดินทางเป็นตำแหน่งปัจจุบันหรือสถานที่ที่ค้นหา เพิ่มจุดแวะ และระบุเวลาออกเดินทางหรือเวลาถึงได้

■ ทุกอย่างอยู่ในเครื่องของคุณ
สถานที่ที่บันทึกและประวัติการค้นหาถูกเก็บไว้ในเครื่องเท่านั้น ไม่ต้องสมัครบัญชี ตำแหน่งของคุณไม่ถูกส่งไปยังเซิร์ฟเวอร์ของเรา

■ ภาษาที่รองรับ
ญี่ปุ่น อังกฤษ จีนตัวย่อ เกาหลี ไทย

แผนที่ การค้นหา และเส้นทางใช้ Apple MapKit ความครอบคลุมของข้อมูลขนส่งสาธารณะขึ้นอยู่กับบริการที่ Apple ให้ในพื้นที่นั้น
```

**มีอะไรใหม่**
```
เวอร์ชันแรกของ Useful Map
・เทียบเวลาเดินทางด้วยรถไฟ เดิน และขับรถ
・ขนส่งสาธารณะแสดงเวลาออกเดินทางและเวลาถึง
・เปิด Google Maps จาก "รายละเอียด" โดยคงเงื่อนไขเวลาไว้
・บันทึกสถานที่และดูประวัติ (ป้ายบ้าน / โรงเรียน)
・รองรับภาษาญี่ปุ่น อังกฤษ จีน เกาหลี และไทย
```

---

## 4. App Review Information（審査メモ）

サインインは不要。以下をそのまま Notes 欄へ貼る。

```
【アプリの目的】
目的地までの移動手段（公共交通・徒歩・車）の所要時間を同じ画面で比較し、
利用者がどの手段で行くかを素早く判断するためのアプリです。

【テスト手順】
1. 位置情報の許可ダイアログで「App の使用中は許可」を選択します。
   （許可しない場合も、出発地を検索して手動指定すれば全機能を利用できます）
2. 地図の上部に、出発地・目的地・時刻条件の 3 行が並んでいます。
   出発地は既定で現在地です。押すとその場で検索欄に変わり、任意の地点に変更できます。
3. 目的地の欄を押して、日本国内の地点を検索してください。例:「東京駅」「新宿御苑」
4. 検索結果を選ぶと、その場で経路が区間に分かれて表示されます。
   例:「現在地 →徒歩→ ○○駅 →公共交通→ 東京駅」
5. 区間と区間のあいだにある矢印のアイコンを押すと、その区間だけ移動手段を
   切り替えられます（公共交通 / 徒歩 / 車）。下部の「公共交通・徒歩・車」を押すと
   全区間をまとめて切り替えます。所要時間は下部に合計で表示されます。
6. 区間の右端にある矢印ボタンを押すと、その区間の地点と時刻条件を引き継いだまま
   Google マップ（アプリまたは Safari）が開きます。
   区間ごとに開くのは、Google マップが公共交通と経由地の組み合わせを扱えないためです。
7. 矢印の横の「＋」を押すと、その区間の途中に経由地を追加できます。

【重要な補足】
・公共交通の経路取得には Apple の MapKit を使用しています。MapKit の公共交通データは
  提供地域が限られるため、日本国内（東京・大阪など）でのテストを推奨します。
  対応外の地域では「この地域では公共交通の経路を取得できません」と表示され、
  徒歩・車の比較は引き続き動作します。これは想定どおりの挙動です。

・Google の API・SDK は一切使用していません。「詳細」は Google マップの URL を開くだけの
  外部リンクであり、Google との提携や提供元であることを示す表現もしていません。
  URL が開けなかった場合は Google 公式の Maps URLs 形式へ自動的に切り替えます。

・運賃、乗換回数、路線名、ホーム番号などをこのアプリ自身が推定・表示することはありません。

・アカウント登録、ログイン、課金はありません。
・保存した場所と履歴は端末内（UserDefaults）にのみ保存され、外部へ送信しません。
・独自のサーバー（Backend）を持たないため、位置情報がネットワークへ送信されることはありません。

【対応言語】
日本語、英語、簡体字中国語、韓国語、タイ語。
端末の言語設定に従って自動的に切り替わります。
```

**Contact Information**: 氏名・電話番号・メールアドレスを入力する。
  Apple ID のものを使う（リポジトリが公開なので、ここには書かない）。

---

## 5. App Privacy（プライバシー質問への回答）

App Store Connect の「App Privacy」では **「Data Not Collected」** を選択できる。

| 質問 | 回答 |
|---|---|
| このアプリはデータを収集しますか？ | **いいえ** |

理由: Backend を持たず、位置情報・検索履歴・保存地点はすべて端末内に留まり、
開発者もサードパーティも取得しない。Google マップへの遷移は利用者自身の操作による
外部リンクであり、こちらからデータを送信するものではない。

> 注意: 将来 Analytics や Crash レポート SDK を入れた場合、この回答は変更が必要になる。

**プライバシーマニフェスト**は `App/PrivacyInfo.xcprivacy` に同梱済み。
`UserDefaults` の利用理由として `CA92.1`（同一アプリ内の情報アクセス）を宣言している。

---

## 6. プライバシーポリシー

App Store Connect には URL の入力が必須。GitHub Pages などで公開してから URL を登録する。

### 日本語

```
Useful Map プライバシーポリシー

最終更新日: 2026年8月15日

Useful Map（以下「本アプリ」）は、利用者のプライバシーを尊重します。
本アプリは、利用者に関するいかなる情報も収集・送信・保存しません。

1. 収集する情報
本アプリの開発者は、利用者の個人情報を一切収集しません。
本アプリは独自のサーバーを持たず、利用者の情報を外部へ送信することはありません。

2. 位置情報の利用
本アプリは、利用者が許可した場合に限り、端末の位置情報を利用します。
位置情報は「現在地を出発地とした経路の取得」および「地図上への現在地表示」にのみ使用され、
端末の外部へ送信・保存されることはありません。
位置情報の利用を許可しない場合でも、出発地を手動で検索して指定することで本アプリを利用できます。

3. 端末内に保存される情報
保存した場所、最近の検索、最近の経路は、利用者の端末内にのみ保存されます。
これらは開発者から参照できません。本アプリを削除すると、これらの情報も削除されます。

4. 外部サービスへの遷移
本アプリは、利用者が公共交通の「詳細」を操作したときに限り、Google マップを開きます。
このとき、選択した地点と時刻の条件が URL に含まれます。
遷移後の情報の取り扱いは Google のプライバシーポリシーに従います。
本アプリは Google の API を利用しておらず、Google へ利用者の情報を送信することもありません。

5. 地図データ
地図の表示、場所の検索、経路の取得には Apple の MapKit を使用しています。
これらの機能の利用時、Apple のプライバシーポリシーが適用されます。

6. 子どものプライバシー
本アプリは年齢を問わず利用できますが、いかなる利用者からも個人情報を収集しません。

7. 本ポリシーの変更
本ポリシーを変更する場合は、本ページの内容を更新します。

8. お問い合わせ
<Apple ID のメールアドレス>
```

### English

```
Useful Map Privacy Policy

Last updated: August 15, 2026

Useful Map ("the app") respects your privacy.
The app does not collect, transmit, or store any information about you.

1. Information We Collect
The developer collects no personal information.
The app has no server of its own and never transmits your information externally.

2. Use of Location
With your permission, the app uses your device's location solely to calculate routes
from your current location and to show your position on the map.
Location data never leaves your device.
If you decline location access, you can still use the app by searching for a starting point manually.

3. Information Stored on Your Device
Saved places, recent searches, and recent routes are stored only on your device.
The developer cannot access them. Deleting the app deletes this information.

4. Links to External Services
When you tap "Details" on a public transit option, the app opens Google Maps.
The selected places and time conditions are included in the URL.
Google's privacy policy applies once you leave the app.
The app does not use Google APIs and does not send your information to Google.

5. Map Data
Map display, place search, and routing use Apple MapKit.
Apple's privacy policy applies when these features are used.

6. Children's Privacy
The app is suitable for all ages and collects no personal information from any user.

7. Changes to This Policy
Any changes will be reflected on this page.

8. Contact
<Apple ID のメールアドレス>
```

> 中国語・韓国語・タイ語のポリシーは上記日本語版の忠実な翻訳を用意すれば足りる。
> Apple は 1 つの URL を要求するだけなので、日英併記のページでも受理される。

---

## 7. 輸出コンプライアンス

| 質問 | 回答 |
|---|---|
| 暗号化を使用していますか？ | HTTPS のみ（免除対象） |
| `ITSAppUsesNonExemptEncryption` | `false`（`App/Info.plist` に設定済み） |

このためアップロードのたびに質問される画面は出ない。

---

## 8. スクリーンショット

必須サイズ（2026 年時点）。**iPad を配信対象に含めているため iPad 用も必須**。

| デバイス | 解像度 | 枚数 |
|---|---|---|
| iPhone 6.9"（iPhone 17 Pro Max など） | 1320 × 2868 | 3〜10 |
| iPad 13"（iPad Pro 13") | 2064 × 2752 | 3〜10 |

推奨する 5 枚の構成（撮影する画面と訴求文）:

1. **経路比較（最適）** — 「電車・徒歩・車をまとめて比較」
2. **経路比較（公共交通）** — 「出発時刻と到着時刻がひと目で分かる」
3. **場所詳細** — 「検索して、経路へ。操作は最小限」
4. **経路編集** — 「出発地・経由地・時刻を変えてすぐ再検索」
5. **保存・履歴** — 「よく行く場所を自宅・学校として保存」

撮影は自動化してある。`-UITestMode` でデータを固定するため、何度撮っても同じ画面になる。

```bash
make screenshots     # 6.9" iPhone と 13" iPad の 2 サイズを撮る
# → artifacts/screenshots/final/{iphone-6.9,ipad-13}/*.png
```

撮れる 5 枚:

| ファイル | 画面 |
|---|---|
| `01-map-home.png` | 検索前に出発地と時刻条件を決められる地図ホーム |
| `02-search.png` | その場で出る検索候補 |
| `03-route-segments.png` | 区間に分かれた経路（徒歩 → 公共交通） |
| `04-route-edit.png` | 区間の途中に経由地を足すところ |
| `05-saved.png` | 保存地点と履歴 |

> **iPad 用を用意しない場合**は `project.yml` の `TARGETED_DEVICE_FAMILY` を `"1"` に変更して
> iPhone 専用として申請する。どちらかを必ず選ぶこと。

---

## 9. 審査で指摘されやすい点と対策

| ガイドライン | リスク | 対策 |
|---|---|---|
| 4.2 Minimum Functionality | 「地図を表示するだけ」と見なされる | 説明文と審査メモで「横断比較」という独自の価値を明示。実際に 3 モードの比較 UI がある |
| 4.1 Copycats | 既存地図アプリの模倣と見なされる | 独自の比較 UI であり、運賃・乗換などの再現はしていない旨を審査メモに記載済み |
| 5.2.5 第三者の権利 | Google との提携を装っていると見なされる | 名称・アイコン・説明文に Google のロゴやブランドを使わない。「Google マップで確認できます」という機能説明に留める |
| 2.1 App Completeness | 公共交通の経路が取得できずクラッシュ／空画面と見なされる | MapKit 非対応地域では専用のメッセージを表示し、徒歩・車の比較は継続する。審査メモに日本国内でのテストを明記 |
| 5.1.1 データ収集と保存 | 位置情報の用途が不明確 | 目的を限定した用途文言を全言語で用意（`App/Resources/*.lproj/InfoPlist.strings`） |
| 5.1.2 データの利用と共有 | プライバシー回答との不一致 | 「Data Not Collected」で回答。実際に Backend が存在しない |

---

## 10. 提出前チェックリスト

- [ ] `App/Assets.xcassets/AppIcon.appiconset/` に 1024×1024 のアイコンがある（配置済み）
- [ ] `App/PrivacyInfo.xcprivacy` が含まれている（配置済み）
- [ ] `ITSAppUsesNonExemptEncryption` が `false`（設定済み）
- [ ] 5 言語の `InfoPlist.strings` で位置情報の用途が翻訳されている（配置済み）
- [x] プライバシーポリシーを公開して URL を取得した（https://naki0227.github.io/useful-map/）
- [x] スクリーンショットを iPhone 6.9" と iPad 13" で撮影した（`make screenshots`）
- [ ] **実機で Google マップへの遷移を確認した**（時刻条件が反映されるか）
- [ ] `make all` が通る（単体 188 / 契約監視 19 / E2E 7）
- [ ] Apple Developer Program に登録済み（年 99 USD）
- [ ] Bundle ID `com.usefulmap.UsefulMap` を Certificates, Identifiers & Profiles で登録した
- [ ] Xcode の Signing で Team を設定した（現在は署名なしでビルドする設定）

---

## 11. 署名について

現在の `project.yml` は CI でビルドできるよう署名を無効にしている。

```yaml
CODE_SIGNING_REQUIRED: NO
CODE_SIGNING_ALLOWED: NO
```

App Store へ提出する際は、Xcode で対象ターゲットを開き
**Signing & Capabilities → Automatically manage signing** を有効にして Team を選ぶ
（または上記 2 行を削除して `DEVELOPMENT_TEAM` を設定する）。
