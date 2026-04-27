import Foundation

public enum ScannerLiveStreamType: String, Codable, CaseIterable, Equatable, Sendable {
    case hls
    case mp3
    case aac
    case icecast
    case unknown
    case unsupported

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self = rawValue.flatMap(Self.init(rawValue:)) ?? .unknown
    }

    public var isSupported: Bool {
        switch self {
        case .hls, .mp3, .aac, .icecast:
            return true
        case .unknown, .unsupported:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .hls:
            return "HLS"
        case .mp3:
            return "MP3"
        case .aac:
            return "AAC"
        case .icecast:
            return "Icecast"
        case .unknown:
            return "Unknown"
        case .unsupported:
            return "Unsupported"
        }
    }
}

public struct ScannerLiveStream: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var systemShortName: String
    public var aliases: [String]
    public var displayName: String
    public var providerLabel: String
    public var streamURL: URL
    public var streamType: ScannerLiveStreamType
    public var notes: String?
    public var isEnabled: Bool

    public init(
        id: String? = nil,
        systemShortName: String,
        aliases: [String] = [],
        displayName: String,
        providerLabel: String,
        streamURL: URL,
        streamType: ScannerLiveStreamType,
        notes: String? = nil,
        isEnabled: Bool = true
    ) {
        self.systemShortName = systemShortName
        self.aliases = aliases
        self.displayName = displayName
        self.providerLabel = providerLabel
        self.streamURL = streamURL
        self.streamType = streamType
        self.notes = notes
        self.isEnabled = isEnabled
        self.id = id ?? [
            systemShortName,
            displayName,
            streamURL.absoluteString
        ]
        .map { ScannerLiveStreamResolver.normalizedIdentifier($0) }
        .joined(separator: "|")
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let systemShortName = try container.decode(String.self, forKey: .systemShortName)
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "Live Feed"
        let providerLabel = try container.decodeIfPresent(String.self, forKey: .providerLabel) ?? "Configured public stream"
        let streamURLString = try container.decodeIfPresent(String.self, forKey: .streamURL) ?? ""
        let streamURL = URL(string: streamURLString.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? URL(string: "about:invalid")!

        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            systemShortName: systemShortName,
            aliases: try container.decodeIfPresent([String].self, forKey: .aliases) ?? [],
            displayName: displayName,
            providerLabel: providerLabel,
            streamURL: streamURL,
            streamType: try container.decodeIfPresent(ScannerLiveStreamType.self, forKey: .streamType) ?? .unknown,
            notes: try container.decodeIfPresent(String.self, forKey: .notes),
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        )
    }

    public var streamTypeText: String {
        streamType.displayName
    }
}

public struct ScannerLiveStreamCatalog: Codable, Equatable, Sendable {
    public var streams: [ScannerLiveStream]

    public init(streams: [ScannerLiveStream] = []) {
        self.streams = streams
    }

    public static let empty = ScannerLiveStreamCatalog()

    public static func decode(from data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> ScannerLiveStreamCatalog {
        try decoder.decode(ScannerLiveStreamCatalog.self, from: data)
    }

    public static func bundled(
        bundle: Bundle = .main,
        resourceName: String = "ScannerLiveStreams",
        decoder: JSONDecoder = JSONDecoder()
    ) -> ScannerLiveStreamCatalog {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? decode(from: data, decoder: decoder) else {
            return .empty
        }

        return catalog
    }
}

public struct ScannerLiveStreamResolver: Equatable, Sendable {
    public var catalog: ScannerLiveStreamCatalog
    public var requiresHTTPS: Bool

    public init(
        catalog: ScannerLiveStreamCatalog,
        requiresHTTPS: Bool = true
    ) {
        self.catalog = catalog
        self.requiresHTTPS = requiresHTTPS
    }

    public func liveStream(for system: ScannerSystem) -> ScannerLiveStream? {
        catalog.streams.first { stream in
            isValid(stream) && matches(stream, system: system)
        }
    }

    public func isValid(_ stream: ScannerLiveStream) -> Bool {
        guard stream.isEnabled else { return false }
        guard !stream.systemShortName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard stream.streamType.isSupported else { return false }
        guard let scheme = stream.streamURL.scheme?.lowercased(), !scheme.isEmpty else { return false }
        guard stream.streamURL.host?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return false }

        if requiresHTTPS {
            return scheme == "https"
        }

        return scheme == "https" || scheme == "http"
    }

    public func matches(_ stream: ScannerLiveStream, system: ScannerSystem) -> Bool {
        let systemIdentifiers = [
            system.shortName,
            system.id,
            system.name
        ].map(Self.normalizedIdentifier)

        let streamIdentifiers = ([stream.systemShortName] + stream.aliases)
            .map(Self.normalizedIdentifier)

        return streamIdentifiers.contains { streamIdentifier in
            !streamIdentifier.isEmpty && systemIdentifiers.contains(streamIdentifier)
        }
    }

    public static func normalizedIdentifier(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

public enum ScannerPlaybackMode: Equatable, Sendable {
    case idle
    case liveStream(ScannerLiveStream)
    case callReplay(ScannerCall)

    public var liveStream: ScannerLiveStream? {
        if case .liveStream(let stream) = self {
            return stream
        }
        return nil
    }

    public var callReplay: ScannerCall? {
        if case .callReplay(let call) = self {
            return call
        }
        return nil
    }
}
