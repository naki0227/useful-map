import Domain
import Foundation
import Testing

@testable import Data

/// URL を開いた記録を残すだけの opener。
final class RecordingURLOpener: URLOpening, @unchecked Sendable {
    private let rejects: (URL) -> Bool
    private(set) var opened: [URL] = []

    init(rejects: @escaping (URL) -> Bool = { _ in false }) {
        self.rejects = rejects
    }

    func open(_ url: URL) async -> Bool {
        if rejects(url) { return false }
        opened.append(url)
        return true
    }
}

@Suite("GoogleMapsURLBuilder")
struct GoogleMapsURLBuilderTests {
    private let tokyoTimeZone = TimeZone(identifier: "Asia/Tokyo")!
    private let currentLocation = Place(name: "現在地", latitude: 35.6993, longitude: 139.7649)
    private let tokyoStation = Place(name: "東京駅", latitude: 35.6812362, longitude: 139.7671248)
    private let shinjukuGyoen = Place(name: "新宿御苑", latitude: 35.6852, longitude: 139.7100)

    private func date(_ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyoTimeZone
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 14,
                                                  hour: hour, minute: minute))!
    }

    private func makeOption(mode: TransportMode = .transit,
                            timePreference: TimePreference = .now,
                            requestedDate: Date? = nil,
                            departure: Date? = nil,
                            arrival: Date? = nil,
                            waypoints: [Place] = [],
                            origin: Place? = nil,
                            destination: Place? = nil) -> RouteOption {
        let query = RouteQuery(destination: destination ?? tokyoStation,
                               waypoints: waypoints,
                               transportMode: mode,
                               timePreference: timePreference,
                               requestedDate: requestedDate)
        return RouteOption(query: query,
                           origin: origin ?? currentLocation,
                           mode: mode,
                           expectedTravelTime: 22 * 60,
                           departureDate: departure,
                           arrivalDate: arrival)
    }

    private func makeBuilder(rejects: @escaping (URL) -> Bool = { _ in false })
        -> (GoogleMapsURLBuilder, RecordingURLOpener) {
        let opener = RecordingURLOpener(rejects: rejects)
        return (GoogleMapsURLBuilder(timeZone: tokyoTimeZone, opener: opener), opener)
    }

    // MARK: - Primary URL

    /// 現行形式のスナップショット。
    ///
    /// 形式そのものは `contract-watch/format.json` から生成されるため、
    /// 契約監視の自動修復で形式が変われば、このテストは意図的に落ちる。
    /// 落ちたときは差分が妥当かを確認したうえで期待値を更新すること
    /// （＝形式変更を人間が承認する場所）。
    @Test("出発時刻付きの Primary URL を生成する（現行形式のスナップショット）")
    func primaryDepartAt() throws {
        let (builder, _) = makeBuilder()
        let option = makeOption(departure: date(10, 32))
        let url = try #require(builder.primaryURL(for: option))

        #expect(url.absoluteString == "https://www.google.com/maps/dir/"
                + "%E7%8F%BE%E5%9C%A8%E5%9C%B0/%E6%9D%B1%E4%BA%AC%E9%A7%85/data="
                + "!4m14!4m13"
                + "!1m3!2m2!1d139.7649000!2d35.6993000"
                + "!1m3!2m2!1d139.7671248!2d35.6812362"
                + "!2m3!6e0!7e2!8j1786703520"
                + "!3e3")
    }

    @Test("到着指定は !6e1 になり、到着時刻が埋まる")
    func primaryArriveBy() throws {
        let (builder, _) = makeBuilder()
        let option = makeOption(timePreference: .arriveBy,
                                requestedDate: date(11, 0),
                                arrival: date(10, 54))
        let url = try #require(builder.primaryURL(for: option))
        #expect(url.absoluteString.contains("!2m3!6e1!7e2!8j1786704840"))
    }

    @Test("data= の構造は自己整合している（ブロック長が正しい）")
    func primaryStructureIsConsistent() throws {
        let (builder, _) = makeBuilder()
        for waypoints in [[], [shinjukuGyoen]] {
            let option = makeOption(mode: .walking, departure: date(10, 32), waypoints: waypoints)
            let url = try #require(builder.primaryURL(for: option))
            let raw = try #require(url.absoluteString.components(separatedBy: "/data=").last)
            let tokens = try #require(GoogleMapsDataParam.parse(raw))
            #expect(GoogleMapsDataParam.isStructurallyConsistent(tokens))
        }
    }

    @Test("経由地は地点ブロックが増え、ブロック長も追随する（徒歩・車のみ）")
    func primaryWithWaypoint() throws {
        // Google は公共交通で経由地に対応しないため、経由地の検証は徒歩で行う。
        let (builder, _) = makeBuilder()
        let option = makeOption(mode: .walking, departure: date(10, 32), waypoints: [shinjukuGyoen])
        let url = try #require(builder.primaryURL(for: option))
        let raw = try #require(url.absoluteString.components(separatedBy: "/data=").last)
        let tokens = try #require(GoogleMapsDataParam.parse(raw))

        // 地点 3 つ ×4 + 時刻 4 + モード 1 = 17
        #expect(tokens[0] == DataToken(group: 4, kind: "m", value: "18"))
        #expect(tokens[1] == DataToken(group: 4, kind: "m", value: "17"))
        #expect(url.absoluteString.contains("!1d139.7100000!2d35.6852000"))
        #expect(url.path.contains("新宿御苑".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
                || url.absoluteString.contains("%E6%96%B0%E5%AE%BF%E5%BE%A1%E8%8B%91"))
    }

    @Test("経度→緯度の順（!1d が経度、!2d が緯度）で埋める")
    func longitudeBeforeLatitude() throws {
        let (builder, _) = makeBuilder()
        let url = try #require(builder.primaryURL(for: makeOption(departure: date(10, 32))))
        let raw = url.absoluteString
        let longitudeIndex = try #require(raw.range(of: "!1d139.7671248"))
        let latitudeIndex = try #require(raw.range(of: "!2d35.6812362"))
        #expect(longitudeIndex.lowerBound < latitudeIndex.lowerBound)
    }

    @Test("移動手段は !3e で表現する", arguments: [
        (TransportMode.transit, "!3e3"),
        (TransportMode.walking, "!3e2"),
        (TransportMode.driving, "!3e0")
    ])
    func primaryModeCode(mode: TransportMode, expected: String) throws {
        let (builder, _) = makeBuilder()
        let url = try #require(builder.primaryURL(for: makeOption(mode: mode, departure: date(10, 32))))
        #expect(url.absoluteString.hasSuffix(expected))
    }

    @Test("時刻条件が取れない候補では Primary URL を作らない")
    func primaryRequiresTimeAnchor() {
        let (builder, _) = makeBuilder()
        #expect(builder.primaryURL(for: makeOption()) == nil)
    }

    @Test("座標が壊れている場合は Primary URL を作らない")
    func primaryRejectsBrokenCoordinates() {
        let (builder, _) = makeBuilder()
        let broken = Place(name: "壊れた地点", latitude: 0, longitude: 0)
        let option = makeOption(departure: date(10, 32), destination: broken)
        #expect(builder.primaryURL(for: option) == nil)
    }

    @Test("名前の空白は + に、日本語はパーセントエンコードされる")
    func pathEncoding() {
        #expect(GoogleMapsURLBuilder.pathSegment(for: Place(name: "Tokyo Station",
                                                            latitude: 35.68,
                                                            longitude: 139.76)) == "Tokyo+Station")
        #expect(GoogleMapsURLBuilder.pathSegment(for: Place(name: "東京駅",
                                                            latitude: 35.68,
                                                            longitude: 139.76))
                == "%E6%9D%B1%E4%BA%AC%E9%A7%85")
    }

    @Test("名前が無い地点はパスに座標を使う")
    func pathEncodingFallsBackToCoordinates() {
        let place = Place(name: "", latitude: 35.6812362, longitude: 139.7671248)
        #expect(GoogleMapsURLBuilder.pathSegment(for: place) == "35.6812362,139.7671248")
    }

    @Test("スラッシュを含む名前でもパス構造を壊さない")
    func pathEncodingEscapesSlash() {
        let place = Place(name: "A/B ビル", latitude: 35.68, longitude: 139.76)
        let segment = GoogleMapsURLBuilder.pathSegment(for: place)
        #expect(!segment.contains("/"))
        #expect(segment.contains("%2F"))
    }

    // MARK: - Official URL

    @Test("公式 Directions URL は api=1 と travelmode を持つ")
    func officialURL() throws {
        let (builder, _) = makeBuilder()
        let url = try #require(builder.officialURL(for: makeOption()))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        #expect(components.host == "www.google.com")
        #expect(components.path == "/maps/dir/")
        #expect(items["api"] == "1")
        #expect(items["origin"] == "35.6993000,139.7649000")
        #expect(items["destination"] == "35.6812362,139.7671248")
        #expect(items["travelmode"] == "transit")
        // 公式 URL は時刻条件を保証しないため、時刻パラメータは付けない。
        #expect(items["waypoints"] == nil)
    }

    @Test("経由地は waypoints パラメータで渡す（徒歩・車のみ）")
    func officialURLWithWaypoints() throws {
        let (builder, _) = makeBuilder()
        let url = try #require(builder.officialURL(for: makeOption(mode: .walking,
                                                                   waypoints: [shinjukuGyoen])))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let waypoints = components.queryItems?.first { $0.name == "waypoints" }?.value
        #expect(waypoints == "35.6852000,139.7100000")
    }

    @Test("公式 URL は時刻条件が無い候補でも生成できる")
    func officialURLWithoutTimeAnchor() {
        let (builder, _) = makeBuilder()
        #expect(builder.officialURL(for: makeOption()) != nil)
    }

    @Test("座標が壊れていれば公式 URL も作らない")
    func officialURLRejectsBrokenCoordinates() {
        let (builder, _) = makeBuilder()
        let broken = Place(name: "壊れた地点", latitude: 0, longitude: 0)
        #expect(builder.officialURL(for: makeOption(destination: broken)) == nil)
    }

    // MARK: - open()

    @Test("Primary が開ければ openedPrimary")
    func openPrimary() async throws {
        let (builder, opener) = makeBuilder()
        let outcome = await builder.open(makeOption(departure: date(10, 32)))
        #expect(outcome == .openedPrimary)
        #expect(opener.opened.count == 1)
        #expect(opener.opened[0].absoluteString.contains("/data="))
    }

    @Test("Primary が開けなければ公式 URL へ fallback する")
    func openFallsBackWhenPrimaryFails() async throws {
        let (builder, opener) = makeBuilder(rejects: { $0.absoluteString.contains("/data=") })
        let outcome = await builder.open(makeOption(departure: date(10, 32)))
        #expect(outcome == .openedFallback)
        #expect(opener.opened.count == 1)
        #expect(opener.opened[0].absoluteString.contains("api=1"))
    }

    @Test("Primary を生成できない場合も公式 URL へ fallback する")
    func openFallsBackWhenPrimaryMissing() async throws {
        let (builder, opener) = makeBuilder()
        let outcome = await builder.open(makeOption())
        #expect(outcome == .openedFallback)
        #expect(opener.opened[0].absoluteString.contains("travelmode=transit"))
    }

    @Test("どちらも開けなければ failed")
    func openFails() async throws {
        let (builder, opener) = makeBuilder(rejects: { _ in true })
        let outcome = await builder.open(makeOption(departure: date(10, 32)))
        #expect(outcome == .failed)
        #expect(opener.opened.isEmpty)
    }

    // MARK: - 隔離

    @Test("生成 URL は Google Place ID を含めない")
    func doesNotIncludePlaceID() throws {
        let (builder, _) = makeBuilder()
        let url = try #require(builder.primaryURL(for: makeOption(departure: date(10, 32))))
        // Place ID を入れると Google が解決に失敗し、地点が見つからなくなる。
        // 座標だけを渡すのが正しい（実機で検証済み）。
        #expect(!url.absoluteString.contains("!1s"))
        #expect(!url.absoluteString.contains("place_id"))
        #expect(url.absoluteString.contains("!1m3!2m2!1d"))
    }
}

