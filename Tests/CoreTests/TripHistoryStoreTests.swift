import XCTest
@testable import TimeThrottleCore

@available(iOS 17.0, macOS 10.15, *)
final class TripHistoryStoreTests: XCTestCase {
    func testSavePersistsAndOrdersNewestTripFirst() async {
        let suiteName = "TripHistoryStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = await MainActor.run {
            TripHistoryStore(
                userDefaults: UserDefaults(suiteName: suiteName)!,
                storageKey: "trip-history-tests"
            )
        }

        let olderTrip = CompletedTripRecord(
            completedAt: Date(timeIntervalSince1970: 10),
            sourceName: "San Francisco",
            destinationName: "San Jose",
            routeLabel: "San Francisco to San Jose",
            baselineRouteETAMinutes: 60,
            baselineRouteDistanceMiles: 50,
            distanceDrivenMiles: 50,
            elapsedDriveMinutes: 54,
            averageTripSpeed: 55,
            timeSavedBySpeeding: 6,
            timeLostBelowTargetPace: 0,
            netTimeGain: 6,
            speedLimitMeasuredMinutes: 54,
            speedLimitUnavailableMinutes: 0
        )

        let newerTrip = CompletedTripRecord(
            completedAt: Date(timeIntervalSince1970: 20),
            sourceName: "Austin",
            destinationName: "Dallas",
            routeLabel: "Austin to Dallas",
            baselineRouteETAMinutes: 180,
            baselineRouteDistanceMiles: 195,
            distanceDrivenMiles: 195,
            elapsedDriveMinutes: 170,
            averageTripSpeed: 68.8,
            timeSavedBySpeeding: 10,
            timeLostBelowTargetPace: 0,
            netTimeGain: 10,
            speedLimitMeasuredMinutes: 160,
            speedLimitUnavailableMinutes: 10
        )

        await MainActor.run {
            store.save(olderTrip)
            store.save(newerTrip)
        }

        let savedIDs = await MainActor.run { store.trips.map(\.id) }
        XCTAssertEqual(savedIDs, [newerTrip.id, olderTrip.id])

        let reloadedStore = await MainActor.run {
            TripHistoryStore(
                userDefaults: UserDefaults(suiteName: suiteName)!,
                storageKey: "trip-history-tests"
            )
        }

        let reloadedTrips = await MainActor.run { reloadedStore.trips }
        XCTAssertEqual(reloadedTrips.count, 2)
        XCTAssertEqual(reloadedTrips.first?.id, newerTrip.id)
    }

    func testSavingExistingTripReplacesMatchingRecord() async {
        let suiteName = "TripHistoryStoreTests-Update-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = await MainActor.run {
            TripHistoryStore(
                userDefaults: UserDefaults(suiteName: suiteName)!,
                storageKey: "trip-history-update-tests"
            )
        }

        let trip = CompletedTripRecord(
            sourceName: "Chicago",
            destinationName: "Milwaukee",
            routeLabel: "Chicago to Milwaukee",
            baselineRouteETAMinutes: 90,
            baselineRouteDistanceMiles: 92,
            distanceDrivenMiles: 92,
            elapsedDriveMinutes: 88,
            averageTripSpeed: 62.7,
            timeSavedBySpeeding: 2,
            timeLostBelowTargetPace: 0,
            netTimeGain: 2,
            speedLimitMeasuredMinutes: 80,
            speedLimitUnavailableMinutes: 8
        )

        var updatedTrip = trip
        updatedTrip.netTimeGain = 4
        updatedTrip.timeSavedBySpeeding = 4

        await MainActor.run {
            store.save(trip)
            store.save(updatedTrip)
        }

        let savedTrips = await MainActor.run { store.trips }
        XCTAssertEqual(savedTrips.count, 1)
        XCTAssertEqual(savedTrips.first?.id, trip.id)
        XCTAssertEqual(savedTrips.first?.netTimeGain ?? 0, 4, accuracy: 0.0001)
        XCTAssertEqual(savedTrips.first?.timeSavedBySpeeding ?? 0, 4, accuracy: 0.0001)
    }

    func testRouteBaselineFlagDistinguishesRouteAndFreeDriveTrips() {
        let routeTrip = CompletedTripRecord(
            sourceName: "Chicago",
            destinationName: "Milwaukee",
            routeLabel: "Chicago to Milwaukee",
            baselineRouteETAMinutes: 90,
            baselineRouteDistanceMiles: 92,
            distanceDrivenMiles: 92,
            elapsedDriveMinutes: 88,
            averageTripSpeed: 62.7,
            timeSavedBySpeeding: 2,
            timeLostBelowTargetPace: 0,
            netTimeGain: 2
        )

        let freeDriveTrip = CompletedTripRecord(
            sourceName: "Current Location",
            destinationName: "No destination",
            routeLabel: "Free Drive",
            baselineRouteETAMinutes: 0,
            baselineRouteDistanceMiles: 0,
            distanceDrivenMiles: 12.4,
            elapsedDriveMinutes: 22,
            averageTripSpeed: 33.8,
            topSpeedMPH: 51,
            timeSavedBySpeeding: 1.5,
            timeLostBelowTargetPace: 0.5,
            netTimeGain: 0
        )

        XCTAssertTrue(routeTrip.hasRouteBaseline)
        XCTAssertFalse(freeDriveTrip.hasRouteBaseline)
        XCTAssertEqual(freeDriveTrip.routeLabel, "Free Drive")
        XCTAssertEqual(freeDriveTrip.destinationName, "No destination")
    }

    func testRouteFreeTripPersistsWithoutRouteBaseline() async {
        let suiteName = "TripHistoryStoreTests-FreeDrive-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = await MainActor.run {
            TripHistoryStore(
                userDefaults: UserDefaults(suiteName: suiteName)!,
                storageKey: "trip-history-free-drive-tests"
            )
        }

        let freeDriveTrip = CompletedTripRecord(
            sourceName: "Current Location",
            destinationName: "No destination",
            routeLabel: "Free Drive",
            baselineRouteETAMinutes: 0,
            baselineRouteDistanceMiles: 0,
            distanceDrivenMiles: 8.2,
            elapsedDriveMinutes: 18,
            averageTripSpeed: 27.3,
            topSpeedMPH: 44,
            timeSavedBySpeeding: 0.75,
            timeLostBelowTargetPace: 1.25,
            netTimeGain: 0,
            speedLimitMeasuredMinutes: 12,
            speedLimitUnavailableMinutes: 6
        )

        await MainActor.run {
            store.save(freeDriveTrip)
        }

        let reloadedStore = await MainActor.run {
            TripHistoryStore(
                userDefaults: UserDefaults(suiteName: suiteName)!,
                storageKey: "trip-history-free-drive-tests"
            )
        }

        let reloadedTrip = await MainActor.run { reloadedStore.trips.first }
        XCTAssertEqual(reloadedTrip?.id, freeDriveTrip.id)
        XCTAssertFalse(reloadedTrip?.hasRouteBaseline ?? true)
        XCTAssertEqual(reloadedTrip?.topSpeedMPH ?? 0, 44, accuracy: 0.0001)
        XCTAssertEqual(reloadedTrip?.timeSavedBySpeeding ?? 0, 0.75, accuracy: 0.0001)
        XCTAssertEqual(reloadedTrip?.timeLostBelowTargetPace ?? 0, 1.25, accuracy: 0.0001)
    }
}
