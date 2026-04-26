import Foundation

public struct ScannerSystem: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var shortName: String
    public var city: String?
    public var county: String?
    public var state: String?
    public var country: String?
    public var status: String?
    public var active: Bool
    public var listenerCount: Int?
    public var clientCount: Int?
    public var lastActiveAt: Date?
    public var coordinate: GuidanceCoordinate?

    public init(
        id: String,
        name: String,
        shortName: String,
        city: String? = nil,
        county: String? = nil,
        state: String? = nil,
        country: String? = nil,
        status: String? = nil,
        active: Bool = true,
        listenerCount: Int? = nil,
        clientCount: Int? = nil,
        lastActiveAt: Date? = nil,
        coordinate: GuidanceCoordinate? = nil
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.city = city
        self.county = county
        self.state = state
        self.country = country
        self.status = status
        self.active = active
        self.listenerCount = listenerCount
        self.clientCount = clientCount
        self.lastActiveAt = lastActiveAt
        self.coordinate = coordinate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let shortName = container.flexibleString(for: "shortName", "short_name", "short", "system", "systemShortName") ?? ""
        let name = container.flexibleString(for: "name", "description", "label", "title") ?? shortName
        let status = container.flexibleString(for: "status", "state")
        let active = container.flexibleBool(for: "active", "enabled", "isActive")
            ?? ScannerSystem.activeDefault(from: status)
        let coordinate = ScannerSystem.decodeCoordinate(from: container)

        self.init(
            id: container.flexibleString(for: "id", "_id", "uuid") ?? shortName.scannerNonEmpty ?? name,
            name: name.scannerNonEmpty ?? shortName.scannerNonEmpty ?? "Scanner System",
            shortName: shortName.scannerNonEmpty ?? name.normalizedScannerIdentifier,
            city: container.flexibleString(for: "city", "locality"),
            county: container.flexibleString(for: "county"),
            state: container.flexibleString(for: "state", "region", "province"),
            country: container.flexibleString(for: "country") ?? "US",
            status: status,
            active: active,
            listenerCount: container.flexibleInt(for: "listenerCount", "listeners", "listener_count"),
            clientCount: container.flexibleInt(for: "clientCount", "clients", "client_count"),
            lastActiveAt: container.flexibleDate(for: "lastActive", "last_active", "lastActiveAt", "lastCall", "lastCallAt"),
            coordinate: coordinate
        )
    }

    public var isAvailable: Bool {
        guard active else { return false }
        let normalizedStatus = status?.lowercased() ?? ""
        return !normalizedStatus.contains("offline")
            && !normalizedStatus.contains("inactive")
            && !normalizedStatus.contains("disabled")
    }

    public var locationText: String {
        [city, county, state, country]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).scannerNonEmpty }
            .joined(separator: ", ")
    }

    public func distanceMiles(from coordinate: GuidanceCoordinate) -> Double? {
        guard let systemCoordinate = self.coordinate else { return nil }
        return systemCoordinate.location.distance(from: coordinate.location) / 1_609.344
    }

    public func withCoordinate(_ coordinate: GuidanceCoordinate?) -> ScannerSystem {
        var copy = self
        copy.coordinate = coordinate
        return copy
    }

    private static func activeDefault(from status: String?) -> Bool {
        guard let status = status?.lowercased() else { return true }
        return !status.contains("offline")
            && !status.contains("inactive")
            && !status.contains("disabled")
    }

    private static func decodeCoordinate(from container: KeyedDecodingContainer<DynamicCodingKey>) -> GuidanceCoordinate? {
        if let latitude = container.flexibleDouble(for: "latitude", "lat"),
           let longitude = container.flexibleDouble(for: "longitude", "lon", "lng") {
            return GuidanceCoordinate(latitude: latitude, longitude: longitude)
        }

        if let nested = try? container.decodeIfPresent(ScannerCoordinatePayload.self, forKey: DynamicCodingKey("coordinate")) {
            return nested.coordinate
        }

        if let nested = try? container.decodeIfPresent(ScannerCoordinatePayload.self, forKey: DynamicCodingKey("location")) {
            return nested.coordinate
        }

        return nil
    }
}

