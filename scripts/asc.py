"""App Store Connect API の薄いクライアント。

説明文・キーワード・スクリーンショットを Web の画面で 5 言語ぶん手入力するのは
現実的でないので、API から流し込む。アプリレコードの作成だけは API に
エンドポイントが無いため、そこは Web で作ってもらう前提。

    ASC_KEY_ID=... ASC_ISSUER_ID=... python scripts/asc.py <サブコマンド>
"""
import base64
import hashlib
import os
import re
import sys
import time
from pathlib import Path

import jwt
import requests

BASE = "https://api.appstoreconnect.apple.com"
PRIVACY_POLICY_URL = "https://naki0227.github.io/useful-map/"
COPYRIGHT = "2026 Ibuki Nagase"
SUPPORT_URL = "https://github.com/naki0227/useful-map"
KEY_DIR = Path.home() / ".appstoreconnect" / "private_keys"


def token() -> str:
    key_id = os.environ["ASC_KEY_ID"]
    issuer = os.environ["ASC_ISSUER_ID"]
    private_key = (KEY_DIR / f"AuthKey_{key_id}.p8").read_text()
    now = int(time.time())
    return jwt.encode(
        # 20 分が上限。余裕を持って 15 分にする。
        {"iss": issuer, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        private_key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


class Duplicate(Exception):
    """すでに同じロケールがある。作成ではなく更新へ回す合図。"""


class Client:
    def __init__(self) -> None:
        self.session = requests.Session()
        self.session.headers["Authorization"] = f"Bearer {token()}"

    def request(self, method: str, path: str, **kwargs):
        url = path if path.startswith("http") else f"{BASE}{path}"
        response = self.session.request(method, url, **kwargs)
        if not response.ok:
            if response.status_code == 409 and "INVALID.DUPLICATE" in response.text:
                raise Duplicate(response.text)
            raise SystemExit(f"{method} {url} → {response.status_code}\n{response.text}")
        return response.json() if response.content else {}

    def get(self, path, **kwargs):
        return self.request("GET", path, **kwargs)

    def post(self, path, payload):
        return self.request("POST", path, json=payload)

    def patch(self, path, payload):
        return self.request("PATCH", path, json=payload)


def find_app(client: Client, bundle_id: str) -> dict | None:
    apps = client.get("/v1/apps", params={"filter[bundleId]": bundle_id})["data"]
    return apps[0] if apps else None


# MARK: - 提出ドキュメントの読み取り
#
# 文言の出典は docs/app-store-submission.md ひとつだけにする。
# 別ファイルへ書き写すと必ず片方だけ直されてずれるため、ここで直接読む。

DOC = Path(__file__).resolve().parent.parent / "docs" / "app-store-submission.md"

# 見出しの言語名 → App Store Connect のロケール
LOCALES = {
    "日本語": "ja",
    "English": "en-US",
    "简体中文": "zh-Hans",
    "한국어": "ko",
    "ไทย": "th",
}


def _sections(text: str, level: int) -> dict[str, str]:
    """`### 見出し` で本文を切り分ける。"""
    marker = "#" * level
    pattern = re.compile(rf"^{marker} (.+)$", re.MULTILINE)
    matches = list(pattern.finditer(text))
    result = {}
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        result[match.group(1).strip()] = text[match.end():end]
    return result


def _code_blocks(text: str) -> list[str]:
    return [block.strip() for block in re.findall(r"```\n(.*?)```", text, re.DOTALL)]


def load_metadata() -> dict[str, dict[str, str]]:
    text = DOC.read_text()
    top = _sections(text, 2)

    metadata: dict[str, dict[str, str]] = {name: {} for name in LOCALES.values()}

    # 1. 名前とサブタイトルは表から、キーワードはコードブロックから読む。
    naming = top["1. アプリ名（ASO 方針）"]
    for row in re.findall(r"^\| (.+?) \| `(.+?)` \| `(.+?)` \|$", naming, re.MULTILINE):
        language, name, subtitle = row
        locale = LOCALES.get(language.strip())
        if locale:
            metadata[locale]["name"] = name
            metadata[locale]["subtitle"] = subtitle

    keyword_block = _code_blocks(naming)[0]
    for chunk in re.split(r"\n\s*\n", keyword_block):
        lines = [line for line in chunk.strip().split("\n") if line.strip()]
        if len(lines) < 2:
            continue
        locale = LOCALES.get(lines[0].rstrip(":").strip())
        if locale:
            metadata[locale]["keywords"] = lines[1].strip()

    # 2. 説明文は言語ごとの見出しの下に、
    #    プロモーション → 説明 → What's New の順でコードブロックが並ぶ。
    for language, body in _sections(top["3. 各ロケールの説明文"], 3).items():
        locale = LOCALES.get(language.strip())
        if locale is None:
            continue
        blocks = _code_blocks(body)
        if len(blocks) < 3:
            raise SystemExit(f"{language} の説明文が 3 ブロック揃っていません")
        metadata[locale]["promotionalText"] = blocks[0]
        metadata[locale]["description"] = blocks[1]
        metadata[locale]["whatsNew"] = blocks[2]

    for locale, values in metadata.items():
        missing = {"name", "subtitle", "keywords", "description"} - values.keys()
        if missing:
            raise SystemExit(f"{locale} に {sorted(missing)} がありません")
    return metadata


def review_notes() -> str:
    top = _sections(DOC.read_text(), 2)
    return _code_blocks(top["4. App Review Information（審査メモ）"])[0]


# MARK: - サブコマンド

def cmd_apps(client: Client) -> None:
    for app in client.get("/v1/apps", params={"limit": 200})["data"]:
        attributes = app["attributes"]
        print(f"{app['id']:12} {attributes['bundleId']:35} {attributes['name']}")


def cmd_status(client: Client) -> None:
    bundle_id = os.environ.get("BUNDLE_ID", "com.usefulmap.UsefulMap")
    app = find_app(client, bundle_id)
    if app is None:
        raise SystemExit(
            f"{bundle_id} のアプリレコードがありません。\n"
            "API ではアプリを作れないため、App Store Connect の「マイApp → ＋」で作成してください。"
        )
    print(f"アプリ  : {app['attributes']['name']} (id={app['id']})")

    versions = client.get(f"/v1/apps/{app['id']}/appStoreVersions", params={"limit": 5})["data"]
    for version in versions:
        attributes = version["attributes"]
        print(f"バージョン: {attributes['versionString']} / {attributes['appStoreState']}")

    builds = client.get("/v1/builds", params={"filter[app]": app["id"], "limit": 5})["data"]
    for build in builds:
        attributes = build["attributes"]
        print(f"ビルド  : {attributes['version']} / {attributes.get('processingState')}")
    if not builds:
        print("ビルド  : まだ届いていません")


def editable_version(client: Client, app_id: str) -> dict:
    """まだ編集できるバージョン（審査提出前）を取る。"""
    versions = client.get(
        f"/v1/apps/{app_id}/appStoreVersions",
        params={"filter[appStoreState]": "PREPARE_FOR_SUBMISSION", "limit": 1},
    )["data"]
    if not versions:
        raise SystemExit("編集できるバージョンがありません（審査中か、公開済みです）")
    return versions[0]


def upsert(client: Client, path: str, list_path: str, locale: str,
           attributes: dict, relationship: dict) -> None:
    """同じロケールがあれば更新、無ければ作る。

    ロケールを 1 つ足すと Apple 側が関連する項目を自動で作ることがあるため、
    一覧は毎回取り直す。それでも競合したら、作成済みとみなして更新へ回す。
    """
    def current() -> dict | None:
        items = client.get(list_path, params={"limit": 50})["data"]
        return next((item for item in items
                     if item["attributes"]["locale"] == locale), None)

    def patch(item: dict) -> None:
        client.patch(f"{path}/{item['id']}",
                     {"data": {"type": item["type"], "id": item["id"],
                               "attributes": attributes}})

    existing = current()
    if existing is not None:
        patch(existing)
        return
    try:
        client.post(path, {"data": {"type": relationship["type"],
                                    "attributes": {**attributes, "locale": locale},
                                    "relationships": relationship["relationships"]}})
    except Duplicate:
        created = current()
        if created is None:
            raise
        patch(created)


def cmd_push(client: Client) -> None:
    """説明文・キーワード・審査メモを投入する。"""
    metadata = load_metadata()
    bundle_id = os.environ.get("BUNDLE_ID", "com.usefulmap.UsefulMap")
    app = find_app(client, bundle_id)
    if app is None:
        raise SystemExit(f"{bundle_id} のアプリレコードがありません")
    app_id = app["id"]
    version = editable_version(client, app_id)
    version_id = version["id"]
    print(f"対象: {app['attributes']['name']} / {version['attributes']['versionString']}")

    # 初回リリースには「このバージョンの新機能」が無く、送ると 409 になる。
    all_versions = client.get(f"/v1/apps/{app_id}/appStoreVersions",
                              params={"limit": 50})["data"]
    is_first_release = all(
        item["attributes"]["appStoreState"] == "PREPARE_FOR_SUBMISSION"
        for item in all_versions
    )
    if is_first_release:
        print("  初回リリースのため What's New は送りません")

    # 名前・サブタイトルは「App 情報」側（バージョンをまたいで共通）。
    app_info = client.get(f"/v1/apps/{app_id}/appInfos")["data"][0]

    info_list = f"/v1/appInfos/{app_info['id']}/appInfoLocalizations"
    version_list = f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations"

    for locale, values in metadata.items():
        upsert(client, "/v1/appInfoLocalizations", info_list, locale,
               {"name": values["name"], "subtitle": values["subtitle"],
                "privacyPolicyUrl": PRIVACY_POLICY_URL},
               {"type": "appInfoLocalizations",
                "relationships": {"appInfo": {"data": {"type": "appInfos",
                                                       "id": app_info["id"]}}}})
        version_attributes = {"description": values["description"],
                              "keywords": values["keywords"],
                              "promotionalText": values["promotionalText"],
                              "supportUrl": SUPPORT_URL,
                              "marketingUrl": SUPPORT_URL}
        if not is_first_release:
            version_attributes["whatsNew"] = values["whatsNew"]
        upsert(client, "/v1/appStoreVersionLocalizations", version_list, locale,
               version_attributes,
               {"type": "appStoreVersionLocalizations",
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions",
                                                               "id": version_id}}}})
        print(f"  {locale} を投入")

    # 審査メモ。サインイン不要なので、そこも明示しておく。
    detail = client.get(f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail")["data"]
    attributes = {"notes": review_notes(), "demoAccountRequired": False}
    if detail:
        client.patch(f"/v1/appStoreReviewDetails/{detail['id']}",
                     {"data": {"type": "appStoreReviewDetails", "id": detail["id"],
                               "attributes": attributes}})
    else:
        client.post("/v1/appStoreReviewDetails",
                    {"data": {"type": "appStoreReviewDetails", "attributes": attributes,
                              "relationships": {"appStoreVersion": {
                                  "data": {"type": "appStoreVersions", "id": version_id}}}}})
    print("  審査メモを投入")


# 撮影したサイズ → App Store Connect の表示タイプ
SCREENSHOT_SETS = {
    "iphone-6.9": "APP_IPHONE_67",
    "ipad-13": "APP_IPAD_PRO_3GEN_129",
}
SCREENSHOT_DIR = Path(__file__).resolve().parent.parent / "artifacts" / "screenshots" / "final"


def upload_screenshot(client: Client, set_id: str, path: Path, order: int) -> None:
    """予約 → 実体を PUT → チェックサムを添えて確定、の 3 段で送る。"""
    data = path.read_bytes()
    reservation = client.post("/v1/appScreenshots", {
        "data": {
            "type": "appScreenshots",
            "attributes": {"fileName": path.name, "fileSize": len(data)},
            "relationships": {"appScreenshotSet": {
                "data": {"type": "appScreenshotSets", "id": set_id}}},
        }
    })["data"]

    for operation in reservation["attributes"]["uploadOperations"]:
        headers = {header["name"]: header["value"] for header in operation["requestHeaders"]}
        chunk = data[operation["offset"]:operation["offset"] + operation["length"]]
        response = requests.request(operation["method"], operation["url"],
                                    headers=headers, data=chunk)
        if not response.ok:
            raise SystemExit(f"アップロード失敗 {path.name}: {response.status_code}")

    client.patch(f"/v1/appScreenshots/{reservation['id']}", {
        "data": {"type": "appScreenshots", "id": reservation["id"],
                 "attributes": {"uploaded": True,
                                "sourceFileChecksum": hashlib.md5(data).hexdigest()}}
    })


# 撮影に使った言語 → App Store Connect のロケール
SCREENSHOT_LANGS = {"ja": "ja", "en": "en-US", "zh-Hans": "zh-Hans", "ko": "ko", "th": "th"}


def cmd_screenshots(client: Client) -> None:
    """スクリーンショットを 5 言語ぶん差し替える。

    売り場ごとにその言語の画面を出す。日本語の画面だけを全世界へ出すと、
    その言語しか読めない人には何のアプリか分からない。
    """
    for language, locale in SCREENSHOT_LANGS.items():
        print(f"--- {locale}")
        push_screenshots(client, language, locale)


def push_screenshots(client: Client, language: str, locale: str) -> None:
    bundle_id = os.environ.get("BUNDLE_ID", "com.usefulmap.UsefulMap")
    app = find_app(client, bundle_id)
    if app is None:
        raise SystemExit(f"{bundle_id} のアプリレコードがありません")
    version_id = editable_version(client, app["id"])["id"]

    localizations = client.get(
        f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations",
        params={"limit": 50})["data"]
    target = next((item for item in localizations
                   if item["attributes"]["locale"] == locale), None)
    if target is None:
        raise SystemExit(f"{locale} のバージョン情報がありません。先に push を実行してください")

    sets = client.get(f"/v1/appStoreVersionLocalizations/{target['id']}/appScreenshotSets",
                      params={"limit": 50})["data"]

    for directory, display_type in SCREENSHOT_SETS.items():
        images = sorted((SCREENSHOT_DIR / language / directory).glob("*.png"))
        if not images:
            raise SystemExit(
                f"{language}/{directory} に画像がありません。make screenshots を実行してください")

        existing = next((item for item in sets
                         if item["attributes"]["screenshotDisplayType"] == display_type), None)
        if existing is None:
            existing = client.post("/v1/appScreenshotSets", {
                "data": {"type": "appScreenshotSets",
                         "attributes": {"screenshotDisplayType": display_type},
                         "relationships": {"appStoreVersionLocalization": {
                             "data": {"type": "appStoreVersionLocalizations",
                                      "id": target["id"]}}}}
            })["data"]
        else:
            # 並び順と枚数を確実に合わせるため、入れ直す前に消す。
            for old in client.get(f"/v1/appScreenshotSets/{existing['id']}/appScreenshots",
                                  params={"limit": 50})["data"]:
                client.request("DELETE", f"/v1/appScreenshots/{old['id']}")

        for order, image in enumerate(images):
            upload_screenshot(client, existing["id"], image, order)
        print(f"  {display_type}: {len(images)} 枚")


# 年齢制限の回答。すべて該当なしで 4+ になる。
#
# このアプリは地図と所要時間しか出さない。利用者どうしのやり取りも、
# 投稿の共有も、広告も、アプリ内購入も無い。表示する文章はすべて自前の
# ローカライズ文字列で、外部から取り込んだ本文を載せる箇所が無い。
AGE_RATING = {
    # 表現の強さを聞く設問。NONE / INFREQUENT_OR_MILD / FREQUENT_OR_INTENSE
    "violenceCartoonOrFantasy": "NONE",
    "violenceRealistic": "NONE",
    "violenceRealisticProlongedGraphicOrSadistic": "NONE",
    "profanityOrCrudeHumor": "NONE",
    "matureOrSuggestiveThemes": "NONE",
    "horrorOrFearThemes": "NONE",
    "medicalOrTreatmentInformation": "NONE",
    "alcoholTobaccoOrDrugUseOrReferences": "NONE",
    "sexualContentOrNudity": "NONE",
    "sexualContentGraphicAndNudity": "NONE",
    "gamblingSimulated": "NONE",
    "contests": "NONE",
    "gunsOrOtherWeapons": "NONE",

    # 機能の有無を聞く設問。
    "gambling": False,
    "lootBox": False,
    "advertising": False,
    "messagingAndChat": False,
    "socialMedia": False,
    # 検索欄に文字を打つが、それが誰かに見えることはない。
    "userGeneratedContent": False,
    # 「詳細」は Google マップを開いて離れるだけで、アプリ内に
    # 任意のサイトを開けるブラウザは持たない。
    "unrestrictedWebAccess": False,
    "parentalControls": False,
    # 健康・ウェルネスの話題は扱わない。
    "healthOrWellnessTopics": False,

    # 年齢確認の仕組みは持たない（誰でもそのまま使える）。
    "ageAssurance": False,

    # 子ども向けカテゴリには出さない。
    "kidsAgeBand": None,
}


def cmd_declare(client: Client) -> None:
    """カテゴリ・著作権表示・年齢制限・権利表明を答える。"""
    bundle_id = os.environ.get("BUNDLE_ID", "com.usefulmap.UsefulMap")
    app = find_app(client, bundle_id)
    if app is None:
        raise SystemExit(f"{bundle_id} のアプリレコードがありません")

    # 第三者のコンテンツを含まない。地図データは Apple、遷移先は Google の公開 URL。
    client.patch(f"/v1/apps/{app['id']}", {
        "data": {"type": "apps", "id": app["id"],
                 "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}
    })
    print("権利表明: 第三者コンテンツを含まない")

    info = client.get(f"/v1/apps/{app['id']}/appInfos")["data"][0]

    # カテゴリ。経路を出すアプリなので Navigation、旅行でも使うので Travel を副に。
    client.patch(f"/v1/appInfos/{info['id']}", {
        "data": {"type": "appInfos", "id": info["id"], "relationships": {
            "primaryCategory": {"data": {"type": "appCategories", "id": "NAVIGATION"}},
            "secondaryCategory": {"data": {"type": "appCategories", "id": "TRAVEL"}},
        }}
    })
    print("カテゴリ: Navigation / Travel")

    # 著作権表示。年と権利者名だけでよい。
    version = editable_version(client, app["id"])
    client.patch(f"/v1/appStoreVersions/{version['id']}", {
        "data": {"type": "appStoreVersions", "id": version["id"],
                 "attributes": {"copyright": COPYRIGHT}}
    })
    print(f"著作権表示: {COPYRIGHT}")

    declaration = client.get(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    client.patch(f"/v1/ageRatingDeclarations/{declaration['id']}", {
        "data": {"type": "ageRatingDeclarations", "id": declaration["id"],
                 "attributes": AGE_RATING}
    })
    refreshed = client.get(f"/v1/appInfos/{info['id']}")["data"]
    print(f"年齢制限: {refreshed['attributes']['appStoreAgeRating']}")


def cmd_availability(client: Client) -> None:
    """配信地域を設定する。既定は全地域。

    日本向けの機能が中心だが、Apple の公共交通データがある地域なら同じように動くし、
    徒歩と車はどこでも動く。地域を絞る理由が無いので全地域に出す。
    """
    bundle_id = os.environ.get("BUNDLE_ID", "com.usefulmap.UsefulMap")
    app = find_app(client, bundle_id)
    if app is None:
        raise SystemExit(f"{bundle_id} のアプリレコードがありません")

    territories = []
    url = "/v1/territories?limit=200"
    while url:
        page = client.get(url)
        territories += [item["id"] for item in page["data"]]
        url = page.get("links", {}).get("next")

    # 同じリクエストの中で作る要素は、実 ID ではなく `${local-id}` で参照する。
    def local(code: str) -> str:
        return "${" + code + "}"

    client.post("/v2/appAvailabilities", {
        "data": {
            "type": "appAvailabilities",
            "attributes": {"availableInNewTerritories": True},
            "relationships": {
                "app": {"data": {"type": "apps", "id": app["id"]}},
                "territoryAvailabilities": {
                    "data": [{"type": "territoryAvailabilities", "id": local(code)}
                             for code in territories]
                },
            },
        },
        "included": [
            {"type": "territoryAvailabilities", "id": local(code),
             "attributes": {"available": True},
             "relationships": {"territory": {"data": {"type": "territories", "id": code}}}}
            for code in territories
        ],
    })
    print(f"配信地域: {len(territories)} 地域を有効にしました")


PROFILE_NAME = "Useful Map App Store"
PROFILE_DIR = Path.home() / "Library" / "MobileDevice" / "Provisioning Profiles"


def cmd_profile(client: Client) -> None:
    """App Store 配布用のプロビジョニングプロファイルを用意して手元へ置く。

    xcodebuild の自動署名は、配布用プロファイルが無いとクラウド署名へ倒れ、
    CI では権限エラーで止まる。作ってから手動署名で書き出すほうが確実で、
    手元と CI で同じ結果になる。
    """
    bundle_id = os.environ.get("BUNDLE_ID", "com.usefulmap.UsefulMap")
    identifiers = client.get("/v1/bundleIds",
                             params={"filter[identifier]": bundle_id, "limit": 1})["data"]
    if not identifiers:
        raise SystemExit(f"{bundle_id} が Identifiers に登録されていません")

    profiles = client.get("/v1/profiles", params={
        "filter[name]": PROFILE_NAME, "filter[profileState]": "ACTIVE", "limit": 1})["data"]
    if profiles:
        profile = client.get(f"/v1/profiles/{profiles[0]['id']}")["data"]
    else:
        certificates = [c for c in client.get("/v1/certificates", params={"limit": 50})["data"]
                        if c["attributes"]["certificateType"] == "DISTRIBUTION"]
        if not certificates:
            raise SystemExit("配布用証明書がありません。"
                             "scripts/make-distribution-cert.sh を実行してください")
        profile = client.post("/v1/profiles", {
            "data": {"type": "profiles",
                     "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_STORE"},
                     "relationships": {
                         "bundleId": {"data": {"type": "bundleIds",
                                               "id": identifiers[0]["id"]}},
                         "certificates": {"data": [{"type": "certificates", "id": c["id"]}
                                                   for c in certificates]}}}
        })["data"]

    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    content = base64.b64decode(profile["attributes"]["profileContent"])
    destination = PROFILE_DIR / f"{profile['attributes']['uuid']}.mobileprovision"
    destination.write_bytes(content)
    print(f"プロファイル: {profile['attributes']['name']} "
          f"({profile['attributes']['uuid']}) → {destination}")


def cmd_price(client: Client) -> None:
    """無料で配信する設定を入れる。"""
    bundle_id = os.environ.get("BUNDLE_ID", "com.usefulmap.UsefulMap")
    app = find_app(client, bundle_id)
    if app is None:
        raise SystemExit(f"{bundle_id} のアプリレコードがありません")

    # 価格は「どこか 1 つの国の価格」を基準に決め、他国は Apple が換算する。
    # 無料なので、基準国の 0 円にあたる価格ポイントを探す。
    points = client.get(f"/v1/apps/{app['id']}/appPricePoints",
                        params={"filter[territory]": "JPN", "limit": 200})["data"]
    free = next((p for p in points if p["attributes"]["customerPrice"] in ("0", "0.00")), None)
    if free is None:
        raise SystemExit("無料の価格ポイントが見つかりません")

    client.post("/v1/appPriceSchedules", {
        "data": {
            "type": "appPriceSchedules",
            "relationships": {
                "app": {"data": {"type": "apps", "id": app["id"]}},
                "baseTerritory": {"data": {"type": "territories", "id": "JPN"}},
                "manualPrices": {"data": [{"type": "appPrices", "id": "${price}"}]},
            },
        },
        "included": [{
            "type": "appPrices", "id": "${price}",
            "relationships": {"appPricePoint": {
                "data": {"type": "appPricePoints", "id": free["id"]}}},
        }],
    })
    print("価格: 無料（基準は日本）")


def cmd_build(client: Client) -> None:
    """処理の終わった最新ビルドを、編集中のバージョンへ紐付ける。

    アップロードしただけではバージョンに付かない。Web で選ぶのと同じ操作を API でやる。
    """
    bundle_id = os.environ.get("BUNDLE_ID", "com.usefulmap.UsefulMap")
    app = find_app(client, bundle_id)
    if app is None:
        raise SystemExit(f"{bundle_id} のアプリレコードがありません")
    version = editable_version(client, app["id"])
    version_id = version["id"]

    # 処理中のビルドは紐付けられないので、VALID になるまで待つ。
    deadline = time.time() + 20 * 60
    while True:
        builds = client.get("/v1/builds", params={
            "filter[app]": app["id"],
            "filter[preReleaseVersion.version]": version["attributes"]["versionString"],
            "sort": "-uploadedDate", "limit": 10,
        })["data"]
        ready = [b for b in builds if b["attributes"]["processingState"] == "VALID"]
        if ready:
            break
        pending = [b["attributes"]["processingState"] for b in builds]
        if time.time() > deadline:
            raise SystemExit(f"ビルドが VALID になりません: {pending or 'ビルドが見つかりません'}")
        print(f"  ビルドの処理待ち {pending or '(まだ届いていません)'}")
        time.sleep(30)

    build = ready[0]
    client.patch(f"/v1/appStoreVersions/{version_id}", {
        "data": {"type": "appStoreVersions", "id": version_id,
                 "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}
    })
    print(f"ビルド {build['attributes']['version']} を "
          f"{version['attributes']['versionString']} に紐付けました")


def cmd_submit(client: Client) -> None:
    """審査へ提出する。

    提出は 3 段階。まとめ（reviewSubmission）を作り、そこへ対象のバージョンを
    足して、最後に submitted へ切り替える。切り替えるまでは何も起きない。
    """
    bundle_id = os.environ.get("BUNDLE_ID", "com.usefulmap.UsefulMap")
    app = find_app(client, bundle_id)
    if app is None:
        raise SystemExit(f"{bundle_id} のアプリレコードがありません")
    version = editable_version(client, app["id"])

    build = client.get(f"/v1/appStoreVersions/{version['id']}/build")["data"]
    if not build:
        raise SystemExit("ビルドが紐付いていません。先に make asc-build を実行してください")

    # 途中まで作りかけの提出が残っていれば使い回す。
    existing = client.get("/v1/reviewSubmissions", params={
        "filter[app]": app["id"], "filter[state]": "READY_FOR_REVIEW", "limit": 1})["data"]
    submission = existing[0] if existing else client.post("/v1/reviewSubmissions", {
        "data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                 "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}}}
    })["data"]

    items = client.get(f"/v1/reviewSubmissions/{submission['id']}/items",
                       params={"limit": 10})["data"]
    if not items:
        client.post("/v1/reviewSubmissionItems", {
            "data": {"type": "reviewSubmissionItems",
                     "relationships": {
                         "reviewSubmission": {"data": {"type": "reviewSubmissions",
                                                       "id": submission["id"]}},
                         "appStoreVersion": {"data": {"type": "appStoreVersions",
                                                      "id": version["id"]}}}}
        })

    result = client.patch(f"/v1/reviewSubmissions/{submission['id']}", {
        "data": {"type": "reviewSubmissions", "id": submission["id"],
                 "attributes": {"submitted": True}}
    })
    state = result["data"]["attributes"]["state"]
    print(f"提出しました: {app['attributes']['name']} "
          f"{version['attributes']['versionString']} (build {build['attributes']['version']})")
    print(f"状態: {state}")


def cmd_check(client: Client) -> None:
    """投入する内容を、送らずに確認する。"""
    metadata = load_metadata()
    for locale, values in metadata.items():
        print(f"--- {locale}")
        print(f"  名前         : {values['name']} ({len(values['name'])} 字)")
        print(f"  サブタイトル : {values['subtitle']} ({len(values['subtitle'])} 字)")
        print(f"  キーワード   : {len(values['keywords'])} 字")
        print(f"  説明文       : {len(values['description'])} 字")
        print(f"  What's New   : {len(values['whatsNew'])} 字")
    print(f"--- 審査メモ: {len(review_notes())} 字")


COMMANDS = {"apps": cmd_apps, "status": cmd_status, "check": cmd_check,
            "push": cmd_push, "screenshots": cmd_screenshots, "build": cmd_build,
            "declare": cmd_declare, "availability": cmd_availability,
            "submit": cmd_submit, "price": cmd_price, "profile": cmd_profile}

if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "status"
    if name not in COMMANDS:
        raise SystemExit(f"使えるサブコマンド: {', '.join(COMMANDS)}")
    COMMANDS[name](Client())
