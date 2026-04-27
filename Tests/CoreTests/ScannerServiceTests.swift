import XCTest
@testable import TimeThrottleCore

private actor RequestedURLStore {
    private(set) var url: URL?

    func set(_ url: URL?) {
        self.url = url
    }
}

final class ScannerServiceTests: XCTestCase {
    func testScannerSystemDecodingSupportsFlexibleOpenMHzShape() throws {
        let data = """
        {
          "id": 42,
          "name": "Chicago Public Safety",
          "shortName": "chi",
          "city": "Chicago",
          "county": "Cook",
          "state": "IL",
          "country": "US",
          "status": "online",
          "active": true,
          "listeners": "18",
          "lastActive": "2026-04-26T12:34:56Z",
          "location": { "lat": 41.8781, "lon": -87.6298 }
        }
        """.data(using: .utf8)!

        let system = try JSONDecoder().decode(ScannerSystem.self, from: data)

        XCTAssertEqual(system.id, "42")
        XCTAssertEqual(system.shortName, "chi")
        XCTAssertEqual(system.city, "Chicago")
        XCTAssertEqual(system.listenerCount, 18)
        XCTAssertTrue(system.isAvailable)
        XCTAssertEqual(system.coordinate?.latitude ?? 0, 41.8781, accuracy: 0.0001)
    }

    func testScannerCallDecodingSupportsLatestCallFixtureAndAudioResolution() throws {
        let data = """
        {
          "id": "call-1",
          "system": "chi",
          "talkgroup": "1234",
          "alphaTag": "Dispatch",
          "time": 1777200000,
          "duration": "12.5",
          "url": "/chi/call-1.mp3",
          "metadata": "Public feed metadata",
          "source": "OpenMHz"
        }
        """.data(using: .utf8)!

        let call = try JSONDecoder().decode(ScannerCall.self, from: data)
        let resolvedURL = call.resolvedAudioURL(relativeTo: URL(string: "https://api.openmhz.com")!)

        XCTAssertEqual(call.systemShortName, "chi")
        XCTAssertEqual(call.talkgroup, 1234)
        XCTAssertEqual(call.talkgroupLabel, "Dispatch")
        XCTAssertEqual(call.duration ?? 0, 12.5, accuracy: 0.0001)
        XCTAssertEqual(resolvedURL?.absoluteString, "https://api.openmhz.com/chi/call-1.mp3")
    }

    func testScannerTalkgroupDecodingSupportsFixture() throws {
        let data = """
        {
          "systemShortName": "chi",
          "decimal": "5678",
          "alpha_tag": "Operations",
          "description": "Operations talkgroup",
          "category": "Public Safety"
        }
        """.data(using: .utf8)!

        let talkgroup = try JSONDecoder().decode(ScannerTalkgroup.self, from: data)

        XCTAssertEqual(talkgroup.systemShortName, "chi")
        XCTAssertEqual(talkgroup.decimal, 5678)
        XCTAssertEqual(talkgroup.alphaTag, "Operations")
        XCTAssertEqual(talkgroup.category, "Public Safety")
    }

    func testSystemsListDecodingSupportsArrayEnvelope() throws {
        let data = """
        {
          "systems": [
            { "name": "Chicago", "shortName": "chi", "active": true },
            { "name": "Offline", "shortName": "off", "status": "offline" }
          ]
        }
        """.data(using: .utf8)!

        let systems = try OpenMHzScannerService.decodeArray(ScannerSystem.self, from: data)

        XCTAssertEqual(systems.count, 2)
        XCTAssertEqual(ScannerSystemFilters.activeSystems(systems).map(\.shortName), ["chi"])
    }

