import XCTest
@testable import TimeThrottleCore

final class RouteIntelligenceFoundationTests: XCTestCase {
    @MainActor
    func testGuidanceEngineTracksProgressAndOffRouteFoundation() {
        let steps = Self.guidanceTestSteps()
        let engine = TurnByTurnGuidanceEngine(offRouteThresholdMeters: 50)
        engine.setMuted(true)
        engine.loadRoute(
            steps: steps,
            routeDistanceMeters: 1_000,
            destination: GuidanceCoordinate(latitude: 41.01, longitude: -87.0),
            routeGeometry: Self.guidanceTestRouteGeometry
        )

        engine.update(progressDistanceMeters: 150)
        XCTAssertEqual(engine.state.nextInstruction, "Continue on I-90")
        XCTAssertEqual(engine.state.routeProgress, 0.15, accuracy: 0.0001)

        engine.update(
            sample: Self.guidanceSample(
                coordinate: GuidanceCoordinate(latitude: 41.006, longitude: -87.00004)
            )
        )
        XCTAssertFalse(engine.state.isOffRoute)
        XCTAssertGreaterThan(engine.state.routeProgress, 0.45)
        XCTAssertEqual(engine.state.nextInstruction, "Continue on I-90")
    }

    @MainActor
    func testGuidanceEngineDoesNotRerouteFromOneGPSDriftPoint() {
        let engine = Self.guidanceEngineForTestRoute()

        engine.update(
            sample: Self.guidanceSample(
                coordinate: GuidanceCoordinate(latitude: 41.003, longitude: -87.0018)
            )
        )

        XCTAssertFalse(engine.state.isOffRoute)
        XCTAssertNil(engine.makeRerouteRequest(from: GuidanceCoordinate(latitude: 41.003, longitude: -87.0018)))
        XCTAssertEqual(engine.lastRouteMatchDiagnostics?.offRouteSampleCount, 1)
    }

    @MainActor
    func testGuidanceEngineConfirmsSustainedMovingOffRoute() {
        let engine = Self.guidanceEngineForTestRoute()
        let startDate = Date()
        let offRouteCoordinate = GuidanceCoordinate(latitude: 41.003, longitude: -87.0022)

        [0.0, 3.0, 6.0, 9.0].forEach { offset in
            engine.update(
                sample: Self.guidanceSample(
                    coordinate: offRouteCoordinate,
                    timestamp: startDate.addingTimeInterval(offset)
                )
            )
        }

        XCTAssertTrue(engine.state.isOffRoute)
        XCTAssertNotNil(engine.makeRerouteRequest(from: offRouteCoordinate))
        XCTAssertEqual(engine.lastRouteMatchDiagnostics?.rerouteDecision, "allowed: sustained off-route confirmed")
    }

    @MainActor
    func testGuidanceEngineSuppressesOffRouteWhileCreeping() {
        let engine = Self.guidanceEngineForTestRoute()
        let startDate = Date()
        let offRouteCoordinate = GuidanceCoordinate(latitude: 41.003, longitude: -87.0022)

        [0.0, 3.0, 6.0, 9.0, 12.0].forEach { offset in
            engine.update(
                sample: Self.guidanceSample(
                    coordinate: offRouteCoordinate,
                    timestamp: startDate.addingTimeInterval(offset),
                    speedMetersPerSecond: 1.5
                )
            )
        }

        XCTAssertFalse(engine.state.isOffRoute)
        XCTAssertNil(engine.makeRerouteRequest(from: offRouteCoordinate))
        XCTAssertEqual(engine.lastRouteMatchDiagnostics?.rerouteDecision, "blocked: vehicle below off-route speed threshold")
    }

