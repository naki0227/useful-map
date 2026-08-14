SIMULATOR ?= platform=iOS Simulator,name=iPhone 17
PACKAGE := Packages/UsefulMapKit

.PHONY: help setup project test unit e2e lint dead-code dup contract contract-unit quality all clean

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

contract: ## Google Maps URL の契約テスト（実際に Google を開く）
	cd contract-watch && npx playwright test

all: unit contract-unit lint dup e2e ## PR 前に回す一式

clean:
	rm -rf $(PACKAGE)/.build UsefulMap.xcodeproj artifacts contract-watch/artifacts
