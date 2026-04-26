import XCTest
@testable import TimeThrottleCore

final class RouteIntelligenceFoundationTests: XCTestCase {
    @MainActor
    func testGuidanceEngineTracksProgressAndOffRouteFoundation() {
        let steps = [
            RouteManeuverStep(
                instruction: "Turn right onto Main St",
                distanceMeters: 100,
                geometry: [
                    GuidanceCoordinate(latitude: 41.0, longitude: -87.0),
                    GuidanceCoordinate(latitude: 41.0005, longitude: -87.0)
                ],
                transportType: .automobile
            ),
            RouteManeuverStep(
                instruction: "Continue on I-90",
                distanceMeters: 900,
                geometry: [
                    GuidanceCoordinate(latitude: 41.0005, longitude: -87.0),
                    GuidanceCoordinate(latitude: 41.01, longitude: -87.0)
                ],
                transportType: .automobile
            )
        ]
        let engine = TurnByTurnGuidanceEngine(offRouteThresholdMeters: 50)
        engine.setMuted(true)
        engine.loadRoute(
            steps: steps,
            routeDistanceMeters: 1_000,
            destination: GuidanceCoordinate(latitude: 41.01, longitude: -87.0)
        )

        engine.update(progressDistanceMeters: 150)
        XCTAssertEqual(engine.state.nextInstruction, "Continue on I-90")
        XCTAssertEqual(engine.state.routeProgress, 0.15, accuracy: 0.0001)

        engine.update(currentLocation: GuidanceCoordinate(latitude: 42.0, longitude: -88.0))
        XCTAssertTrue(engine.state.isOffRoute)
        XCTAssertNotNil(engine.makeRerouteRequest(from: GuidanceCoordinate(latitude: 42.0, longitude: -88.0)))
    }

    func testWeatherRouteProviderSamplesCheckpointsByArrivalProgress() throws {
        let provider = WeatherRouteProvider()
        let startDate = Date(timeIntervalSince1970: 1_000)
        let checkpoints = try provider.checkpoints(
            for: [
                GuidanceCoordinate(latitude: 41.0, longitude: -87.0),
                GuidanceCoordinate(latitude: 41.1, longitude: -87.0),
                GuidanceCoordinate(latitude: 41.2, longitude: -87.0)
            ],
            routeDistanceMeters: 20_000,
            startDate: startDate,
            expectedTravelTimeSeconds: 3_600,
            maxCheckpointCount: 4
        )

        XCTAssertEqual(checkpoints.count, 4)
        XCTAssertEqual(checkpoints.first?.distanceFromStartMeters ?? 0, 5_000, accuracy: 0.0001)
        XCTAssertEqual(checkpoints.last?.expectedArrivalDate.timeIntervalSince(startDate) ?? 0, 3_600, accuracy: 0.0001)
    }

