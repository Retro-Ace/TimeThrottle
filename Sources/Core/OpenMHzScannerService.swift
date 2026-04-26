import Foundation
#if canImport(OSLog)
import OSLog
#endif

public struct ScannerSystemSnapshot: Equatable, Sendable {
    public var systemShortName: String
    public var latestCalls: [ScannerCall]
    public var talkgroups: [ScannerTalkgroup]
    public var refreshedAt: Date

    public init(
        systemShortName: String,
        latestCalls: [ScannerCall],
        talkgroups: [ScannerTalkgroup],
        refreshedAt: Date = Date()
    ) {
        self.systemShortName = systemShortName
        self.latestCalls = latestCalls
        self.talkgroups = talkgroups
        self.refreshedAt = refreshedAt
    }
}

public enum ScannerServiceError: Error, Equatable, LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case httpStatus(Int)
    case decodeFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Scanner endpoint is not configured correctly."
        case .invalidResponse:
            return "Scanner provider returned an unreadable response."
        case .httpStatus(let statusCode):
            return "Scanner provider returned HTTP \(statusCode)."
        case .decodeFailure(let message):
            return message
        }
    }
}

public final class OpenMHzScannerService: @unchecked Sendable {
    public typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public let baseURL: URL
    private let timeout: TimeInterval
    private let dataLoader: DataLoader
    private let decoder: JSONDecoder

    public init(
        baseURL: URL = URL(string: "https://api.openmhz.com")!,
        timeout: TimeInterval = 12,
        dataLoader: @escaping DataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.dataLoader = dataLoader
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
            }
            let string = try container.decode(String.self)
            if let number = Double(string) {
                return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1_000 : number)
            }
            if let date = ScannerDateParser.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported scanner date")
        }
        self.decoder = decoder
    }

    public func fetchSystems() async throws -> [ScannerSystem] {
        try await fetchArray(endpoint: ["systems"])
    }

    public func fetchLatestCalls(for systemShortName: String) async throws -> [ScannerCall] {
        try await fetchArray(endpoint: [Self.endpointSystemIdentifier(systemShortName), "calls"])
    }

    public func fetchTalkgroups(for systemShortName: String) async throws -> [ScannerTalkgroup] {
        try await fetchArray(endpoint: [Self.endpointSystemIdentifier(systemShortName), "talkgroups"])
    }

    public func refreshSelectedSystem(shortName: String) async throws -> ScannerSystemSnapshot {
        async let calls = fetchLatestCalls(for: shortName)
        async let talkgroups = fetchTalkgroups(for: shortName)
        return try await ScannerSystemSnapshot(
            systemShortName: shortName,
            latestCalls: calls,
            talkgroups: talkgroups
        )
    }

    private func fetchArray<Element: Decodable>(endpoint pathComponents: [String]) async throws -> [Element] {
        let data = try await fetchData(endpoint: pathComponents)
        do {
            let decoded = try Self.decodeArray(Element.self, from: data, decoder: decoder)
            Self.logDecodeSuccess(endpoint: pathComponents, count: decoded.count)
            return decoded
        } catch {
            Self.logDecodeFailure(endpoint: pathComponents, error: error, data: data)
            throw ScannerServiceError.decodeFailure("Scanner provider response could not be decoded for \(pathComponents.joined(separator: "/")).")
        }
    }

    private func fetchData(endpoint pathComponents: [String]) async throws -> Data {
        let url = try endpointURL(pathComponents)
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        Self.logRequest(url: url)
        let (data, response) = try await dataLoader(request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            Self.logHTTPFailure(url: url, statusCode: httpResponse.statusCode)
            throw ScannerServiceError.httpStatus(httpResponse.statusCode)
        }
        if let httpResponse = response as? HTTPURLResponse {
            Self.logHTTPSuccess(url: url, statusCode: httpResponse.statusCode, byteCount: data.count)
        }
        return data
    }

    private func endpointURL(_ pathComponents: [String]) throws -> URL {
        var url = baseURL
        for component in pathComponents {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ScannerServiceError.invalidEndpoint }
            url.appendPathComponent(trimmed)
        }
        return url
    }

    private static func endpointSystemIdentifier(_ systemShortName: String) -> String {
        systemShortName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func logRequest(url: URL) {
        #if canImport(OSLog)
        logger.debug("Scanner request endpoint=\(url.absoluteString, privacy: .public)")
        #endif
    }

    private static func logHTTPSuccess(url: URL, statusCode: Int, byteCount: Int) {
        #if canImport(OSLog)
        logger.debug(
            "Scanner response endpoint=\(url.absoluteString, privacy: .public) status=\(statusCode, privacy: .public) bytes=\(byteCount, privacy: .public)"
        )
        #endif
    }

    private static func logHTTPFailure(url: URL, statusCode: Int) {
        #if canImport(OSLog)
        logger.error(
            "Scanner HTTP failure endpoint=\(url.absoluteString, privacy: .public) status=\(statusCode, privacy: .public)"
        )
        #endif
    }

    private static func logDecodeSuccess(endpoint: [String], count: Int) {
        #if canImport(OSLog)
        logger.debug(
            "Scanner decoded endpoint=\(endpoint.joined(separator: "/"), privacy: .public) count=\(count, privacy: .public)"
        )
        #endif
    }

    private static func logDecodeFailure(endpoint: [String], error: Error, data: Data) {
        #if canImport(OSLog)
        let preview = String(data: data.prefix(240), encoding: .utf8) ?? "<binary>"
        logger.error(
            "Scanner decode failure endpoint=\(endpoint.joined(separator: "/"), privacy: .public) error=\(error.localizedDescription, privacy: .public) preview=\(preview, privacy: .private)"
        )
        #endif
    }

    #if canImport(OSLog)
    private static let logger = Logger(subsystem: "com.timethrottle.app", category: "Scanner")
    #endif

    public static func decodeArray<Element: Decodable>(
        _ type: Element.Type,
        from data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> [Element] {
        if let array = try? decoder.decode([Element].self, from: data) {
            return array
        }

        return try decoder.decode(ScannerArrayEnvelope<Element>.self, from: data).items
    }
}

private struct ScannerArrayEnvelope<Element: Decodable>: Decodable {
    var items: [Element]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        for key in ["systems", "calls", "talkgroups", "data", "results", "items"] {
            if let values = try? container.decodeIfPresent([Element].self, forKey: DynamicCodingKey(key)) {
                items = values
                return
            }
        }

        throw ScannerServiceError.invalidResponse
    }
}