    @MainActor
    func testGuidanceEngineDoesNotLockProgressForwardFromOneOffRouteJump() {
        let engine = Self.guidanceEngineForTestRoute()

        engine.update(
            sample: Self.guidanceSample(
                coordinate: GuidanceCoordinate(latitude: 41.009, longitude: -87.0022)
            )
        )
        XCTAssertFalse(engine.state.isOffRoute)

        engine.update(
            sample: Self.guidanceSample(
                coordinate: GuidanceCoordinate(latitude: 41.002, longitude: -87.00002),
                timestamp: Date().addingTimeInterval(2)
            )
        )

        XCTAssertFalse(engine.state.isOffRoute)
        XCTAssertLessThan(engine.state.routeProgress, 0.35)
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

    func testWeatherRouteProviderScalesCheckpointCountByDistance() {
        XCTAssertEqual(WeatherRouteProvider.recommendedCheckpointCount(forDistanceMiles: 50), 4)
        XCTAssertEqual(WeatherRouteProvider.recommendedCheckpointCount(forDistanceMiles: 150), 5)
        XCTAssertEqual(WeatherRouteProvider.recommendedCheckpointCount(forDistanceMiles: 500), 8)
        XCTAssertEqual(WeatherRouteProvider.recommendedCheckpointCount(forDistanceMiles: 900), 10)
        XCTAssertEqual(WeatherRouteProvider.recommendedCheckpointCount(forDistanceMiles: 1_500), 12)
    }

    func testAircraftSpeechCueFormatterUsesShortCopyAndGroupedAltitude() {
        let aircraft = Aircraft(
            id: "abc",
            callsign: " N123AB ",
            coordinate: GuidanceCoordinate(latitude: 41.0, longitude: -87.0),
            altitudeFeet: 3_200,
            distanceMiles: 1.42,
            isLowNearbyAircraft: true
        )

        XCTAssertEqual(
            AircraftSpeechCueFormatter.spokenCue(for: aircraft),
            "Low aircraft nearby, N123AB, 1.4 miles, 3,200 feet."
        )
    }

    func testAircraftSpeechCueFormatterSkipsMissingOptionalParts() {
        let coordinate = GuidanceCoordinate(latitude: 41.0, longitude: -87.0)

        XCTAssertEqual(
            AircraftSpeechCueFormatter.spokenCue(for: Aircraft(id: "no-call", callsign: " ", coordinate: coordinate, altitudeFeet: 3_200, distanceMiles: 1.42)),
            "Low aircraft nearby, 1.4 miles, 3,200 feet."
        )
        XCTAssertEqual(
            AircraftSpeechCueFormatter.spokenCue(for: Aircraft(id: "no-distance", callsign: "N123AB", coordinate: coordinate, altitudeFeet: 3_200)),
            "Low aircraft nearby, N123AB, 3,200 feet."
        )
        XCTAssertEqual(
            AircraftSpeechCueFormatter.spokenCue(for: Aircraft(id: "no-altitude", callsign: "N123AB", coordinate: coordinate, distanceMiles: 1.42)),
            "Low aircraft nearby, N123AB, 1.4 miles."
        )
    }

    func testWeatherRouteProviderAllowsTwelveCheckpointHardMax() throws {
        let provider = WeatherRouteProvider()
        let checkpoints = try provider.checkpoints(
            for: [
                GuidanceCoordinate(latitude: 41.0, longitude: -87.0),
                GuidanceCoordinate(latitude: 42.0, longitude: -87.0)
            ],
            routeDistanceMeters: 160_000,
            startDate: Date(timeIntervalSince1970: 1_000),
            expectedTravelTimeSeconds: 7_200,
            maxCheckpointCount: 20
        )

        XCTAssertEqual(checkpoints.count, 12)
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
                "highway": "motorway",
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
        XCTAssertEqual(result?.roadClass, .major)
        XCTAssertEqual(result?.highwayTag, "motorway")
        XCTAssertEqual(result?.confidence ?? 0, 0.95, accuracy: 0.0001)
    }

    func testSpeedLimitParsingDecodesHighwayRoadClasses() {
        XCTAssertEqual(SpeedLimitRoadClass(highwayTag: "primary"), .major)
        XCTAssertEqual(SpeedLimitRoadClass(highwayTag: "secondary_link"), .major)
        XCTAssertEqual(SpeedLimitRoadClass(highwayTag: "residential"), .minor)
        XCTAssertEqual(SpeedLimitRoadClass(highwayTag: "service"), .minor)
        XCTAssertEqual(SpeedLimitRoadClass(highwayTag: nil), .unknown)
    }

    func testOSMSpeedLimitServiceCachesWayAndCoordinateResults() async {
        let service = OSMSpeedLimitService()
        let coordinate = GuidanceCoordinate(latitude: 41.0, longitude: -87.0)
        let result = OSMSpeedLimitResult(
            currentSpeedLimitMPH: 35,
            confidence: 0.9,
            roadName: "Main St",
            wayId: 987,
            roadClass: .minor,
            highwayTag: "residential"
        )

        await service.storeCachedResult(result, for: coordinate, timestamp: Date())

        let coordinateKey = OSMSpeedLimitCacheKey.coordinateCorridor(SpeedLimitSegmentCacheKey(coordinate: coordinate))
        let wayKey = OSMSpeedLimitCacheKey.wayId(987)
        let cachedCoordinateResult = await service.cachedResult(for: coordinateKey)
        let cachedWayResult = await service.cachedResult(for: wayKey)
        XCTAssertEqual(cachedCoordinateResult, result)
        XCTAssertEqual(cachedWayResult, result)
    }

    func testSpeedLimitHoldoverKeepsMajorRoadLimitLonger() {
        let now = Date(timeIntervalSince1970: 1_000)
        let coordinate = GuidanceCoordinate(latitude: 42.0, longitude: -87.0)
        let snapshot = SpeedLimitHoldoverPolicy.Snapshot(
            speedLimitMPH: 45,
            confidence: 0.95,
            coordinate: coordinate,
            timestamp: now,
            roadName: "Touhy Ave",
            roadClass: .major,
            highwayTag: "secondary"
        )

        let resolution = SpeedLimitHoldoverPolicy.resolve(
            freshResult: nil,
            previousSnapshot: snapshot,
            coordinate: self.coordinate(coordinate, milesNorth: 1.9),
            now: now.addingTimeInterval(299)
        )

        XCTAssertEqual(resolution.speedLimitMPH, 45)
        guard case .holdover(let heldSnapshot) = resolution else {
            return XCTFail("Expected held major-road speed limit.")
        }
        XCTAssertEqual(heldSnapshot.roadName, "Touhy Ave")
    }

    func testSpeedLimitHoldoverExpiresMajorRoadAfterPolicyWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let coordinate = GuidanceCoordinate(latitude: 42.0, longitude: -87.0)
        let snapshot = SpeedLimitHoldoverPolicy.Snapshot(
            speedLimitMPH: 45,
            coordinate: coordinate,
            timestamp: now,
            roadClass: .major
        )

        XCTAssertEqual(
            SpeedLimitHoldoverPolicy.resolve(
                freshResult: nil,
                previousSnapshot: snapshot,
                coordinate: self.coordinate(coordinate, milesNorth: 2.1),
                now: now.addingTimeInterval(120)
            ),
            .unavailable
        )
        XCTAssertEqual(
            SpeedLimitHoldoverPolicy.resolve(
                freshResult: nil,
                previousSnapshot: snapshot,
                coordinate: self.coordinate(coordinate, milesNorth: 1.0),
                now: now.addingTimeInterval(301)
            ),
            .unavailable
        )
    }