    func testOSMSpeedLimitParsingSupportsMilesPerHourAndMetricValues() {
        XCTAssertEqual(OSMSpeedLimitProvider.parseMaxspeedMilesPerHour("65 mph"), 65)
        XCTAssertEqual(OSMSpeedLimitProvider.parseMaxspeedMilesPerHour("100"), 62)

        let coordinate = GuidanceCoordinate(latitude: 41.0, longitude: -87.0)
        let data = """
        {
          "elements": [
            {
              "id": 123456,
              "center": { "lat": 41.0, "lon": -87.0 },
              "geometry": [
                { "lat": 41.0, "lon": -87.0 },
                { "lat": 41.001, "lon": -87.0 }
              ],
              "tags": {
                "name": "I-90",
                "maxspeed": "70 mph"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let result = OSMSpeedLimitProvider.parseSpeedLimitResult(from: data, coordinate: coordinate)
        XCTAssertEqual(result?.currentSpeedLimitMPH, 70)
        XCTAssertEqual(result?.source, "OpenStreetMap")
        XCTAssertEqual(result?.roadName, "I-90")
        XCTAssertEqual(result?.wayId, 123456)
        XCTAssertEqual(result?.confidence ?? 0, 0.95, accuracy: 0.0001)
    }

    func testOSMSpeedLimitServiceCachesWayAndCoordinateResults() async {
        let service = OSMSpeedLimitService()
        let coordinate = GuidanceCoordinate(latitude: 41.0, longitude: -87.0)
        let result = OSMSpeedLimitResult(
            currentSpeedLimitMPH: 35,
            confidence: 0.9,
            roadName: "Main St",
            wayId: 987
        )

        await service.storeCachedResult(result, for: coordinate, timestamp: Date())

        let coordinateKey = OSMSpeedLimitCacheKey.coordinateCorridor(SpeedLimitSegmentCacheKey(coordinate: coordinate))
        let wayKey = OSMSpeedLimitCacheKey.wayId(987)
        let cachedCoordinateResult = await service.cachedResult(for: coordinateKey)
        let cachedWayResult = await service.cachedResult(for: wayKey)
        XCTAssertEqual(cachedCoordinateResult, result)
        XCTAssertEqual(cachedWayResult, result)
    }

    func testOpenSkyAircraftParsingShowsInsideRadiusBelowAltitude() {
        let now = Date(timeIntervalSince1970: 2_000)
        let data = """
        {
          "states": [
            ["a1b2c3", "N123TT ", "United States", \(now.timeIntervalSince1970), \(now.timeIntervalSince1970), -87.91, 41.97, 1000, false, 100, 135, 0, null, 1010, "1234", false, 0]
          ]
        }
        """.data(using: .utf8)!

        let aircraft = OpenSkyAircraftProvider.parseAircraft(
            from: data,
            reference: GuidanceCoordinate(latitude: 41.98, longitude: -87.9),
            now: now
        )

        XCTAssertEqual(aircraft.count, 1)
        XCTAssertEqual(aircraft.first?.callsign, "N123TT")
        XCTAssertEqual(aircraft.first?.altitudeMeters, 1000)
        XCTAssertEqual(aircraft.first?.altitudeFeet ?? 0, 3280.84, accuracy: 0.01)
        XCTAssertEqual(aircraft.first?.headingDegrees, 135)
        XCTAssertNotNil(aircraft.first?.groundSpeedKnots)
        XCTAssertNotNil(aircraft.first?.groundSpeedMPH)
        XCTAssertNotNil(aircraft.first?.distanceMiles)
        XCTAssertTrue(aircraft.first?.isLowNearbyAircraft == true)
    }

    func testOpenSkyAircraftParsingFiltersOutsideRadiusAboveAltitudeAndStalePositions() {
        let now = Date(timeIntervalSince1970: 2_000)
        let data = """
        {
          "states": [
            ["outside", "FAR1 ", "United States", \(now.timeIntervalSince1970), \(now.timeIntervalSince1970), -88.50, 41.97, 1000, false, 100, 135, 0, null, 1010, "1234", false, 0],
            ["high", "HIGH1 ", "United States", \(now.timeIntervalSince1970), \(now.timeIntervalSince1970), -87.91, 41.97, 3000, false, 100, 135, 0, null, 3010, "1234", false, 0],
            ["stale", "OLD1 ", "United States", \(now.addingTimeInterval(-500).timeIntervalSince1970), \(now.addingTimeInterval(-500).timeIntervalSince1970), -87.91, 41.97, 1000, false, 100, 135, 0, null, 1010, "1234", false, 0],
            ["missing", "BAD1 ", "United States", \(now.timeIntervalSince1970), \(now.timeIntervalSince1970), null, null, 1000, false, 100, 135, 0, null, 1010, "1234", false, 0]
          ]
        }
        """.data(using: .utf8)!

        let aircraft = OpenSkyAircraftProvider.parseAircraft(
            from: data,
            reference: GuidanceCoordinate(latitude: 41.98, longitude: -87.9),
            now: now
        )

        XCTAssertTrue(aircraft.isEmpty)
    }

    func testLocalEnforcementAlertProviderFiltersByRadiusAndStaleness() async throws {
        let now = Date()
        let center = GuidanceCoordinate(latitude: 41.0, longitude: -87.0)
        let provider = LocalEnforcementAlertProvider(
            alerts: [
                EnforcementAlert(
                    id: "near-camera",
                    type: .speedCamera,
                    coordinate: GuidanceCoordinate(latitude: 41.01, longitude: -87.0),
                    source: "Local open data",
                    confidence: 0.8,
                    lastUpdated: now
                ),
                EnforcementAlert(
                    id: "far-camera",
                    type: .redLightCamera,
                    coordinate: GuidanceCoordinate(latitude: 42.0, longitude: -88.0),
                    source: "Local open data",
                    confidence: 0.8,
                    lastUpdated: now
                ),
                EnforcementAlert(
                    id: "stale-report",
                    type: .policeReported,
                    coordinate: GuidanceCoordinate(latitude: 41.01, longitude: -87.0),
                    source: "Report",
                    confidence: 0.4,
                    lastUpdated: now.addingTimeInterval(-90_000)
                )
            ]
        )

        let alerts = try await provider.enforcementAlerts(
            in: EnforcementAlertSearchRegion(center: center, radiusMiles: 5)
        )

        XCTAssertEqual(alerts.map(\.id), ["near-camera"])
        XCTAssertEqual(alerts.first?.type, .speedCamera)
        XCTAssertNotNil(alerts.first?.distanceMiles)
    }
}