    func testLatestCallsDecodingSupportsCallsEnvelope() throws {
        let data = """
        {
          "calls": [
            { "_id": "one", "system": "chi", "talkgroupNum": 100, "url": "https://example.com/one.mp3", "len": 7 }
          ]
        }
        """.data(using: .utf8)!

        let calls = try OpenMHzScannerService.decodeArray(ScannerCall.self, from: data)

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.id, "one")
        XCTAssertEqual(calls.first?.talkgroup, 100)
        XCTAssertEqual(calls.first?.duration, 7)
        XCTAssertEqual(calls.first?.resolvedAudioURL(relativeTo: nil)?.absoluteString, "https://example.com/one.mp3")
    }

    func testTalkgroupsDecodingSupportsTalkgroupsEnvelope() throws {
        let data = """
        {
          "talkgroups": [
            { "system": "chi", "tg": 100, "name": "Dispatch" }
          ]
        }
        """.data(using: .utf8)!

        let talkgroups = try OpenMHzScannerService.decodeArray(ScannerTalkgroup.self, from: data)

        XCTAssertEqual(talkgroups.count, 1)
        XCTAssertEqual(talkgroups.first?.decimal, 100)
    }

    func testNearbySortingUsesDistanceAndIgnoresInactiveSystems() {
        let user = GuidanceCoordinate(latitude: 41.88, longitude: -87.63)
        let systems = [
            ScannerSystem(
                id: "far",
                name: "Far",
                shortName: "far",
                active: true,
                coordinate: GuidanceCoordinate(latitude: 42.50, longitude: -88.00)
            ),
            ScannerSystem(
                id: "near",
                name: "Near",
                shortName: "near",
                active: true,
                coordinate: GuidanceCoordinate(latitude: 41.89, longitude: -87.64)
            ),
            ScannerSystem(
                id: "offline",
                name: "Offline",
                shortName: "offline",
                status: "offline",
                active: false,
                coordinate: GuidanceCoordinate(latitude: 41.88, longitude: -87.63)
            )
        ]

        let sorted = ScannerNearbySorter.sortedSystems(systems, from: user)

        XCTAssertEqual(sorted.map(\.shortName), ["near", "far"])
    }

    func testNoLocationFallsBackToBrowseMode() {
        XCTAssertEqual(
            ScannerNearbyModeResolver.resolvedMode(requested: .nearby, userCoordinate: nil),
            .browse
        )
        XCTAssertEqual(
            ScannerNearbyModeResolver.resolvedMode(requested: .nearby, userCoordinate: GuidanceCoordinate(latitude: 1, longitude: 2)),
            .nearby
        )
    }

    func testEmptySystemsStateAndInactiveFilteringAreDeterministic() {
        XCTAssertTrue(ScannerSystemFilters.activeSystems([]).isEmpty)

        let systems = [
            ScannerSystem(id: "offline", name: "Offline", shortName: "offline", status: "offline", active: true),
            ScannerSystem(id: "inactive", name: "Inactive", shortName: "inactive", status: "inactive", active: true),
            ScannerSystem(id: "active", name: "Active", shortName: "active", status: "online", active: true)
        ]

        XCTAssertEqual(ScannerSystemFilters.activeSystems(systems).map(\.shortName), ["active"])
    }

    func testGeocodeCacheReusesStoredCoordinate() {
        let suiteName = "ScannerServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cache = ScannerGeocodeCache(userDefaults: defaults, storageKey: "cache")
        let system = ScannerSystem(
            id: "chi",
            name: "Chicago",
            shortName: "chi",
            city: "Chicago",
            county: "Cook",
            state: "IL",
            country: "US"
        )
        let coordinate = GuidanceCoordinate(latitude: 41.8781, longitude: -87.6298)

        cache.store(coordinate, for: system)
        let reused = cache.coordinate(for: system)

        XCTAssertEqual(reused?.latitude ?? 0, 41.8781, accuracy: 0.0001)
        XCTAssertEqual(reused?.longitude ?? 0, -87.6298, accuracy: 0.0001)
    }

    func testOpenMHzServiceBuildsRequestsWithConfigurableBaseURL() async throws {
        let systemsData = """
        [{ "name": "Chicago", "shortName": "chi", "active": true }]
        """.data(using: .utf8)!
        let requestedURLStore = RequestedURLStore()
        let service = OpenMHzScannerService(baseURL: URL(string: "https://scanner.example.test/base")!) { request in
            await requestedURLStore.set(request.url)
            return (systemsData, HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!)
        }

        let systems = try await service.fetchSystems()
        let requestedURL = await requestedURLStore.url

        XCTAssertEqual(requestedURL?.absoluteString, "https://scanner.example.test/base/systems")
        XCTAssertEqual(systems.first?.shortName, "chi")
    }

    func testOpenMHzServiceBuildsRecentCallsEndpointWithSystemShortName() async throws {
        let callsData = """
        { "calls": [{ "_id": "one", "system": "chi", "talkgroupNum": 100, "url": "https://example.com/one.mp3" }] }
        """.data(using: .utf8)!
        let requestedURLStore = RequestedURLStore()
        let service = OpenMHzScannerService(baseURL: URL(string: "https://scanner.example.test/base")!) { request in
            await requestedURLStore.set(request.url)
            return (callsData, HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!)
        }

        let calls = try await service.fetchLatestCalls(for: " CHI ")
        let requestedURL = await requestedURLStore.url

        XCTAssertEqual(requestedURL?.absoluteString, "https://scanner.example.test/base/chi/calls")
        XCTAssertEqual(calls.first?.id, "one")
    }

    func testScannerLiveStreamCatalogDecodesValidJSON() throws {
        let data = """
        {
          "streams": [
            {
              "systemShortName": "chi",
              "aliases": ["CHI_CPD", "SC21102"],
              "displayName": "Chicago Live Feed",
              "providerLabel": "Approved public stream",
              "streamURL": "https://example.com/live.m3u8",
              "streamType": "hls",
              "notes": "Configured with permission from provider.",
              "isEnabled": true
            }
          ]
        }
        """.data(using: .utf8)!

        let catalog = try ScannerLiveStreamCatalog.decode(from: data)
        let stream = try XCTUnwrap(catalog.streams.first)

        XCTAssertEqual(stream.systemShortName, "chi")
        XCTAssertEqual(stream.aliases, ["CHI_CPD", "SC21102"])
        XCTAssertEqual(stream.streamURL.absoluteString, "https://example.com/live.m3u8")
        XCTAssertEqual(stream.streamType, .hls)
        XCTAssertTrue(stream.isEnabled)
    }

    func testScannerLiveStreamCatalogAllowsEmptyConfig() throws {
        let data = """
        { "streams": [] }
        """.data(using: .utf8)!

        let catalog = try ScannerLiveStreamCatalog.decode(from: data)

        XCTAssertTrue(catalog.streams.isEmpty)
    }

    func testScannerLiveStreamResolverReturnsNilForMissingSystem() {
        let resolver = ScannerLiveStreamResolver(catalog: ScannerLiveStreamCatalog(streams: [
            liveStream(systemShortName: "chi")
        ]))
        let system = ScannerSystem(id: "la", name: "Los Angeles", shortName: "la")

        XCTAssertNil(resolver.liveStream(for: system))
    }

    func testScannerLiveStreamResolverMatchesAliases() throws {
        let stream = liveStream(systemShortName: "chi", aliases: ["CHI_CPD", "SC21102"])
        let resolver = ScannerLiveStreamResolver(catalog: ScannerLiveStreamCatalog(streams: [stream]))
        let system = ScannerSystem(id: "sc21102", name: "Chicago Alternate", shortName: "SC21102")

        XCTAssertEqual(resolver.liveStream(for: system)?.id, stream.id)
    }

    func testScannerLiveStreamResolverRejectsUnsupportedURLScheme() {
        let stream = liveStream(
            systemShortName: "chi",
            streamURL: URL(string: "ftp://example.com/live.mp3")!,
            streamType: .mp3
        )
        let resolver = ScannerLiveStreamResolver(catalog: ScannerLiveStreamCatalog(streams: [stream]))
        let system = ScannerSystem(id: "chi", name: "Chicago", shortName: "chi")

        XCTAssertFalse(resolver.isValid(stream))
        XCTAssertNil(resolver.liveStream(for: system))
    }

    func testScannerLiveStreamResolverRejectsUnsupportedStreamType() {
        let stream = liveStream(
            systemShortName: "chi",
            streamURL: URL(string: "https://example.com/live.bin")!,
            streamType: .unsupported
        )
        let resolver = ScannerLiveStreamResolver(catalog: ScannerLiveStreamCatalog(streams: [stream]))
        let system = ScannerSystem(id: "chi", name: "Chicago", shortName: "chi")

        XCTAssertFalse(resolver.isValid(stream))
        XCTAssertNil(resolver.liveStream(for: system))
    }

    func testScannerLiveStreamResolverAcceptsHTTPSStream() throws {
        let stream = liveStream(systemShortName: "chi", streamURL: URL(string: "https://example.com/live.mp3")!, streamType: .mp3)
        let resolver = ScannerLiveStreamResolver(catalog: ScannerLiveStreamCatalog(streams: [stream]))
        let system = ScannerSystem(id: "chi", name: "Chicago", shortName: "chi")

        XCTAssertTrue(resolver.isValid(stream))
        XCTAssertEqual(resolver.liveStream(for: system)?.id, stream.id)
    }

    func testScannerLiveStreamResolverRejectsHTTPByDefault() {
        let stream = liveStream(systemShortName: "chi", streamURL: URL(string: "http://example.com/live.mp3")!, streamType: .mp3)
        let resolver = ScannerLiveStreamResolver(catalog: ScannerLiveStreamCatalog(streams: [stream]))
        let system = ScannerSystem(id: "chi", name: "Chicago", shortName: "chi")

        XCTAssertFalse(resolver.isValid(stream))
        XCTAssertNil(resolver.liveStream(for: system))
    }

    func testScannerLiveStreamResolverReturnsConfiguredStreamForSelectedSystem() throws {
        let stream = liveStream(systemShortName: "chi")
        let resolver = ScannerLiveStreamResolver(catalog: ScannerLiveStreamCatalog(streams: [stream]))
        let system = ScannerSystem(id: "chi", name: "Chicago", shortName: "chi")

        XCTAssertEqual(resolver.liveStream(for: system)?.displayName, "Test Live Feed")
    }

    func testScannerPlaybackModeSwitchesLiveToCallReplay() {
        let stream = liveStream(systemShortName: "chi")
        let call = ScannerCall(id: "call-1", systemShortName: "chi", audioURL: URL(string: "https://example.com/call.mp3"))
        var mode = ScannerPlaybackMode.liveStream(stream)

        mode = .callReplay(call)

        XCTAssertNil(mode.liveStream)
        XCTAssertEqual(mode.callReplay?.id, "call-1")
    }

    func testScannerPlaybackModeSwitchesCallReplayToLive() {
        let stream = liveStream(systemShortName: "chi")
        let call = ScannerCall(id: "call-1", systemShortName: "chi", audioURL: URL(string: "https://example.com/call.mp3"))
        var mode = ScannerPlaybackMode.callReplay(call)

        mode = .liveStream(stream)

        XCTAssertEqual(mode.liveStream?.id, stream.id)
        XCTAssertNil(mode.callReplay)
    }

    private func liveStream(
        systemShortName: String,
        aliases: [String] = [],
        streamURL: URL = URL(string: "https://example.com/live.m3u8")!,
        streamType: ScannerLiveStreamType = .hls,
        isEnabled: Bool = true
    ) -> ScannerLiveStream {
        ScannerLiveStream(
            systemShortName: systemShortName,
            aliases: aliases,
            displayName: "Test Live Feed",
            providerLabel: "Approved public stream",
            streamURL: streamURL,
            streamType: streamType,
            notes: "Configured with permission from provider.",
            isEnabled: isEnabled
        )
    }
}
