import Foundation

/// Domain が持つ表示文言の解決。
/// モジュール同梱の Localizable.strings を引くため、必ず `.module` を指定する
/// （既定の `Bundle.main` ではアプリ本体を見てしまい、翻訳が当たらない）。
enum L10n {
    static func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .module)
    }

    static func string(_ key: String, _ argument: String) -> String {
        String(format: string(key), argument)
    }
}