public struct ScannerCall: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var systemShortName: String
    public var talkgroup: Int?
    public var talkgroupLabel: String?
    public var timestamp: Date?
    public var duration: TimeInterval?
    public var audioURL: URL?
    public var metadataDisplayText: String?
    public var source: String?
    public var frequency: String?
    public var channel: String?

    public init(
        id: String,
        systemShortName: String,
        talkgroup: Int? = nil,
        talkgroupLabel: String? = nil,
        timestamp: Date? = nil,
        duration: TimeInterval? = nil,
        audioURL: URL? = nil,
        metadataDisplayText: String? = nil,
        source: String? = nil,
        frequency: String? = nil,
        channel: String? = nil
    ) {
        self.id = id
        self.systemShortName = systemShortName
        self.talkgroup = talkgroup
        self.talkgroupLabel = talkgroupLabel
        self.timestamp = timestamp
        self.duration = duration
        self.audioURL = audioURL
        self.metadataDisplayText = metadataDisplayText
        self.source = source
        self.frequency = frequency
        self.channel = channel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let systemShortName = container.flexibleString(for: "systemShortName", "system", "shortName", "short_name") ?? ""
        let timestamp = container.flexibleDate(for: "timestamp", "time", "date", "createdAt", "startTime")
        let talkgroup = container.flexibleInt(for: "talkgroup", "talkgroupNum", "talkgroupNumber", "tg", "decimal")
        let audioString = container.flexibleString(
            for: "audioURL",
            "audioUrl",
            "mediaURL",
            "mediaUrl",
            "streamURL",
            "streamUrl",
            "url",
            "mp3",
            "callURL",
            "filename"
        )

        self.init(
            id: container.flexibleString(for: "id", "_id", "uuid", "callId")
                ?? [systemShortName, talkgroup.map(String.init), timestamp.map { String(Int($0.timeIntervalSince1970)) }]
                    .compactMap { $0 }
                    .joined(separator: "-")
                    .scannerNonEmpty
                ?? UUID().uuidString,
            systemShortName: systemShortName,
            talkgroup: talkgroup,
            talkgroupLabel: container.flexibleString(for: "talkgroupLabel", "talkgroup_label", "alphaTag", "alpha_tag", "name", "label"),
            timestamp: timestamp,
            duration: container.flexibleDouble(for: "duration", "durationSeconds", "length", "seconds", "len"),
            audioURL: Self.makeAudioURL(from: audioString),
            metadataDisplayText: container.flexibleString(for: "metadata", "metadataDisplayText", "display", "text", "description"),
            source: container.flexibleString(for: "source", "provider"),
            frequency: container.flexibleString(for: "frequency", "freq"),
            channel: container.flexibleString(for: "channel")
        )
    }

    public var displayTitle: String {
        talkgroupLabel?.trimmingCharacters(in: .whitespacesAndNewlines).scannerNonEmpty
            ?? talkgroup.map { "Talkgroup \($0)" }
            ?? "Scanner Call"
    }

    public func resolvedAudioURL(relativeTo baseURL: URL?) -> URL? {
        guard let audioURL else { return nil }
        guard audioURL.scheme == nil, let baseURL else { return audioURL.absoluteURL }
        return URL(string: audioURL.relativeString, relativeTo: baseURL)?.absoluteURL
    }

    private static func makeAudioURL(from string: String?) -> URL? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmed) {
            return url
        }

        return trimmed
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            .flatMap(URL.init(string:))
    }
}

public struct ScannerTalkgroup: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var systemShortName: String
    public var decimal: Int?
    public var alphaTag: String?
    public var description: String?
    public var category: String?

    public init(
        id: String,
        systemShortName: String,
        decimal: Int? = nil,
        alphaTag: String? = nil,
        description: String? = nil,
        category: String? = nil
    ) {
        self.id = id
        self.systemShortName = systemShortName
        self.decimal = decimal
        self.alphaTag = alphaTag
        self.description = description
        self.category = category
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let systemShortName = container.flexibleString(for: "systemShortName", "system", "shortName", "short_name") ?? ""
        let decimal = container.flexibleInt(for: "decimal", "talkgroup", "talkgroupNum", "tg")
        let alphaTag = container.flexibleString(for: "alphaTag", "alpha_tag", "name", "label")

        self.init(
            id: container.flexibleString(for: "id", "_id", "uuid")
                ?? [systemShortName, decimal.map(String.init), alphaTag]
                    .compactMap { $0 }
                    .joined(separator: "-")
                    .scannerNonEmpty
                ?? UUID().uuidString,
            systemShortName: systemShortName,
            decimal: decimal,
            alphaTag: alphaTag,
            description: container.flexibleString(for: "description", "desc"),
            category: container.flexibleString(for: "category", "tag")
        )
    }
}

public enum ScannerSystemListMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case nearby
    case browse

    public var id: String { rawValue }
}

public enum ScannerSystemFilters {
    public static func activeSystems(_ systems: [ScannerSystem]) -> [ScannerSystem] {
        systems.filter(\.isAvailable)
    }

    public static func search(_ systems: [ScannerSystem], query: String) -> [ScannerSystem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return systems }

        return systems.filter { system in
            [
                system.name,
                system.shortName,
                system.city,
                system.county,
                system.state
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(normalizedQuery) }
        }
    }
}

public enum ScannerNearbySorter {
    public static func sortedSystems(_ systems: [ScannerSystem], from userCoordinate: GuidanceCoordinate?) -> [ScannerSystem] {
        guard let userCoordinate else { return [] }

        return ScannerSystemFilters.activeSystems(systems)
            .filter { $0.coordinate != nil }
            .sorted {
                ($0.distanceMiles(from: userCoordinate) ?? .greatestFiniteMagnitude)
                    < ($1.distanceMiles(from: userCoordinate) ?? .greatestFiniteMagnitude)
            }
    }
}

public enum ScannerNearbyModeResolver {
    public static func resolvedMode(requested: ScannerSystemListMode, userCoordinate: GuidanceCoordinate?) -> ScannerSystemListMode {
        requested == .nearby && userCoordinate == nil ? .browse : requested
    }
}

