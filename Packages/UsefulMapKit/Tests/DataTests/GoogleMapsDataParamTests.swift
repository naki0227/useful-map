import Foundation
import Testing

@testable import Data

@Suite("GoogleMapsDataParam（data= トークン）")
struct GoogleMapsDataParamTests {
    @Test("トークン列へ分解できる")
    func parsesTokens() throws {
        let tokens = try #require(GoogleMapsDataParam.parse("!4m8!4m7!1m1!1s0x0:0x0!2m3!6e0!7e2!8j1786703520"))
        #expect(tokens.count == 8)
        #expect(tokens[0] == DataToken(group: 4, kind: "m", value: "8"))
        #expect(tokens[3] == DataToken(group: 1, kind: "s", value: "0x0:0x0"))
        #expect(tokens[7] == DataToken(group: 8, kind: "j", value: "1786703520"))
    }

    @Test("encode は parse の逆写像")
    func roundTrip() throws {
        let raw = "!4m14!1m5!1m1!1s0x0:0x0!2m2!1d139.7671248!2d35.6812362!2m3!6e1!7e2!8j1786704840!3e3"
        let tokens = try #require(GoogleMapsDataParam.parse(raw))
        #expect(GoogleMapsDataParam.encode(tokens) == raw)
    }

    @Test("形式不正は nil",
          arguments: ["", "4m8", "!", "!!4m8", "!m8", "!4", "!4m8!"])
    func rejectsMalformed(raw: String) {
        #expect(GoogleMapsDataParam.parse(raw) == nil)
    }

    @Test("ブロック長が後続トークン数と一致していれば整合")
    func consistentStructure() throws {
        // !1m5 が 5 トークンを束ね、その内側の !1m1 と !2m2 も整合している。
        let tokens = try #require(GoogleMapsDataParam.parse("!1m5!1m1!1s0x0:0x0!2m2!1d139.0!2d35.0"))
        #expect(GoogleMapsDataParam.isStructurallyConsistent(tokens))
    }

    @Test("ブロック長が実際のトークン数を超える場合は不整合として検出する")
    func detectsInconsistentStructure() throws {
        // 先頭ブロックが 9 トークンを要求するが、後続は 5 つしかない。
        let tooLong = try #require(GoogleMapsDataParam.parse("!1m9!1m1!1s0x0:0x0!2m2!1d139.0!2d35.0"))
        #expect(!GoogleMapsDataParam.isStructurallyConsistent(tooLong))

        // 入れ子ブロック(!2m2)が親(!1m3)の範囲をはみ出す。
        let overflowing = try #require(GoogleMapsDataParam.parse("!1m3!1m1!1s0x0:0x0!2m2!1d139.0!2d35.0"))
        #expect(!GoogleMapsDataParam.isStructurallyConsistent(overflowing))
    }

    @Test("末尾が途中で切れたブロックも不整合として検出する")
    func detectsTruncatedStructure() throws {
        let truncated = try #require(GoogleMapsDataParam.parse("!1m5!1m1!1s0x0:0x0!2m2!1d139.0"))
        #expect(!GoogleMapsDataParam.isStructurallyConsistent(truncated))
    }

    @Test("ブロックヘッダの判定")
    func blockHeaderDetection() {
        #expect(DataToken(group: 4, kind: "m", value: "17").isBlockHeader)
        #expect(DataToken(group: 4, kind: "m", value: "17").blockLength == 17)
        #expect(!DataToken(group: 8, kind: "j", value: "1786703520").isBlockHeader)
        #expect(DataToken(group: 8, kind: "j", value: "1786703520").blockLength == nil)
    }

    @Test("encoded は URL に載る形")
    func encodedForm() {
        #expect(DataToken(group: 6, kind: "e", value: "1").encoded == "!6e1")
        #expect(DataToken(group: 6, kind: "e", value: "1").description == "!6e1")
    }
}