    func testSpeedLimitHoldoverUsesShortMinorRoadWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let coordinate = GuidanceCoordinate(latitude: 42.0, longitude: -87.0)
        let snapshot = SpeedLimitHoldoverPolicy.Snapshot(
            speedLimitMPH: 25,
            coordinate: coordinate,
            timestamp: now,
            roadName: "Side St",
            roadClass: .minor,
            highwayTag: "residential"
        )

        XCTAssertEqual(
            SpeedLimitHoldoverPolicy.resolve(
                freshResult: nil,
                previousSnapshot: snapshot,
                coordinate: self.coordinate(coordinate, milesNorth: 0.24),
                now: now.addingTimeInterval(89)
            ).speedLimitMPH,
            25
        )
        XCTAssertEqual(
            SpeedLimitHoldoverPolicy.resolve(
                freshResult: nil,
                previousSnapshot: snapshot,
                coordinate: self.coordinate(coordinate, milesNorth: 0.26),
                now: now.addingTimeInterval(60)
            ),
            .unavailable
        )
    }

    func testSpeedLimitHoldoverUsesMiddleUnknownRoadWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let coordinate = GuidanceCoordinate(latitude: 42.0, longitude: -87.0)
        let snapshot = SpeedLimitHoldoverPolicy.Snapshot(
            speedLimitMPH: 35,
            coordinate: coordinate,
            timestamp: now,
            roadClass: .unknown
        )

        XCTAssertEqual(
            SpeedLimitHoldoverPolicy.resolve(
                freshResult: nil,
                previousSnapshot: snapshot,
                coordinate: self.coordinate(coordinate, milesNorth: 0.7),
                now: now.addingTimeInterval(179)
            ).speedLimitMPH,
            35
        )
        XCTAssertEqual(
            SpeedLimitHoldoverPolicy.resolve(
                freshResult: nil,
                previousSnapshot: snapshot,
                coordinate: self.coordinate(coordinate, milesNorth: 0.76),
                now: now.addingTimeInterval(120)
            ),
            .unavailable
        )
    }

    func testSpeedLimitHoldoverReplacesImmediatelyOnFreshLookup() {
        let now = Date(timeIntervalSince1970: 1_000)
        let coordinate = GuidanceCoordinate(latitude: 42.0, longitude: -87.0)
        let previous = SpeedLimitHoldoverPolicy.Snapshot(
            speedLimitMPH: 45,
            coordinate: coordinate,
            timestamp: now,
            roadClass: .major
        )
        let freshResult = OSMSpeedLimitResult(
            currentSpeedLimitMPH: 30,
            confidence: 0.9,
            roadName: "Residential St",
            wayId: 55,
            roadClass: .minor,
            highwayTag: "residential"
        )

        let resolution = SpeedLimitHoldoverPolicy.resolve(
            freshResult: freshResult,
            previousSnapshot: previous,
            coordinate: self.coordinate(coordinate, milesNorth: 0.1),
            now: now.addingTimeInterval(30)
        )

        XCTAssertEqual(resolution.speedLimitMPH, 30)
        guard case .fresh(let freshSnapshot) = resolution else {
            return XCTFail("Expected fresh speed-limit replacement.")
        }
        XCTAssertEqual(freshSnapshot.roadClass, .minor)
        XCTAssertEqual(freshSnapshot.roadName, "Residential St")
    }

    func testDanielVoiceResolverPrefersDanielWhenAvailable() {
        let voices = [
            VoiceGuidanceVoiceOption(
                identifier: "com.apple.voice.compact.en-US.Samantha",
                name: "Samantha",
                language: "en-US",
                qualityRank: 1
            ),
            VoiceGuidanceVoiceOption(
                identifier: "com.apple.voice.compact.en-GB.Daniel",
                name: "Daniel",
                language: "en-GB",
                qualityRank: 1
            )
        ]

        XCTAssertEqual(
            VoiceGuidanceVoiceCatalog.danielVoiceIdentifier(in: voices),
            "com.apple.voice.compact.en-GB.Daniel"
        )
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
        XCTAssertEqual(EnforcementAlertSearchRegion(center: center).radiusMiles, 2.0)
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

    func testOSMEnforcementAlertProviderParsesRealTaggedCameraElements() {
        let data = """
        {
          "elements": [
            {
              "type": "node",
              "id": 101,
              "lat": 41.0001,
              "lon": -87.0001,
              "tags": {
                "highway": "speed_camera",
                "name": "Speed camera"
              }
            },
            {
              "type": "node",
              "id": 102,
              "lat": 41.0002,
              "lon": -87.0002,
              "tags": {
                "red_light_camera": "yes"
              }
            },
            {
              "type": "way",
              "id": 103,
              "center": { "lat": 41.0003, "lon": -87.0003 },
              "tags": {
                "type": "enforcement",
                "enforcement": "access"
              }
            },
            {
              "type": "node",
              "id": 104,
              "lat": 41.0004,
              "lon": -87.0004,
              "tags": {
                "camera:type": "red_light"
              }
            },
            {
              "type": "node",
              "id": 105,
              "lat": 41.0005,
              "lon": -87.0005,
              "tags": {
                "device": "camera",
                "enforcement": "maxspeed"
              }
            },
            {
              "type": "node",
              "id": 106,
              "lat": 41.0006,
              "lon": -87.0006,
              "tags": {
                "man_made": "surveillance",
                "surveillance": "traffic"
              }
            },
            {
              "type": "node",
              "id": 107,
              "lat": 41.0007,
              "lon": -87.0007,
              "tags": {
                "amenity": "cafe"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let alerts = OSMEnforcementAlertProvider.parseAlerts(
            from: data,
            reference: GuidanceCoordinate(latitude: 41.0, longitude: -87.0)
        )

        XCTAssertEqual(
            alerts.map(\.id).sorted(),
            ["osm-node-101", "osm-node-102", "osm-node-104", "osm-node-105", "osm-node-106", "osm-way-103"]
        )
        XCTAssertEqual(alerts.first(where: { $0.id == "osm-node-101" })?.type, .speedCamera)
        XCTAssertEqual(alerts.first(where: { $0.id == "osm-node-102" })?.type, .redLightCamera)
        XCTAssertEqual(alerts.first(where: { $0.id == "osm-node-104" })?.type, .redLightCamera)
        XCTAssertEqual(alerts.first(where: { $0.id == "osm-node-105" })?.type, .speedCamera)
        XCTAssertEqual(alerts.first(where: { $0.id == "osm-node-106" })?.type, .other)
        XCTAssertEqual(alerts.first(where: { $0.id == "osm-way-103" })?.type, .other)
        XCTAssertTrue(alerts.allSatisfy { $0.source == "OpenStreetMap Overpass" })
    }

    func testEnforcementVisibilityCapsNoRouteAlertsToClosestTwenty() {
        let center = GuidanceCoordinate(latitude: 41.0, longitude: -87.0)
        let alerts = (0..<80).map { index in
            enforcementAlert(
                id: "nearby-\(String(format: "%02d", index))",
                latitude: 41.0 + (Double(index) * 0.0005),
                longitude: -87.0,
                confidence: Double(index) / 100
            )
        }

        let visibleAlerts = EnforcementAlertVisibilityPolicy.visibleAlerts(
            from: alerts,
            context: EnforcementAlertVisibilityContext(referenceCoordinate: center)
        )

        XCTAssertEqual(visibleAlerts.count, EnforcementAlertVisibilityPolicy.noRouteVisibleLimit)
        XCTAssertEqual(visibleAlerts.first?.id, "nearby-00")
        XCTAssertEqual(visibleAlerts.last?.id, "nearby-19")
        XCTAssertTrue(visibleAlerts.allSatisfy {
            ($0.distanceMiles ?? .greatestFiniteMagnitude) <= EnforcementAlertVisibilityPolicy.noRouteDistanceCapMiles
        })
        XCTAssertEqual(
            EnforcementAlertVisibilityPolicy.statusText(
                visibleAlertCount: visibleAlerts.count,
                hasActiveRoute: false
            ),
            "Showing 20 camera/enforcement reports nearby"
        )
    }

    func testEnforcementVisibilityPrioritizesAheadRouteAlertsAndCapsToTwenty() {
        let routeGeometry = (0...130).map { index in
            GuidanceCoordinate(latitude: 41.0 + (Double(index) * 0.0005), longitude: -87.0)
        }
        let userCoordinate = routeGeometry[30]
        var alerts: [EnforcementAlert] = [
            enforcementAlert(
                id: "off-route-close",
                latitude: routeGeometry[31].latitude,
                longitude: -86.99,
                confidence: 1
            ),
            enforcementAlert(
                id: "behind-on-route",
                latitude: routeGeometry[20].latitude,
                longitude: routeGeometry[20].longitude,
                confidence: 1
            ),
            enforcementAlert(
                id: "ahead-main",
                latitude: routeGeometry[31].latitude,
                longitude: routeGeometry[31].longitude,
                confidence: 1
            )
        ]
        alerts.append(contentsOf: (0..<75).map { index in
            let routeCoordinate = routeGeometry[32 + index]
            return enforcementAlert(
                id: "ahead-filler-\(String(format: "%02d", index))",
                latitude: routeCoordinate.latitude,
                longitude: routeCoordinate.longitude,
                confidence: 0.5
            )
        })

        let visibleAlerts = EnforcementAlertVisibilityPolicy.visibleAlerts(
            from: alerts,
            context: EnforcementAlertVisibilityContext(
                referenceCoordinate: userCoordinate,
                routeGeometry: routeGeometry
            )
        )

        XCTAssertEqual(visibleAlerts.count, EnforcementAlertVisibilityPolicy.routeActiveVisibleLimit)
        XCTAssertEqual(visibleAlerts.first?.id, "ahead-main")
        XCTAssertFalse(visibleAlerts.map(\.id).contains("off-route-close"))
        XCTAssertFalse(visibleAlerts.map(\.id).contains("behind-on-route"))
        XCTAssertTrue(visibleAlerts.allSatisfy {
            ($0.distanceMiles ?? .greatestFiniteMagnitude) <= EnforcementAlertVisibilityPolicy.routeActiveDistanceCapMiles
        })
        XCTAssertEqual(
            EnforcementAlertVisibilityPolicy.statusText(
                visibleAlertCount: visibleAlerts.count,
                hasActiveRoute: true
            ),
            "Showing 20 route-relevant alerts within 2.0 mi"
        )
    }

    func testEnforcementRefreshPolicyRequiresMovementAfterInitialLookup() {
        let now = Date()
        let center = GuidanceCoordinate(latitude: 41.0, longitude: -87.0)
        let routeContextID = "no-route"

        XCTAssertTrue(
            EnforcementAlertRefreshPolicy.shouldRefresh(
                force: false,
                routeContextID: routeContextID,
                lastRouteContextID: nil,
                lastLookupAt: now.addingTimeInterval(-120),
                lastCoordinate: center,
                currentCoordinate: center,
                hasActiveRoute: false,
                currentSpeedMPH: 0,
                now: now
            )
        )

        XCTAssertFalse(
            EnforcementAlertRefreshPolicy.shouldRefresh(
                force: false,
                routeContextID: routeContextID,
                lastRouteContextID: routeContextID,
                lastLookupAt: now.addingTimeInterval(-120),
                lastCoordinate: center,
                currentCoordinate: coordinate(center, milesNorth: 0.2),
                hasActiveRoute: false,
                currentSpeedMPH: 0,
                now: now
            )
        )

        XCTAssertTrue(
            EnforcementAlertRefreshPolicy.shouldRefresh(
                force: false,
                routeContextID: routeContextID,
                lastRouteContextID: routeContextID,
                lastLookupAt: now.addingTimeInterval(-120),
                lastCoordinate: center,
                currentCoordinate: coordinate(center, milesNorth: 1.1),
                hasActiveRoute: false,
                currentSpeedMPH: 30,
                now: now
            )
        )
    }

    func testEnforcementRefreshPolicyUsesHighSpeedMovementThreshold() {
        let now = Date()
        let center = GuidanceCoordinate(latitude: 41.0, longitude: -87.0)
        let routeContextID = "route"

        XCTAssertFalse(
            EnforcementAlertRefreshPolicy.shouldRefresh(
                force: false,
                routeContextID: routeContextID,
                lastRouteContextID: routeContextID,
                lastLookupAt: now.addingTimeInterval(-30),
                lastCoordinate: center,
                currentCoordinate: coordinate(center, milesNorth: 0.55),
                hasActiveRoute: false,
                currentSpeedMPH: 64,
                now: now
            )
        )

        XCTAssertTrue(
            EnforcementAlertRefreshPolicy.shouldRefresh(
                force: false,
                routeContextID: routeContextID,
                lastRouteContextID: routeContextID,
                lastLookupAt: now.addingTimeInterval(-30),
                lastCoordinate: center,
                currentCoordinate: coordinate(center, milesNorth: 0.55),
                hasActiveRoute: false,
                currentSpeedMPH: 65,
                now: now
            )
        )
    }

    func testEnforcementVisibilityUsesRouteFirstFallbackRanking() {
        let routeGeometry = (0...10).map { index in
            GuidanceCoordinate(latitude: 41.0 + (Double(index) * 0.0005), longitude: -87.0)
        }
        let userCoordinate = routeGeometry[1]
        let alerts = [
            enforcementAlert(id: "near-route-ahead", latitude: routeGeometry[3].latitude, longitude: routeGeometry[3].longitude, confidence: 0.7),
            enforcementAlert(id: "near-route-behind", latitude: routeGeometry[0].latitude, longitude: routeGeometry[0].longitude, confidence: 0.9),
            enforcementAlert(id: "fallback-close", latitude: routeGeometry[2].latitude, longitude: -86.99, confidence: 1),
            enforcementAlert(id: "fallback-farther", latitude: routeGeometry[4].latitude, longitude: -86.98, confidence: 0.4)
        ]

        let visibleAlerts = EnforcementAlertVisibilityPolicy.visibleAlerts(
            from: alerts,
            context: EnforcementAlertVisibilityContext(
                referenceCoordinate: userCoordinate,
                routeGeometry: routeGeometry
            )
        )

        XCTAssertEqual(visibleAlerts.map(\.id), ["near-route-ahead", "near-route-behind", "fallback-close", "fallback-farther"])
    }

    func testEnforcementAlertFilteringTogglesRedLightAndReportsButKeepsSpeedCameras() {
        let alerts = [
            enforcementAlert(id: "speed", type: .speedCamera),
            enforcementAlert(id: "red", type: .redLightCamera),
            enforcementAlert(id: "reported", type: .policeReported),
            enforcementAlert(id: "other", type: .other)
        ]

        XCTAssertEqual(
            EnforcementAlertVisibilityPolicy.filteredAlerts(
                from: alerts,
                redLightCameraAlertsEnabled: false,
                enforcementReportAlertsEnabled: false
            ).map(\.id),
            ["speed"]
        )
        XCTAssertEqual(
            EnforcementAlertVisibilityPolicy.filteredAlerts(
                from: alerts,
                redLightCameraAlertsEnabled: true,
                enforcementReportAlertsEnabled: false
            ).map(\.id),
            ["speed", "red"]
        )
        XCTAssertEqual(
            EnforcementAlertVisibilityPolicy.filteredAlerts(
                from: alerts,
                redLightCameraAlertsEnabled: false,
                enforcementReportAlertsEnabled: true
            ).map(\.id),
            ["speed", "reported", "other"]
        )
    }

    func testAircraftProjectionUsesHeadingSpeedAndElapsedTime() {
        let now = Date(timeIntervalSince1970: 1_000)
        let aircraft = Aircraft(
            id: "proj",
            callsign: "PROJ",
            coordinate: GuidanceCoordinate(latitude: 41.0, longitude: -87.0),
            headingDegrees: 90,
            groundSpeedMPH: 360,
            lastPositionDate: now,
            timePositionDate: now,
            isLowNearbyAircraft: true
        )

        let projected = AircraftPositionProjection.projectedAircraft(
            aircraft,
            reference: GuidanceCoordinate(latitude: 41.0, longitude: -87.0),
            now: now.addingTimeInterval(10),
            staleTimeoutSeconds: 90
        )

        XCTAssertNotNil(projected)
        XCTAssertGreaterThan(projected?.coordinate.longitude ?? -87.0, -87.0)
        XCTAssertEqual(projected?.dataAgeSeconds ?? 0, 10, accuracy: 0.01)
        XCTAssertNotNil(projected?.distanceMiles)
    }

    func testAircraftProjectionDropsStalePositions() {
        let now = Date(timeIntervalSince1970: 1_000)
        let aircraft = Aircraft(
            id: "stale-proj",
            callsign: "STALE",
            coordinate: GuidanceCoordinate(latitude: 41.0, longitude: -87.0),
            headingDegrees: 90,
            groundSpeedMPH: 360,
            lastPositionDate: now.addingTimeInterval(-120),
            timePositionDate: now.addingTimeInterval(-120),
            isLowNearbyAircraft: true
        )

        XCTAssertNil(
            AircraftPositionProjection.projectedAircraft(
                aircraft,
                now: now,
                staleTimeoutSeconds: 90
            )
        )
    }

    @MainActor
    private static func guidanceEngineForTestRoute() -> TurnByTurnGuidanceEngine {
        let engine = TurnByTurnGuidanceEngine(offRouteThresholdMeters: 50)
        engine.setMuted(true)
        engine.loadRoute(
            steps: guidanceTestSteps(),
            routeDistanceMeters: 1_000,
            destination: GuidanceCoordinate(latitude: 41.01, longitude: -87.0),
            routeGeometry: guidanceTestRouteGeometry
        )
        return engine
    }

    private static var guidanceTestRouteGeometry: [GuidanceCoordinate] {
        [
            GuidanceCoordinate(latitude: 41.0, longitude: -87.0),
            GuidanceCoordinate(latitude: 41.0005, longitude: -87.0),
            GuidanceCoordinate(latitude: 41.01, longitude: -87.0)
        ]
    }

    private static func guidanceTestSteps() -> [RouteManeuverStep] {
        [
            RouteManeuverStep(
                instruction: "Turn right onto Main St",
                distanceMeters: 100,
                geometry: Array(guidanceTestRouteGeometry.prefix(2)),
                transportType: .automobile
            ),
            RouteManeuverStep(
                instruction: "Continue on I-90",
                distanceMeters: 900,
                geometry: Array(guidanceTestRouteGeometry.suffix(2)),
                transportType: .automobile
            )
        ]
    }

    private static func guidanceSample(
        coordinate: GuidanceCoordinate,
        timestamp: Date = Date(),
        speedMetersPerSecond: Double = 13
    ) -> GuidanceLocationSample {
        GuidanceLocationSample(
            coordinate: coordinate,
            timestamp: timestamp,
            horizontalAccuracyMeters: 10,
            speedMetersPerSecond: speedMetersPerSecond,
            courseDegrees: 0,
            courseAccuracyDegrees: 12
        )
    }

    private func enforcementAlert(
        id: String,
        latitude: Double,
        longitude: Double,
        confidence: Double
    ) -> EnforcementAlert {
        enforcementAlert(id: id, type: .speedCamera, latitude: latitude, longitude: longitude, confidence: confidence)
    }

    private func enforcementAlert(
        id: String,
        type: EnforcementAlertType,
        latitude: Double = 41.0,
        longitude: Double = -87.0,
        confidence: Double = 0.8
    ) -> EnforcementAlert {
        EnforcementAlert(
            id: id,
            type: type,
            coordinate: GuidanceCoordinate(latitude: latitude, longitude: longitude),
            source: "Test",
            confidence: confidence
        )
    }

    private func coordinate(_ coordinate: GuidanceCoordinate, milesNorth miles: Double) -> GuidanceCoordinate {
        GuidanceCoordinate(
            latitude: coordinate.latitude + (miles / 69.0),
            longitude: coordinate.longitude
        )
    }
}
