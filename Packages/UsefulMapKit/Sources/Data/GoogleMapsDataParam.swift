import Foundation

/// Google Maps 非公開 `data=` パラメータのトークン表現。
///
/// `!4m18!4m17!1m5!1m1!1s0x0:0x0!2m2!1d139.7!2d35.6...` のような文字列を
/// 「!{group}{kind}{value}」の列として構造化して扱う。文字列 diff ではなく
/// このトークン単位で比較することで、契約監視側の差分解析（仕様書 9）と実装を揃える。
public struct DataToken: Hashable, Sendable, CustomStringConvertible {
    /// `!4m18` の 4。
    public let group: Int
    /// `!4m18` の m。
    public let kind: Character
    /// `!4m18` の 18。
    public let value: String

    public init(group: Int, kind: Character, value: String) {
        self.group = group
        self.kind = kind
        self.value = value
    }

    public var encoded: String { "!\(group)\(kind)\(value)" }
    public var description: String { encoded }

    /// `!4m18` のような「後続 n トークンを束ねる」ブロックヘッダか。
    public var isBlockHeader: Bool { kind == "m" }

    public var blockLength: Int? {
        isBlockHeader ? Int(value) : nil
    }
}

public enum GoogleMapsDataParam {
    /// data= 値をトークン列へ分解する。形式不正なら nil。
    public static func parse(_ raw: String) -> [DataToken]? {
        guard !raw.isEmpty, raw.hasPrefix("!") else { return nil }
        var tokens: [DataToken] = []
        // 先頭の "!" を落としてから "!" 区切りで分解する。
        for chunk in raw.dropFirst().components(separatedBy: "!") {
            guard !chunk.isEmpty else { return nil }
            let digits = chunk.prefix { $0.isNumber }
            guard !digits.isEmpty, let group = Int(digits) else { return nil }
            let rest = chunk.dropFirst(digits.count)
            guard let kind = rest.first, kind.isLetter else { return nil }
            tokens.append(DataToken(group: group, kind: kind, value: String(rest.dropFirst())))
        }
        return tokens
    }

    public static func encode(_ tokens: [DataToken]) -> String {
        tokens.map(\.encoded).joined()
    }

    /// ブロックヘッダの長さが後続トークン数と整合しているか検証する。
    /// Builder が生成した URL の自己整合性テスト、および契約監視の構造比較で使う。
    public static func isStructurallyConsistent(_ tokens: [DataToken]) -> Bool {
        validate(tokens, from: 0, count: tokens.count)
    }

    private static func validate(_ tokens: [DataToken], from start: Int, count: Int) -> Bool {
        var index = start
        let end = start + count
        guard end <= tokens.count else { return false }
        while index < end {
            let token = tokens[index]
            index += 1
            guard let length = token.blockLength else { continue }
            guard index + length <= end else { return false }
            guard validate(tokens, from: index, count: length) else { return false }
            index += length
        }
        return index == end
    }
}
