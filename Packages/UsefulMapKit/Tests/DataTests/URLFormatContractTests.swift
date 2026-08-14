import Domain
import Foundation
import Testing

@testable import Data

/// Swift 実装と契約監視（contract-watch/format.json）が同じ形式を指しているかを検証する。
///
/// CI の自動修復は format.json を書き換えるため、この橋渡しが無いと
/// 「監視は直ったがアプリは古い形式のまま」という状態を見逃す。
@Suite("URL 形式の契約（format.json）")
struct URLFormatContractTests {
    struct FormatToken: Decodable {
        let group: Int
        let kind: String
        let value: String
    }

    struct Format: Decodable {
        struct Wrapper: Decodable {
            let outer: FormatToken
            let inner: FormatToken
        }

        let host: String
        let pathPrefix: String
        let dataPrefix: String
        let wrapper: Wrapper
        let placeBlock: [FormatToken]
        let timeBlock: [FormatToken]
        let modeToken: FormatToken
        let timeMode: [String: String]
        let modeCode: [String: String]
        let coordinatePrecision: Int
    }

    static func loadFormat() throws -> Format {
        // Tests/DataTests/URLFormatContractTests.swift → リポジトリルート → contract-watch/format.json
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DataTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // Tests の親（UsefulMapKit）
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // リポジトリルート
            .appendingPathComponent("contract-watch/format.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Format.self, from: data)
    }

    private func tokens(from url: URL) throws -> [DataToken] {
        let raw = try #require(url.absoluteString.components(separatedBy: "/data=").last)
        return try #require(GoogleMapsDataParam.parse(raw))
    }

    private func makeOption(mode: TransportMode = .transit,
                            preference: TimePreference = .departAt) -> RouteOption {
        let timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 10, minute: 32))!
        let query = RouteQuery(destination: Place(name: "東京駅", latitude: 35.6812362, longitude: 139.7671248),
                               transportMode: mode,
                               timePreference: preference,
                               requestedDate: date)
        return RouteOption(query: query,
                           origin: Place(name: "御茶ノ水駅", latitude: 35.6993, longitude: 139.7649),
                           mode: mode,
                           expectedTravelTime: 22 * 60)
    }

    private func makeBuilder() -> GoogleMapsURLBuilder {
        GoogleMapsURLBuilder(timeZone: TimeZone(identifier: "Asia/Tokyo")!,
                             opener: RecordingURLOpener())
    }

    @Test("ホストとパス接頭辞が一致する")
    func hostAndPath() throws {
        let format = try Self.loadFormat()
        let url = try #require(makeBuilder().primaryURL(for: makeOption()))
        #expect(url.absoluteString.hasPrefix(format.host + format.pathPrefix))
        #expect(url.absoluteString.contains(format.dataPrefix))
        #expect(GoogleMapsURLBuilder.host == format.host)
    }

    @Test("地点ブロックの定数トークンが一致する")
    func placeBlockMatches() throws {
        let format = try Self.loadFormat()
        let generated = GoogleMapsURLBuilder.placeTokens(
            Place(name: "東京駅", latitude: 35.6812362, longitude: 139.7671248)
        )
        #expect(generated.count == format.placeBlock.count)
        for (token, expected) in zip(generated, format.placeBlock) {
            #expect(token.group == expected.group)
            #expect(String(token.kind) == expected.kind)
            if !expected.value.contains("{") {
                #expect(token.value == expected.value,
                        "定数トークン !\(expected.group)\(expected.kind) がずれている")
            }
        }
    }

    @Test("時刻ブロックとモードトークンが一致する")
    func timeAndModeTokensMatch() throws {
        let format = try Self.loadFormat()
        let tokens = try tokens(from: #require(makeBuilder().primaryURL(for: makeOption())))

        // 時刻ブロックは末尾から 5 番目〜2 番目（最後はモードトークン）。
        let timeTokens = Array(tokens.suffix(5).prefix(4))
        #expect(timeTokens.count == format.timeBlock.count)
        for (token, expected) in zip(timeTokens, format.timeBlock) {
            #expect(token.group == expected.group)
            #expect(String(token.kind) == expected.kind)
            if !expected.value.contains("{") {
                #expect(token.value == expected.value)
            }
        }

        let modeToken = try #require(tokens.last)
        #expect(modeToken.group == format.modeToken.group)
        #expect(String(modeToken.kind) == format.modeToken.kind)
        #expect(modeToken.value == format.modeCode["transit"])
    }

    @Test("出発 / 到着フラグの値が一致する")
    func timeModeValues() throws {
        let format = try Self.loadFormat()
        let builder = makeBuilder()

        let departTokens = try tokens(from: #require(builder.primaryURL(for: makeOption(preference: .departAt))))
        let departFlag = try #require(departTokens.first { $0.group == 6 && $0.kind == "e" })
        #expect(departFlag.value == format.timeMode["departAt"])

        let arriveTokens = try tokens(from: #require(builder.primaryURL(for: makeOption(preference: .arriveBy))))
        let arriveFlag = try #require(arriveTokens.first { $0.group == 6 && $0.kind == "e" })
        #expect(arriveFlag.value == format.timeMode["arriveBy"])
    }

    @Test("移動手段コードが一致する")
    func modeCodes() throws {
        let format = try Self.loadFormat()
        #expect(TransportMode.transit.googleDataModeCode == format.modeCode["transit"])
        #expect(TransportMode.walking.googleDataModeCode == format.modeCode["walking"])
        #expect(TransportMode.driving.googleDataModeCode == format.modeCode["driving"])
    }

    @Test("ラッパーのブロック長の決め方が一致する")
    func wrapperCounts() throws {
        let format = try Self.loadFormat()
        let tokens = try tokens(from: #require(makeBuilder().primaryURL(for: makeOption())))
        let outer = tokens[0]
        let inner = tokens[1]

        #expect(outer.group == format.wrapper.outer.group)
        #expect(String(outer.kind) == format.wrapper.outer.kind)
        #expect(inner.group == format.wrapper.inner.group)
        #expect(String(inner.kind) == format.wrapper.inner.kind)

        let bodyCount = tokens.count - 2
        #expect(inner.value == String(bodyCount))
        #expect(outer.value == String(bodyCount + 1))
    }

    @Test("座標の桁数が一致する")
    func coordinatePrecision() throws {
        let format = try Self.loadFormat()
        let decimals = Coordinate(latitude: 35.6812362, longitude: 139.7671248)
            .latitudeString
            .split(separator: ".")
            .last?
            .count
        #expect(decimals == format.coordinatePrecision)
    }
}
