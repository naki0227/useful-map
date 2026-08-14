import Foundation

/// data= の構造定義を「データ」として扱うための型。
///
/// トークンを Swift のコードにベタ書きすると、CI の自動修復が機械的に差分を当てられない。
/// 定数とプレースホルダを区別した記述にしておくことで、
/// `contract-watch/format.json` からの生成と、値だけの安全な差し替えが成立する。
enum FormatPlaceholder: String {
    case longitude
    case latitude
    case timeMode
    case timestamp
    case modeCode
    case innerCount
    case outerCount
}

struct FormatToken {
    enum Value {
        /// 形式が変わらない限り固定の値（例: `!7e2` の "2"）。
        case constant(String)
        /// 実行時に埋める値（座標・時刻・モードなど）。
        case placeholder(FormatPlaceholder)
    }

    let group: Int
    let kind: Character
    let value: Value

    /// プレースホルダを実際の値へ置き換えてトークンにする。
    func resolved(with substitutions: [FormatPlaceholder: String]) -> DataToken? {
        switch value {
        case let .constant(constant):
            return DataToken(group: group, kind: kind, value: constant)
        case let .placeholder(placeholder):
            guard let substitution = substitutions[placeholder] else { return nil }
            return DataToken(group: group, kind: kind, value: substitution)
        }
    }
}
