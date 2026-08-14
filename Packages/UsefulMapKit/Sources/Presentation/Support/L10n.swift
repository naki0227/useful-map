import Foundation
import SwiftUI

/// Presentation の表示文言。
/// モジュール同梱の Localizable.strings を引くため、必ず `.module` を指定する
/// （既定の `Bundle.main` はアプリ本体を見るため翻訳が当たらない）。
enum L10n {
    static func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .module)
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }

    /// ロケールを明示して解決する（テストと、表示ロケールを固定したい箇所で使う）。
    static func string(_ key: String, locale: Locale) -> String {
        Bundle.localizedBundle(for: locale)
            .localizedString(forKey: key, value: nil, table: nil)
    }

    static func string(_ key: String, locale: Locale, _ arguments: CVarArg...) -> String {
        String(format: string(key, locale: locale), locale: locale, arguments: arguments)
    }
}

extension Bundle {
    /// 指定ロケールの .lproj を持つバンドル。無ければモジュール本体を返す。
    ///
    /// SwiftPM は .lproj 名を小文字化して同梱する（`zh-Hans` → `zh-hans`）ため、
    /// バンドルが持つ localization 一覧と大文字小文字を無視して突き合わせる。
    static func localizedBundle(for locale: Locale) -> Bundle {
        let available = Bundle.module.localizations
        for candidate in localizationCandidates(for: locale) {
            guard let matched = available.first(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }),
                  let path = Bundle.module.path(forResource: matched, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { continue }
            return bundle
        }
        return .module
    }

    /// 「言語-地域」→「言語-文字体系」→「言語」の順に絞り込む。
    /// 例: zh_Hans_CN → ["zh-Hans-CN", "zh-Hans", "zh"]
    private static func localizationCandidates(for locale: Locale) -> [String] {
        var candidates = [locale.identifier.replacingOccurrences(of: "_", with: "-")]
        let language = locale.language.languageCode?.identifier
        if let language, let script = locale.language.script?.identifier {
            candidates.append("\(language)-\(script)")
        }
        if let language {
            // 中国語は地域指定だけで来ることがあるので、既定を簡体字にする。
            if language == "zh", !candidates.contains(where: { $0.contains("Hant") }) {
                candidates.append("zh-Hans")
            }
            candidates.append(language)
        }
        return candidates
    }
}

extension Text {
    /// モジュールの翻訳を引く Text。
    init(l10n key: String) {
        self.init(LocalizedStringKey(key), bundle: .module)
    }
}
