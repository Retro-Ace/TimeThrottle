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
    public var targetSpeed: Double
    public var timeSavedBySpeeding: Double
    public var timeLostBelowTargetPace: Double
    public var netTimeGain: Double

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
        targetSpeed: Double,
        timeSavedBySpeeding: Double,
        timeLostBelowTargetPace: Double,
        netTimeGain: Double
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
        self.targetSpeed = targetSpeed
        self.timeSavedBySpeeding = timeSavedBySpeeding
        self.timeLostBelowTargetPace = timeLostBelowTargetPace
        self.netTimeGain = netTimeGain
    }

    public var displayRouteTitle: String {
        "\(sourceName) → \(destinationName)"
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
