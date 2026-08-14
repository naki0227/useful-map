import Foundation
import Testing

@testable import Presentation

/// 翻訳の欠落・書式指定子のずれを検知する。
///
/// 対象言語は「その言語しか読めない利用者が一定数いる」ことを前提に選んでいるため、
/// 未翻訳のキーが 1 つでも残ると実害が出る。日本語を基準に全言語を突き合わせる。
@Suite("ローカライズ")
struct LocalizationTests {
    static let languages = ["ja", "en", "zh-Hans", "ko", "th"]
    static let modules = ["Presentation", "Domain"]

    /// `Sources/<module>/Resources/<lang>.lproj/Localizable.strings` を読む。
    static func entries(module: String, language: String) throws -> [String: String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // PresentationTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // UsefulMapKit
            .appendingPathComponent("Sources/\(module)/Resources/\(language).lproj/Localizable.strings")
        let contents = try String(contentsOf: url, encoding: .utf8)

        var result: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""), trimmed.hasSuffix(";") else { continue }
            let parts = trimmed.components(separatedBy: "\" = \"")
            guard parts.count == 2 else { continue }
            let key = String(parts[0].dropFirst())
            let value = String(parts[1].dropLast(2))
            result[key] = value
        }
        return result
    }

    /// "%@" や "%1$@" のような書式指定子を数える。
    static func placeholders(in value: String) -> Int {
        var count = 0
        var index = value.startIndex
        while let range = value.range(of: "%", range: index..<value.endIndex) {
            let rest = value[range.upperBound...]
            if rest.hasPrefix("%") {
                index = value.index(range.upperBound, offsetBy: 1)
                continue
            }
            count += 1
            index = range.upperBound
        }
        return count
    }

    @Test("すべての言語に、日本語と同じキーが揃っている",
          arguments: LocalizationTests.modules)
    func noMissingKeys(module: String) throws {
        let base = try Self.entries(module: module, language: "ja")
        #expect(!base.isEmpty, "\(module) の ja が空")

        for language in Self.languages where language != "ja" {
            let translated = try Self.entries(module: module, language: language)
            let missing = Set(base.keys).subtracting(translated.keys).sorted()
            let extra = Set(translated.keys).subtracting(base.keys).sorted()
            #expect(missing.isEmpty, "\(module)/\(language) に未翻訳のキー: \(missing)")
            #expect(extra.isEmpty, "\(module)/\(language) に余分なキー: \(extra)")
        }
    }

    @Test("翻訳が空文字になっていない", arguments: LocalizationTests.modules)
    func noEmptyValues(module: String) throws {
        for language in Self.languages {
            for (key, value) in try Self.entries(module: module, language: language) {
                #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty,
                        "\(module)/\(language) の \(key) が空")
            }
        }
    }

    @Test("書式指定子の数が言語間で一致する（実行時クラッシュを防ぐ）",
          arguments: LocalizationTests.modules)
    func placeholderCountsMatch(module: String) throws {
        let base = try Self.entries(module: module, language: "ja")
        for language in Self.languages where language != "ja" {
            let translated = try Self.entries(module: module, language: language)
            for (key, japanese) in base {
                guard let value = translated[key] else { continue }
                let detail = "\(module)/\(language) の \(key) で書式指定子の数が違う: ja=\(japanese) / \(value)"
                #expect(Self.placeholders(in: japanese) == Self.placeholders(in: value), "\(detail)")
            }
        }
    }

    @Test("日本語以外の翻訳が日本語のまま残っていない")
    func translationsAreNotJapanese() throws {
        // 日本語の文言をそのままコピーしただけの行を検出する（記号だけの値は除く）。
        let base = try Self.entries(module: "Presentation", language: "ja")
        for language in ["en", "ko", "th"] {
            let translated = try Self.entries(module: "Presentation", language: language)
            for (key, value) in translated {
                guard let japanese = base[key], japanese.count > 3 else { continue }
                #expect(value != japanese, "\(language) の \(key) が日本語のまま: \(value)")
            }
        }
    }

    @Test("表示ロケールを切り替えると文言も切り替わる")
    func lookupSwitchesWithLocale() {
        let expectations = [
            ("ja", "詳細"),
            ("en", "Details"),
            ("zh-Hans", "详情"),
            ("ko", "상세"),
            ("th", "รายละเอียด")
        ]
        for (language, expected) in expectations {
            #expect(L10n.string("route.detail", locale: Locale(identifier: language)) == expected,
                    "\(language) の route.detail が一致しない")
        }
    }

    @Test("地域付きロケールでも正しい .lproj へ解決する")
    func resolvesRegionalLocales() {
        #expect(L10n.string("route.detail", locale: Locale(identifier: "zh_Hans_CN")) == "详情")
        #expect(L10n.string("route.detail", locale: Locale(identifier: "ko_KR")) == "상세")
        #expect(L10n.string("route.detail", locale: Locale(identifier: "th_TH")) == "รายละเอียด")
        #expect(L10n.string("route.detail", locale: Locale(identifier: "en_US")) == "Details")
    }

    @Test("未知のロケールでも空文字にはならない")
    func unknownLocaleFallsBack() {
        let value = L10n.string("route.detail", locale: Locale(identifier: "fr_FR"))
        #expect(!value.isEmpty)
        #expect(value != "route.detail")
    }
}
