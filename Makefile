SIMULATOR ?= platform=iOS Simulator,name=iPhone 17
PACKAGE := Packages/UsefulMapKit
BUNDLE_ID := com.usefulmap.UsefulMap

# 実機ビルド用。DEVICE_ID は `xcrun devicectl list devices` の Identifier。
DEVICE_ID ?= $(shell xcrun devicectl list devices 2>/dev/null | awk '$$4 == "available" {print $$3; exit}')
DEVELOPMENT_TEAM ?= X97ZJZ42VZ
DEVICE_BUILD_DIR := build/device
ARCHIVE_PATH := build/UsefulMap.xcarchive
EXPORT_DIR := build/export

# App Store 用スクリーンショットを撮る端末。Apple が必須としている 2 サイズ。
SCREENSHOT_IPHONE ?= platform=iOS Simulator,name=iPhone 17 Pro Max
SCREENSHOT_IPAD ?= platform=iOS Simulator,name=iPad Pro 13-inch (M5)
SCREENSHOT_DIR := artifacts/screenshots
# 署名は CI で無効化しているため、実機ビルドのときだけ上書きする。
SIGNING_OVERRIDES := CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
	CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM)

.PHONY: help setup project test unit e2e lint dead-code dup contract contract-unit urls generate-format verify-format devices check-device device-build device-install device-run sim-run screenshots archive export-ipa upload asc-venv asc-status asc-apps asc-check asc-push asc-screenshots asc-build asc-declare asc-availability asc-price asc-submit quality all clean

help: ## 使えるターゲット一覧
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

setup: ## 開発に必要なツールを入れる
	brew install xcodegen swiftlint peripheryapp/periphery/periphery
	cd contract-watch && npm install --no-package-lock && npx playwright install chromium

project: ## Xcode プロジェクトを生成する
	xcodegen generate

unit: ## 単体テスト + アーキテクチャテスト（Swift Testing）
	cd $(PACKAGE) && swift test --parallel

contract-unit: ## 契約監視の単体テスト（ネットワーク不要）
	cd contract-watch && node --test "tests/unit/*.test.mjs"

e2e: project ## E2E（XCUITest / シミュレータ）
	xcodebuild test -project UsefulMap.xcodeproj -scheme UsefulMap \
		-destination "$(SIMULATOR)" -only-testing:UsefulMapUITests \
		-skip-testing:UsefulMapUITests/ScreenshotTests

test: unit contract-unit e2e ## テスト一式

lint: ## SwiftLint
	swiftlint lint --strict

dead-code: project ## Periphery（未使用コード）
	periphery scan --config .periphery.yml

dup: ## コード重複チェック
	npx --yes jscpd@4 --config .jscpd.json

quality: lint dup dead-code ## 静的解析一式

generate-format: ## format.json から Swift の形式定義を再生成する
	cd contract-watch && node src/generate-swift.mjs

verify-format: ## 生成済み Swift が format.json と一致するか確認する
	cd contract-watch && node src/generate-swift.mjs --check

devices: ## 接続中の実機を一覧する
	xcrun devicectl list devices

check-device:
	@test -n "$(DEVICE_ID)" || (echo "実機が見つかりません。`make devices` で確認し、DEVICE_ID=... を指定してください" && exit 1)

device-build: project check-device ## 実機向けにビルドする（署名あり）
	xcodebuild build -project UsefulMap.xcodeproj -scheme UsefulMap \
		-destination 'platform=iOS,id=$(DEVICE_ID)' \
		-derivedDataPath $(DEVICE_BUILD_DIR) \
		-allowProvisioningUpdates -allowProvisioningDeviceRegistration $(SIGNING_OVERRIDES)

device-install: device-build ## 実機へインストールする
	xcrun devicectl device install app --device $(DEVICE_ID) \
		$(DEVICE_BUILD_DIR)/Build/Products/Debug-iphoneos/UsefulMap.app

device-run: device-install ## 実機へインストールして起動する
	xcrun devicectl device process launch --device $(DEVICE_ID) --terminate-existing $(BUNDLE_ID)

sim-run: project ## シミュレータへインストールして起動する
	xcodebuild build -project UsefulMap.xcodeproj -scheme UsefulMap \
		-destination '$(SIMULATOR)' -derivedDataPath build/sim -quiet
	xcrun simctl boot "iPhone 17" 2>/dev/null || true
	open -a Simulator
	xcrun simctl install booted build/sim/Build/Products/Debug-iphonesimulator/UsefulMap.app
	xcrun simctl launch booted $(BUNDLE_ID)

# 提出する言語。売り場ごとに、その言語の画面を出す。
SCREENSHOT_LANGS ?= ja en zh-Hans ko th

screenshots: project ## App Store 用スクリーンショットを 5 言語 x 2 サイズ撮る
	@rm -rf $(SCREENSHOT_DIR)
	@for lang in $(SCREENSHOT_LANGS); do \
		$(MAKE) capture-screenshots DEST="$(SCREENSHOT_IPHONE)" OUT=$$lang/iphone-6.9 LANG_ID=$$lang; \
		$(MAKE) capture-screenshots DEST="$(SCREENSHOT_IPAD)" OUT=$$lang/ipad-13 LANG_ID=$$lang; \
	done
	@echo "書き出し先: $(SCREENSHOT_DIR)/final/"