public final class ScannerGeocodeCache {
    private struct CachedCoordinate: Codable {
        var latitude: Double
        var longitude: Double
    }

    private let userDefaults: UserDefaults
    private let storageKey: String

    public init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "timethrottle.scanner.geocodeCache"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    public func coordinate(for system: ScannerSystem) -> GuidanceCoordinate? {
        if let coordinate = system.coordinate {
            return coordinate
        }

        guard let cached = storedCoordinates()[Self.cacheKey(for: system)] else { return nil }
        return GuidanceCoordinate(latitude: cached.latitude, longitude: cached.longitude)
    }

    public func store(_ coordinate: GuidanceCoordinate, for system: ScannerSystem) {
        var coordinates = storedCoordinates()
        coordinates[Self.cacheKey(for: system)] = CachedCoordinate(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        guard let data = try? JSONEncoder().encode(coordinates) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    public static func cacheKey(for system: ScannerSystem) -> String {
        [
            system.shortName,
            system.city,
            system.county,
            system.state,
            system.country
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().scannerNonEmpty }
        .joined(separator: "|")
    }

    private func storedCoordinates() -> [String: CachedCoordinate] {
        guard let data = userDefaults.data(forKey: storageKey),
              let coordinates = try? JSONDecoder().decode([String: CachedCoordinate].self, from: data) else {
            return [:]
        }
        return coordinates
    }
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private struct ScannerCoordinatePayload: Decodable {
    var coordinate: GuidanceCoordinate?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        if let latitude = container.flexibleDouble(for: "latitude", "lat"),
           let longitude = container.flexibleDouble(for: "longitude", "lon", "lng") {
            coordinate = GuidanceCoordinate(latitude: latitude, longitude: longitude)
        } else {
            coordinate = nil
        }
    }
}

extension KeyedDecodingContainer where K == DynamicCodingKey {
    func flexibleString(for keys: String...) -> String? {
        for key in keys {
            let codingKey = DynamicCodingKey(key)
            if let value = try? decodeIfPresent(String.self, forKey: codingKey) {
                return value.trimmingCharacters(in: .whitespacesAndNewlines).scannerNonEmpty
            }
            if let value = try? decodeIfPresent(Int.self, forKey: codingKey) {
                return String(value)
            }
            if let value = try? decodeIfPresent(Double.self, forKey: codingKey) {
                return String(value)
            }
        }
        return nil
    }

    func flexibleInt(for keys: String...) -> Int? {
        for key in keys {
            let codingKey = DynamicCodingKey(key)
            if let value = try? decodeIfPresent(Int.self, forKey: codingKey) {
                return value
            }
            if let value = try? decodeIfPresent(Double.self, forKey: codingKey) {
                return Int(value.rounded())
            }
            if let value = try? decodeIfPresent(String.self, forKey: codingKey) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let intValue = Int(trimmed) {
                    return intValue
                }
                if let doubleValue = Double(trimmed) {
                    return Int(doubleValue.rounded())
                }
            }
        }
        return nil
    }

    func flexibleDouble(for keys: String...) -> Double? {
        for key in keys {
            let codingKey = DynamicCodingKey(key)
            if let value = try? decodeIfPresent(Double.self, forKey: codingKey) {
                return value
            }
            if let value = try? decodeIfPresent(Int.self, forKey: codingKey) {
                return Double(value)
            }
            if let value = try? decodeIfPresent(String.self, forKey: codingKey),
               let doubleValue = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return doubleValue
            }
        }
        return nil
    }

    func flexibleBool(for keys: String...) -> Bool? {
        for key in keys {
            let codingKey = DynamicCodingKey(key)
            if let value = try? decodeIfPresent(Bool.self, forKey: codingKey) {
                return value
            }
            if let value = try? decodeIfPresent(Int.self, forKey: codingKey) {
                return value != 0
            }
            if let value = try? decodeIfPresent(String.self, forKey: codingKey) {
                switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "yes", "active", "online", "1":
                    return true
                case "false", "no", "inactive", "offline", "disabled", "0":
                    return false
                default:
                    break
                }
            }
        }
        return nil
    }

    func flexibleDate(for keys: String...) -> Date? {
        for key in keys {
            let codingKey = DynamicCodingKey(key)
            if let value = try? decodeIfPresent(Date.self, forKey: codingKey) {
                return value
            }
            if let value = try? decodeIfPresent(Double.self, forKey: codingKey) {
                return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1_000 : value)
            }
            if let value = try? decodeIfPresent(Int.self, forKey: codingKey) {
                let seconds = Double(value)
                return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
            }
            if let value = try? decodeIfPresent(String.self, forKey: codingKey) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if let number = Double(trimmed) {
                    return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1_000 : number)
                }
                if let date = ScannerDateParser.date(from: trimmed) {
                    return date
                }
            }
        }
        return nil
    }
}

enum ScannerDateParser {
    static func date(from string: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        return ISO8601DateFormatter().date(from: string)
    }
}

extension String {
    var scannerNonEmpty: String? {
        isEmpty ? nil : self
    }

    var normalizedScannerIdentifier: String {
        lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
