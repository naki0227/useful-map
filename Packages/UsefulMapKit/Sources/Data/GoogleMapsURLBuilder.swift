import Domain
import Foundation

/// Google Maps への外部詳細遷移 URL を組み立てる（仕様書 7）。
///
/// 非公開の `data=` 形式はこの型と `GoogleMapsDataParam` の外へ漏らさない（非機能要件 14）。
/// アプリ本体の経路取得はこの型に依存しないため、形式が壊れても比較機能は動き続ける。
/// 移動手段の Google 側表現。Domain には持たせず、この層で対応付ける。
extension TransportMode {
    /// 公式 Maps URLs の travelmode 値。
    var googleTravelMode: String {
        switch self {
        case .transit: return "transit"
        case .walking: return "walking"
        case .driving: return "driving"
        }
    }

    /// 内部 data= のモードコード（`!3e` に載る値）。
    var googleDataModeCode: String {
        switch self {
        case .driving: return "0"
        case .walking: return "2"
        case .transit: return "3"
        }
    }
}

public struct GoogleMapsURLBuilder: RouteDetailLinking {
    public static let host = "https://www.google.com"

    private let timeZone: TimeZone
    private let opener: URLOpening

    public init(timeZone: TimeZone = .current, opener: URLOpening) {
        self.timeZone = timeZone
        self.opener = opener
    }

    // MARK: - Primary（時刻付き内部形式）

    public func primaryURL(for option: RouteOption) -> URL? {
        guard let anchor = option.timeAnchor else { return nil }
        let places = option.orderedPlaces
        guard places.count >= 2, places.allSatisfy({ $0.coordinate.isValid }) else { return nil }

        let path = places.map { Self.pathSegment(for: $0) }.joined(separator: "/")
        let tokens = Self.dataTokens(places: places,
                                     anchor: anchor,
                                     timestamp: GoogleTimestamp.value(for: anchor.date, timeZone: timeZone),
                                     mode: option.mode)
        guard GoogleMapsDataParam.isStructurallyConsistent(tokens) else { return nil }
        return URL(string: "\(Self.host)/maps/dir/\(path)/data=\(GoogleMapsDataParam.encode(tokens))")
    }

    /// data= のトークン列を組み立てる。
    ///
    ///   !4m{n+1}!4m{n}                 … 全体を包むブロック
    ///   !1m5!1m1!1s0x0:0x0!2m2!1d{lng}!2d{lat}   … 地点ブロック（出発地→経由地→目的地）
    ///   !2m3!6e{0|1}!7e2!8j{timestamp} … 時刻ブロック（6e0=出発指定 / 6e1=到着指定）
    ///   !3e{mode}                      … 移動手段
    ///
    /// 地点に Google Place ID は要求せず、名称と緯度経度だけで生成する（仕様書 7.2）。
    static func dataTokens(places: [Place],
                           anchor: TimeAnchor,
                           timestamp: Int,
                           mode: TransportMode) -> [DataToken] {
        var body: [DataToken] = places.flatMap(placeTokens)
        body += [
            DataToken(group: 2, kind: "m", value: "3"),
            DataToken(group: 6, kind: "e", value: anchor.kind == .arrive ? "1" : "0"),
            DataToken(group: 7, kind: "e", value: "2"),
            DataToken(group: 8, kind: "j", value: String(timestamp))
        ]
        body.append(DataToken(group: 3, kind: "e", value: mode.googleDataModeCode))

        return [
            DataToken(group: 4, kind: "m", value: String(body.count + 1)),
            DataToken(group: 4, kind: "m", value: String(body.count))
        ] + body
    }

    static func placeTokens(_ place: Place) -> [DataToken] {
        [
            DataToken(group: 1, kind: "m", value: "5"),
            DataToken(group: 1, kind: "m", value: "1"),
            // Place ID を使わない場合の中立値。
            DataToken(group: 1, kind: "s", value: "0x0:0x0"),
            DataToken(group: 2, kind: "m", value: "2"),
            DataToken(group: 1, kind: "d", value: place.coordinate.longitudeString),
            DataToken(group: 2, kind: "d", value: place.coordinate.latitudeString)
        ]
    }

    /// URL パスに載せる地点名。名前が無い地点は座標を使う。
    static func pathSegment(for place: Place) -> String {
        let name = place.name
        if name.isEmpty {
            return "\(place.coordinate.latitudeString),\(place.coordinate.longitudeString)"
        }
        let plusEncoded = name.replacingOccurrences(of: " ", with: "+")
        return plusEncoded.addingPercentEncoding(withAllowedCharacters: Self.pathAllowed) ?? plusEncoded
    }

    private static let pathAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~+,")
        return set
    }()

    // MARK: - Official fallback（公式 Maps URLs）

    public func officialURL(for option: RouteOption) -> URL? {
        let places = option.orderedPlaces
        guard let origin = places.first, let destination = places.last, places.count >= 2 else { return nil }
        guard origin.coordinate.isValid, destination.coordinate.isValid else { return nil }

        var components = URLComponents(string: "\(Self.host)/maps/dir/")
        var items = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: Self.coordinateValue(origin)),
            URLQueryItem(name: "destination", value: Self.coordinateValue(destination)),
            URLQueryItem(name: "travelmode", value: option.mode.googleTravelMode)
        ]
        let waypoints = places.dropFirst().dropLast()
        if !waypoints.isEmpty {
            items.append(URLQueryItem(name: "waypoints",
                                      value: waypoints.map(Self.coordinateValue).joined(separator: "|")))
        }
        components?.queryItems = items
        return components?.url
    }

    static func coordinateValue(_ place: Place) -> String {
        "\(place.coordinate.latitudeString),\(place.coordinate.longitudeString)"
    }

    // MARK: - 遷移

    /// Primary → 開けなければ Official の順で試す（仕様書 7.4 / 13）。
    public func open(_ option: RouteOption) async -> DetailOpenOutcome {
        if let primary = primaryURL(for: option), await opener.open(primary) {
            return .openedPrimary
        }
        if let official = officialURL(for: option), await opener.open(official) {
            return .openedFallback
        }
        return .failed
    }
}
