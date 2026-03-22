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
            targetSpeed: 65,
            ratedMPG: 30,
            estimatedObservedMPG: 26,
            fuelPricePerGallon: 4,
            timeSavedBySpeeding: 6,
            timeLostBelowTargetPace: 0,
            netTimeGain: 6,
            fuelPenalty: 1.02
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
            targetSpeed: 75,
            ratedMPG: 28,
            estimatedObservedMPG: 23,
            fuelPricePerGallon: 3.75,
            timeSavedBySpeeding: 10,
            timeLostBelowTargetPace: 0,
            netTimeGain: 10,
            fuelPenalty: 4.63
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

    func testUpdatingObservedMPGRecalculatesFuelPenalty() {
        let trip = CompletedTripRecord(
            sourceName: "Chicago",
            destinationName: "Milwaukee",
            routeLabel: "Chicago to Milwaukee",
            baselineRouteETAMinutes: 90,
            baselineRouteDistanceMiles: 92,
            distanceDrivenMiles: 92,
            elapsedDriveMinutes: 88,
            averageTripSpeed: 62.7,
            targetSpeed: 70,
            ratedMPG: 30,
            estimatedObservedMPG: 26,
            fuelPricePerGallon: 4,
            timeSavedBySpeeding: 2,
            timeLostBelowTargetPace: 0,
            netTimeGain: 2,
            fuelPenalty: 1.89
        )

        let updatedTrip = trip.updatingObservedMPG(24)

        XCTAssertEqual(updatedTrip.enteredObservedMPG ?? 0, 24, accuracy: 0.0001)
        XCTAssertEqual(updatedTrip.fuelPenalty, 3.0666666667, accuracy: 0.0001)
    }
}
