SIMULATOR ?= platform=iOS Simulator,name=iPhone 17
PACKAGE := Packages/UsefulMapKit
BUNDLE_ID := com.usefulmap.UsefulMap

# 実機ビルド用。DEVICE_ID は `xcrun devicectl list devices` の Identifier。
DEVICE_ID ?= $(shell xcrun devicectl list devices 2>/dev/null | awk '$$4 == "available" {print $$3; exit}')
DEVELOPMENT_TEAM ?= X97ZJZ42VZ
DEVICE_BUILD_DIR := build/device
# 署名は CI で無効化しているため、実機ビルドのときだけ上書きする。
SIGNING_OVERRIDES := CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
	CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM)

.PHONY: help setup project test unit e2e lint dead-code dup contract contract-unit urls generate-format verify-format devices check-device device-build device-install device-run sim-run quality all clean

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
		-destination "$(SIMULATOR)" -only-testing:UsefulMapUITests

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

urls: ## 手動検証用に Primary / Official URL を出力する
	cd contract-watch && node src/print-urls.mjs $(WALLCLOCK)

contract: ## Google Maps URL の契約テスト（実際に Google を開く）
	cd contract-watch && npx playwright test

all: verify-format unit contract-unit lint dup e2e ## PR 前に回す一式

clean:
	rm -rf $(PACKAGE)/.build UsefulMap.xcodeproj artifacts contract-watch/artifacts build
