import Foundation

public actor OpenSkyAircraftProvider: AircraftProvider {
    private let endpoint: URL
    private let session: URLSession
    private let lowAircraftConfiguration: NearbyLowAircraftConfiguration

    public init(
        endpoint: URL = URL(string: "https://opensky-network.org/api/states/all")!,
        session: URLSession = .shared,
        lowAircraftConfiguration: NearbyLowAircraftConfiguration = .default
    ) {
        self.endpoint = endpoint
        self.session = session
        self.lowAircraftConfiguration = lowAircraftConfiguration
    }

    public func nearbyAircraft(in region: AircraftSearchRegion) async throws -> [Aircraft] {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "lamin", value: "\(region.minimumLatitude)"),
            URLQueryItem(name: "lomin", value: "\(region.minimumLongitude)"),
            URLQueryItem(name: "lamax", value: "\(region.maximumLatitude)"),
            URLQueryItem(name: "lomax", value: "\(region.maximumLongitude)")
        ]

        let url = components?.url ?? endpoint
        let (data, _) = try await session.data(from: url)
        return Self.parseAircraft(
            from: data,
            reference: region.center,
            configuration: lowAircraftConfiguration
        )
    }

    public static func parseAircraft(
        from data: Data,
        reference: GuidanceCoordinate? = nil,
        configuration: NearbyLowAircraftConfiguration = .default,
        now: Date = Date()
    ) -> [Aircraft] {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let states = object["states"] as? [[Any]]
        else {
            return []
        }

        return states.compactMap { state -> Aircraft? in
            guard state.count > 10,
                  let icao24 = state[0] as? String,
                  let timePositionSeconds = state[safe: 3] as? Double,
                  let longitude = state[5] as? Double,
                  let latitude = state[6] as? Double,
                  latitude >= -90,
                  latitude <= 90,
                  longitude >= -180,
                  longitude <= 180 else {
                return nil
            }

            let timePositionDate = Date(timeIntervalSince1970: timePositionSeconds)
            let lastContactDate = (state[safe: 4] as? Double).map { Date(timeIntervalSince1970: $0) }
            let dataAgeSeconds = now.timeIntervalSince(timePositionDate)
            guard dataAgeSeconds <= configuration.maximumPositionAgeSeconds else {
                return nil
            }

            let rawCallsign = state[1] as? String
            let callsign = rawCallsign?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false
                ? rawCallsign!.trimmingCharacters(in: .whitespacesAndNewlines)
                : icao24.uppercased()
            let coordinate = GuidanceCoordinate(latitude: latitude, longitude: longitude)
            let distanceMeters = reference.map { $0.location.distance(from: coordinate.location) }
            let distanceMiles = distanceMeters.map { $0 / 1_609.344 }
            guard distanceMiles.map({ $0 <= configuration.radiusMiles }) ?? true else {
                return nil
            }

            let barometricAltitudeMeters = state[safe: 7] as? Double
            let geometricAltitudeMeters = state[safe: 13] as? Double
            let resolvedAltitudeMeters = barometricAltitudeMeters ?? geometricAltitudeMeters
            let altitudeSource: AircraftAltitudeSource = {
                if barometricAltitudeMeters != nil { return .barometric }
                if geometricAltitudeMeters != nil { return .geometric }
                return .unavailable
            }()
            let altitudeFeet = resolvedAltitudeMeters.map { $0 * 3.28084 }
            guard altitudeFeet.map({ $0 <= configuration.maximumAltitudeFeet }) ?? false else {
                return nil
            }

            let velocityMetersPerSecond = state[safe: 9] as? Double
            let groundSpeedKnots = velocityMetersPerSecond.map { $0 * 1.94384449 }
            let groundSpeedMPH = velocityMetersPerSecond.map { $0 * 2.23693629 }

            return Aircraft(
                id: icao24,
                callsign: callsign,
                coordinate: coordinate,
                altitudeMeters: resolvedAltitudeMeters,
                altitudeFeet: altitudeFeet,
                altitudeSource: altitudeSource,
                headingDegrees: state[safe: 10] as? Double,
                groundSpeedKnots: groundSpeedKnots,
                groundSpeedMPH: groundSpeedMPH,
                distanceMeters: distanceMeters,
                distanceMiles: distanceMiles,
                lastPositionDate: timePositionDate,
                lastContactDate: lastContactDate,
                timePositionDate: timePositionDate,
                dataAgeSeconds: dataAgeSeconds,
                isStale: false,
                isLowNearbyAircraft: true
            )
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
