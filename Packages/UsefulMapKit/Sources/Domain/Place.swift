import Foundation

/// 内部地点モデル（仕様書 5.1）。
/// name / latitude / longitude が必須、address は UI 補助のみで URL 生成には必須ではない。
public struct Place: Identifiable, Hashable, Codable, Sendable {
    public var name: String
    public var coordinate: Coordinate
    public var address: String?

    public init(name: String, coordinate: Coordinate, address: String? = nil) {
        self.name = Place.normalizedName(name)
        self.coordinate = coordinate
        self.address = Place.normalizedAddress(address)
    }

    public init(name: String, latitude: Double, longitude: Double, address: String? = nil) {
        self.init(name: name,
                  coordinate: Coordinate(latitude: latitude, longitude: longitude),
                  address: address)
    }

    /// 永続化・重複判定で安定して使える ID（UUID だと保存往復で同一性が壊れる）。
    public var id: String {
        "\(name)@\(coordinate.latitudeString),\(coordinate.longitudeString)"
    }

    public var isUsableForRouting: Bool {
        !name.isEmpty && coordinate.isValid
    }

    /// 表示名が空の地点は座標を表示名として使う。
    public var displayName: String {
        name.isEmpty ? "\(coordinate.latitudeString), \(coordinate.longitudeString)" : name
    }

    public static func normalizedName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizedAddress(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
