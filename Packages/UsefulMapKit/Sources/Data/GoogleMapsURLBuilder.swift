import Domain
import Foundation

/// 移動手段の Google 側表現。Domain には持たせず、この層で対応付ける。
extension TransportMode {
    /// 公式 Maps URLs の travelmode 値（公開 API なので生成対象に含めない）。
    var googleTravelMode: String {
        switch self {
        case .transit: return "transit"
        case .walking: return "walking"
        case .driving: return "driving"
        }
    }

    /// 内部 data= のモードコード。値は生成された形式定義から引く。
    var googleDataModeCode: String? {
        GoogleMapsURLFormat.modeCode[rawValue]
    }
}

/// Google Maps への外部詳細遷移 URL を組み立てる（仕様書 7）。
///
/// 形式そのもの（トークンの並びと定数値）は `GoogleMapsURLFormat+Generated.swift` にあり、
/// `contract-watch/format.json` から生成される。この型が持つのは
/// 「地点の数だけブロックを並べ、ブロック長を数え、パスを組む」という手続きだけで、
/// 契約監視の自動修復が変更するのは前者に限られる。
///
/// 非公開仕様はこの一群の外へ漏らさない（非機能要件 14）。
/// アプリ本体の経路取得はこれに依存しないため、形式が壊れても比較機能は動き続ける。
public struct GoogleMapsURLBuilder: RouteDetailLinking {
    public static var host: String { GoogleMapsURLFormat.host }

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

        let timestamp = GoogleTimestamp.value(for: anchor.date, timeZone: timeZone)
        guard let tokens = Self.dataTokens(places: places,
                                           anchor: anchor,
                                           timestamp: timestamp,
                                           mode: option.mode),
              GoogleMapsDataParam.isStructurallyConsistent(tokens) else { return nil }

        let path = places.map { Self.pathSegment(for: $0) }.joined(separator: "/")
        let string = GoogleMapsURLFormat.host
            + GoogleMapsURLFormat.pathPrefix
            + path
            + GoogleMapsURLFormat.dataPrefix
            + GoogleMapsDataParam.encode(tokens)
        return URL(string: string)
    }

    /// data= のトークン列を組み立てる。
    ///
    ///   wrapper                        … 全体を包むブロック（後続トークン数を持つ）
    ///   placeBlock × 地点数             … 出発地 → 経由地 → 目的地
    ///   timeBlock                      … 出発 / 到着の指定と時刻
    ///   modeToken                      … 移動手段
    ///
    /// 地点に Google Place ID は要求せず、名称と緯度経度だけで生成する（仕様書 7.2）。
    static func dataTokens(places: [Place],
                           anchor: TimeAnchor,
                           timestamp: Int,
                           mode: TransportMode) -> [DataToken]? {
        guard let timeMode = GoogleMapsURLFormat.timeMode[anchor.kind == .arrive ? "arriveBy" : "departAt"],
              let modeCode = GoogleMapsURLFormat.modeCode[mode.rawValue] else { return nil }

        var body: [DataToken] = []
        for place in places {
            guard let tokens = placeTokens(place) else { return nil }
            body += tokens
        }

        let timeSubstitutions: [FormatPlaceholder: String] = [
            .timeMode: timeMode,
            .timestamp: String(timestamp)
        ]
        for token in GoogleMapsURLFormat.timeBlock {
            guard let resolved = token.resolved(with: timeSubstitutions) else { return nil }
            body.append(resolved)
        }

        guard let modeToken = GoogleMapsURLFormat.modeToken.resolved(with: [.modeCode: modeCode]) else {
            return nil
        }
        body.append(modeToken)

        let wrapperSubstitutions: [FormatPlaceholder: String] = [
            .outerCount: String(body.count + 1),
            .innerCount: String(body.count)
        ]
        var wrapper: [DataToken] = []
        for token in GoogleMapsURLFormat.wrapper {
            guard let resolved = token.resolved(with: wrapperSubstitutions) else { return nil }
            wrapper.append(resolved)
        }
        return wrapper + body
    }

    static func placeTokens(_ place: Place) -> [DataToken]? {
        let substitutions: [FormatPlaceholder: String] = [
            .longitude: place.coordinate.longitudeString,
            .latitude: place.coordinate.latitudeString
        ]
        var tokens: [DataToken] = []
        for token in GoogleMapsURLFormat.placeBlock {
            guard let resolved = token.resolved(with: substitutions) else { return nil }
            tokens.append(resolved)
        }
        return tokens
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

        var components = URLComponents(string: GoogleMapsURLFormat.host + GoogleMapsURLFormat.pathPrefix)
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
