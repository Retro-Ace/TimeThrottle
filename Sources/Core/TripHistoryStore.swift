import Combine
import Foundation

public struct CompletedTripRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var completedAt: Date
    public var sourceName: String
    public var destinationName: String
    public var routeLabel: String
    public var baselineRouteETAMinutes: Double
    public var baselineRouteDistanceMiles: Double
    public var distanceDrivenMiles: Double
    public var elapsedDriveMinutes: Double
    public var averageTripSpeed: Double
    public var topSpeedMPH: Double?
    public var legacyTargetSpeed: Double
    public var timeSavedBySpeeding: Double
    public var timeLostBelowTargetPace: Double
    public var netTimeGain: Double
    public var speedLimitMeasuredMinutes: Double
    public var speedLimitUnavailableMinutes: Double

    public var speedLimitCoverageRatio: Double? {
        let total = speedLimitMeasuredMinutes + speedLimitUnavailableMinutes
        guard total > 0 else { return nil }
        return speedLimitMeasuredMinutes / total
    }

    public init(
        id: UUID = UUID(),
        completedAt: Date = Date(),
        sourceName: String,
        destinationName: String,
        routeLabel: String,
        baselineRouteETAMinutes: Double,
        baselineRouteDistanceMiles: Double,
        distanceDrivenMiles: Double,
        elapsedDriveMinutes: Double,
        averageTripSpeed: Double,
        topSpeedMPH: Double? = nil,
        legacyTargetSpeed: Double = 0,
        timeSavedBySpeeding: Double,
        timeLostBelowTargetPace: Double,
        netTimeGain: Double,
        speedLimitMeasuredMinutes: Double = 0,
        speedLimitUnavailableMinutes: Double = 0
    ) {
        self.id = id
        self.completedAt = completedAt
        self.sourceName = sourceName
        self.destinationName = destinationName
        self.routeLabel = routeLabel
        self.baselineRouteETAMinutes = baselineRouteETAMinutes
        self.baselineRouteDistanceMiles = baselineRouteDistanceMiles
        self.distanceDrivenMiles = distanceDrivenMiles
        self.elapsedDriveMinutes = elapsedDriveMinutes
        self.averageTripSpeed = averageTripSpeed
        self.topSpeedMPH = topSpeedMPH
        self.legacyTargetSpeed = legacyTargetSpeed
        self.timeSavedBySpeeding = timeSavedBySpeeding
        self.timeLostBelowTargetPace = timeLostBelowTargetPace
        self.netTimeGain = netTimeGain
        self.speedLimitMeasuredMinutes = speedLimitMeasuredMinutes
        self.speedLimitUnavailableMinutes = speedLimitUnavailableMinutes
    }

    public var displayRouteTitle: String {
        "\(sourceName) → \(destinationName)"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case completedAt
        case sourceName
        case destinationName
        case routeLabel
        case baselineRouteETAMinutes
        case baselineRouteDistanceMiles
        case distanceDrivenMiles
        case elapsedDriveMinutes
        case averageTripSpeed
        case topSpeedMPH
        case legacyTargetSpeed = "targetSpeed"
        case timeSavedBySpeeding
        case timeLostBelowTargetPace
        case netTimeGain
        case speedLimitMeasuredMinutes
        case speedLimitUnavailableMinutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt) ?? Date()
        sourceName = try container.decode(String.self, forKey: .sourceName)
        destinationName = try container.decode(String.self, forKey: .destinationName)
        routeLabel = try container.decode(String.self, forKey: .routeLabel)
        baselineRouteETAMinutes = try container.decode(Double.self, forKey: .baselineRouteETAMinutes)
        baselineRouteDistanceMiles = try container.decode(Double.self, forKey: .baselineRouteDistanceMiles)
        distanceDrivenMiles = try container.decode(Double.self, forKey: .distanceDrivenMiles)
        elapsedDriveMinutes = try container.decode(Double.self, forKey: .elapsedDriveMinutes)
        averageTripSpeed = try container.decode(Double.self, forKey: .averageTripSpeed)
        topSpeedMPH = try container.decodeIfPresent(Double.self, forKey: .topSpeedMPH)
        legacyTargetSpeed = try container.decodeIfPresent(Double.self, forKey: .legacyTargetSpeed) ?? 0
        timeSavedBySpeeding = try container.decode(Double.self, forKey: .timeSavedBySpeeding)
        timeLostBelowTargetPace = try container.decode(Double.self, forKey: .timeLostBelowTargetPace)
        netTimeGain = try container.decode(Double.self, forKey: .netTimeGain)
        speedLimitMeasuredMinutes = try container.decodeIfPresent(Double.self, forKey: .speedLimitMeasuredMinutes) ?? 0
        speedLimitUnavailableMinutes = try container.decodeIfPresent(Double.self, forKey: .speedLimitUnavailableMinutes) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(sourceName, forKey: .sourceName)
        try container.encode(destinationName, forKey: .destinationName)
        try container.encode(routeLabel, forKey: .routeLabel)
        try container.encode(baselineRouteETAMinutes, forKey: .baselineRouteETAMinutes)
        try container.encode(baselineRouteDistanceMiles, forKey: .baselineRouteDistanceMiles)
        try container.encode(distanceDrivenMiles, forKey: .distanceDrivenMiles)
        try container.encode(elapsedDriveMinutes, forKey: .elapsedDriveMinutes)
        try container.encode(averageTripSpeed, forKey: .averageTripSpeed)
        try container.encodeIfPresent(topSpeedMPH, forKey: .topSpeedMPH)
        if legacyTargetSpeed > 0 {
            try container.encode(legacyTargetSpeed, forKey: .legacyTargetSpeed)
        }
        try container.encode(timeSavedBySpeeding, forKey: .timeSavedBySpeeding)
        try container.encode(timeLostBelowTargetPace, forKey: .timeLostBelowTargetPace)
        try container.encode(netTimeGain, forKey: .netTimeGain)
        try container.encode(speedLimitMeasuredMinutes, forKey: .speedLimitMeasuredMinutes)
        try container.encode(speedLimitUnavailableMinutes, forKey: .speedLimitUnavailableMinutes)
    }
}

@available(iOS 17.0, macOS 10.15, *)
@MainActor
public final class TripHistoryStore: ObservableObject {
    @Published public private(set) var trips: [CompletedTripRecord]

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "timethrottle.completedTrips"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.trips = []
        loadTrips()
    }

    public func save(_ trip: CompletedTripRecord) {
        if let existingIndex = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[existingIndex] = trip
        } else {
            trips.insert(trip, at: 0)
        }

        trips.sort { $0.completedAt > $1.completedAt }
        persistTrips()
    }

    public func deleteTrips(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            trips.remove(at: index)
        }
        persistTrips()
    }

    public func removeAll() {
        trips = []
        userDefaults.removeObject(forKey: storageKey)
    }

    private func loadTrips() {
        guard
            let data = userDefaults.data(forKey: storageKey),
            let decoded = try? decoder.decode([CompletedTripRecord].self, from: data)
        else {
            trips = []
            return
        }

        trips = decoded.sorted { $0.completedAt > $1.completedAt }
    }

    private func persistTrips() {
        guard let data = try? encoder.encode(trips) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}
