// このファイルは自動生成されています。直接編集しないでください。
//
// 生成元 : contract-watch/format.json
// 生成器 : contract-watch/src/generate-swift.mjs
// 再生成 : make generate-format
//
// Google Maps の非公開 data= 形式が変わった場合、契約監視 CI が最小差分を
// format.json へ当ててから、この生成器で Swift まで更新して PR を作る。

import Foundation

enum GoogleMapsURLFormat {
    static let host = "https://www.google.com"
    static let pathPrefix = "/maps/dir/"
    static let dataPrefix = "/data="
    static let coordinatePrecision = 7

    /// 全体を包むブロック。
    static let wrapper: [FormatToken] = [
        FormatToken(group: 4, kind: "m", value: .placeholder(.outerCount)),
        FormatToken(group: 4, kind: "m", value: .placeholder(.innerCount))
    ]

    /// 地点 1 つぶんのブロック。
    static let placeBlock: [FormatToken] = [
        FormatToken(group: 1, kind: "m", value: .constant("3")),
        FormatToken(group: 2, kind: "m", value: .constant("2")),
        FormatToken(group: 1, kind: "d", value: .placeholder(.longitude)),
        FormatToken(group: 2, kind: "d", value: .placeholder(.latitude))
    ]

    /// 時刻条件のブロック。
    static let timeBlock: [FormatToken] = [
        FormatToken(group: 2, kind: "m", value: .constant("3")),
        FormatToken(group: 6, kind: "e", value: .placeholder(.timeMode)),
        FormatToken(group: 7, kind: "e", value: .constant("2")),
        FormatToken(group: 8, kind: "j", value: .placeholder(.timestamp))
    ]

    /// 移動手段のトークン。
    static let modeToken: FormatToken =
        FormatToken(group: 3, kind: "e", value: .placeholder(.modeCode))

    /// 出発指定 / 到着指定の値。
    static let timeMode: [String: String] = [
        "departAt": "0",
        "arriveBy": "1"
    ]

    /// 移動手段コード（キーは TransportMode の rawValue）。
    static let modeCode: [String: String] = [
        "driving": "0",
        "walking": "2",
        "transit": "3"
    ]
}