@Suite("移動手段の Google 表現")
struct GoogleTransportMappingTests {
    @Test("公式 URL の travelmode 値")
    func travelMode() {
        #expect(TransportMode.transit.googleTravelMode == "transit")
        #expect(TransportMode.walking.googleTravelMode == "walking")
        #expect(TransportMode.driving.googleTravelMode == "driving")
    }

    @Test("内部 data= のモードコード")
    func dataModeCode() {
        #expect(TransportMode.driving.googleDataModeCode == "0")
        #expect(TransportMode.walking.googleDataModeCode == "2")
        #expect(TransportMode.transit.googleDataModeCode == "3")
    }
}

@Suite("Google の経由地制約")
struct GoogleWaypointConstraintTests {
    private let tokyoTimeZone = TimeZone(identifier: "Asia/Tokyo")!
    private let origin = Place(name: "自宅", latitude: 35.7029, longitude: 139.7649)
    private let station = Place(name: "御茶ノ水駅", latitude: 35.6993, longitude: 139.7649)
    private let destination = Place(name: "東京駅", latitude: 35.6812362, longitude: 139.7671248)

    private func option(mode: TransportMode) -> RouteOption {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyoTimeZone
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14,
                                                      hour: 10, minute: 32))!
        let query = RouteQuery(destination: destination,
                               waypoints: [station],
                               transportMode: mode,
                               timePreference: .departAt,
                               requestedDate: date)
        return RouteOption(query: query, origin: origin, mode: mode,
                           expectedTravelTime: 22 * 60, departureDate: date)
    }

    private func makeBuilder() -> GoogleMapsURLBuilder {
        GoogleMapsURLBuilder(timeZone: tokyoTimeZone, opener: RecordingURLOpener())
    }

    @Test("公共交通では経由地を渡さない（Google が乗換案内を計算できなくなるため）")
    func dropsWaypointsForTransit() throws {
        let places = GoogleMapsURLBuilder.placesForGoogle(option(mode: .transit))
        #expect(places.map(\.name) == ["自宅", "東京駅"])

        let url = try #require(makeBuilder().primaryURL(for: option(mode: .transit)))
        #expect(!url.absoluteString.contains("139.7649000!2d35.6993000"),
                "経由地の座標ブロックが入っている")
        // 地点ブロックは 2 つ ×4 + 時刻 4 + モード 1 = 13。
        let raw = try #require(url.absoluteString.components(separatedBy: "/data=").last)
        let tokens = try #require(GoogleMapsDataParam.parse(raw))
        #expect(tokens[1] == DataToken(group: 4, kind: "m", value: "13"))
    }

    @Test("公式 URL でも公共交通では waypoints を付けない")
    func officialURLDropsWaypointsForTransit() throws {
        let url = try #require(makeBuilder().officialURL(for: option(mode: .transit)))
        #expect(!url.absoluteString.contains("waypoints"))
    }

    @Test("徒歩・車は経由地に対応しているのでそのまま渡す",
          arguments: [TransportMode.walking, TransportMode.driving])
    func keepsWaypointsForOtherModes(mode: TransportMode) throws {
        let places = GoogleMapsURLBuilder.placesForGoogle(option(mode: mode))
        #expect(places.map(\.name) == ["自宅", "御茶ノ水駅", "東京駅"])

        let url = try #require(makeBuilder().officialURL(for: option(mode: mode)))
        #expect(url.absoluteString.contains("waypoints"))
    }
}