# 1 サイズぶんを撮って xcresult の添付から PNG を取り出す。
# 添付名（01-map-home など）がそのままファイル名になる。
capture-screenshots:
	@rm -rf $(SCREENSHOT_DIR)/$(OUT).xcresult
	@mkdir -p $(SCREENSHOT_DIR)/$(dir $(OUT))
	# TEST_RUNNER_ で始まる環境変数は、接頭辞を外してテストランナーへ渡る。
	# ビルド設定として書いても届かないので、環境変数として渡す。
	TEST_RUNNER_SCREENSHOT_LANG=$(LANG_ID) \
	xcodebuild test -project UsefulMap.xcodeproj -scheme UsefulMap \
		-destination "$(DEST)" \
		-only-testing:UsefulMapUITests/ScreenshotTests \
		-resultBundlePath $(SCREENSHOT_DIR)/$(OUT).xcresult
	@rm -rf $(SCREENSHOT_DIR)/raw/$(OUT)
	@mkdir -p $(SCREENSHOT_DIR)/raw/$(OUT) $(SCREENSHOT_DIR)/final/$(OUT)
	xcrun xcresulttool export attachments \
		--path $(SCREENSHOT_DIR)/$(OUT).xcresult \
		--output-path $(SCREENSHOT_DIR)/raw/$(OUT)
	@python3 scripts/collect-screenshots.py \
		$(SCREENSHOT_DIR)/raw/$(OUT) $(SCREENSHOT_DIR)/final/$(OUT)

archive: project ## App Store 提出用にアーカイブする（署名あり）
	xcodebuild archive -project UsefulMap.xcodeproj -scheme UsefulMap \
		-destination 'generic/platform=iOS' \
		-archivePath $(ARCHIVE_PATH) \
		-allowProvisioningUpdates $(SIGNING_OVERRIDES)

export-ipa: archive ## アーカイブから App Store 用の .ipa を書き出す
	@rm -rf $(EXPORT_DIR)
	xcodebuild -exportArchive -archivePath $(ARCHIVE_PATH) \
		-exportPath $(EXPORT_DIR) \
		-exportOptionsPlist ExportOptions.plist \
		-allowProvisioningUpdates
	@echo "書き出し先: $(EXPORT_DIR)"

# App Store Connect の API キーが要る。発行は「ユーザとアクセス > 統合」から。
#   export ASC_KEY_ID=... ASC_ISSUER_ID=...
#   キー本体は ~/.appstoreconnect/private_keys/AuthKey_$$ASC_KEY_ID.p8 に置く
# App Store Connect API を叩くための仮想環境。Git には入れない。
ASC_PY := scripts/.venv/bin/python

asc-venv: ## API クライアント用の Python 環境を用意する
	python3 -m venv scripts/.venv
	scripts/.venv/bin/pip install --quiet PyJWT cryptography requests

check-asc:
	@test -n "$(ASC_KEY_ID)" || (echo "ASC_KEY_ID が未設定です" && exit 1)
	@test -n "$(ASC_ISSUER_ID)" || (echo "ASC_ISSUER_ID が未設定です" && exit 1)
	@test -f "$(ASC_PY)" || (echo "先に make asc-venv を実行してください" && exit 1)

asc-apps: check-asc ## App Store Connect の登録アプリを一覧する
	$(ASC_PY) scripts/asc.py apps

asc-status: check-asc ## このアプリのレコード・バージョン・ビルドの状態を見る
	$(ASC_PY) scripts/asc.py status

asc-check: ## 投入する文言を、送らずに確認する
	$(ASC_PY) scripts/asc.py check

asc-push: check-asc ## 説明文・キーワード・審査メモを 5 言語ぶん反映する
	$(ASC_PY) scripts/asc.py push

asc-screenshots: check-asc ## スクリーンショットを差し替える
	$(ASC_PY) scripts/asc.py screenshots

asc-build: check-asc ## 処理の終わったビルドをバージョンへ紐付ける
	$(ASC_PY) scripts/asc.py build

asc-declare: check-asc ## 年齢制限と権利表明を回答する
	$(ASC_PY) scripts/asc.py declare

asc-availability: check-asc ## 配信地域を設定する
	$(ASC_PY) scripts/asc.py availability

asc-price: check-asc ## 無料配信の価格を設定する
	$(ASC_PY) scripts/asc.py price

asc-submit: check-asc ## 審査へ提出する
	$(ASC_PY) scripts/asc.py submit

upload: export-ipa ## .ipa を App Store Connect へ上げる
	@test -n "$(ASC_KEY_ID)" || (echo "ASC_KEY_ID が未設定です" && exit 1)
	@test -n "$(ASC_ISSUER_ID)" || (echo "ASC_ISSUER_ID が未設定です" && exit 1)
	xcrun altool --upload-app --type ios \
		--file $(EXPORT_DIR)/UsefulMap.ipa \
		--apiKey $(ASC_KEY_ID) --apiIssuer $(ASC_ISSUER_ID)

urls: ## 手動検証用に Primary / Official URL を出力する
	cd contract-watch && node src/print-urls.mjs $(WALLCLOCK)

contract: ## Google Maps URL の契約テスト（実際に Google を開く）
	cd contract-watch && npx playwright test

all: verify-format unit contract-unit lint dup e2e ## PR 前に回す一式

clean:
	rm -rf $(PACKAGE)/.build UsefulMap.xcodeproj artifacts contract-watch/artifacts build
