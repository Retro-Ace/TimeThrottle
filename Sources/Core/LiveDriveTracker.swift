#if os(iOS)
import Combine
import CoreLocation
import Foundation

public struct LiveDriveConfiguration: Equatable, Sendable {
    public var baselineRouteETAMinutes: Double
    public var baselineRouteDistanceMiles: Double
    public var locationUpdateThrottleSeconds: TimeInterval
    public var summaryUpdateIntervalSeconds: TimeInterval
    public var distanceFilterMeters: CLLocationDistance
    public var desiredAccuracy: CLLocationAccuracy

    public init(
        baselineRouteETAMinutes: Double = 0,
        baselineRouteDistanceMiles: Double = 0,
        locationUpdateThrottleSeconds: TimeInterval = 1,
        summaryUpdateIntervalSeconds: TimeInterval = 2,
        distanceFilterMeters: CLLocationDistance = 10,
        desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBestForNavigation
    ) {
        self.baselineRouteETAMinutes = baselineRouteETAMinutes
        self.baselineRouteDistanceMiles = baselineRouteDistanceMiles
        self.locationUpdateThrottleSeconds = locationUpdateThrottleSeconds
        self.summaryUpdateIntervalSeconds = min(max(summaryUpdateIntervalSeconds, 1), 3)
        self.distanceFilterMeters = distanceFilterMeters
        self.desiredAccuracy = desiredAccuracy
    }
}

public struct LiveDriveSnapshot: Equatable, Sendable {
    public var currentSpeed: Double
    public var topSpeed: Double
    public var distanceTraveled: Double
    public var tripDuration: Double
    public var timeAboveTargetSpeed: Double
    public var timeBelowTargetSpeed: Double
    public var estimatedTimeLostBelowTargetPace: Double
    public var expectedArrivalTime: Date?
    public var tripSummary: TripSummary
    public var sampleCount: Int
    public var isPaused: Bool
    public var didFinishTrip: Bool

    public init(
        currentSpeed: Double = 0,
        topSpeed: Double = 0,
        distanceTraveled: Double = 0,
        tripDuration: Double = 0,
        timeAboveTargetSpeed: Double = 0,
        timeBelowTargetSpeed: Double = 0,
        estimatedTimeLostBelowTargetPace: Double = 0,
        expectedArrivalTime: Date? = nil,
        tripSummary: TripSummary = TripSummary(),
        sampleCount: Int = 0,
        isPaused: Bool = false,
        didFinishTrip: Bool = false
    ) {
        self.currentSpeed = currentSpeed
        self.topSpeed = topSpeed
        self.distanceTraveled = distanceTraveled
        self.tripDuration = tripDuration
        self.timeAboveTargetSpeed = timeAboveTargetSpeed
        self.timeBelowTargetSpeed = timeBelowTargetSpeed
        self.estimatedTimeLostBelowTargetPace = estimatedTimeLostBelowTargetPace
        self.expectedArrivalTime = expectedArrivalTime
        self.tripSummary = tripSummary
        self.sampleCount = sampleCount
        self.isPaused = isPaused
        self.didFinishTrip = didFinishTrip
    }
}

public enum LiveDrivePermissionState: Equatable, Sendable {
    case notDetermined
    case authorizedWhenInUse
    case authorizedAlways
    case denied
    case restricted

    var requiresSettingsAction: Bool {
        self == .denied || self == .authorizedWhenInUse
    }

    var supportsBackgroundContinuation: Bool {
        self == .authorizedAlways
    }
}

@MainActor
public final class LiveDriveTracker: NSObject, ObservableObject {
    @Published public private(set) var currentSpeed: Double = 0
    @Published public private(set) var topSpeed: Double = 0
    @Published public private(set) var distanceTraveled: Double = 0
    @Published public private(set) var tripDuration: Double = 0
    @Published public private(set) var timeAboveTargetSpeed: Double = 0
    @Published public private(set) var timeBelowTargetSpeed: Double = 0
    @Published public private(set) var estimatedTimeLostBelowTargetPace: Double = 0
    @Published public private(set) var expectedArrivalTime: Date?
    @Published public private(set) var tripSummary: TripSummary = TripSummary()
    @Published public private(set) var analysisResult: TripAnalysisResult = TripAnalysisResult()
    @Published public private(set) var currentSpeedLimitMPH: Int?
    @Published public private(set) var isTracking = false
    @Published public private(set) var isPaused = false
    @Published public private(set) var didFinishTrip = false
    @Published public private(set) var permissionState: LiveDrivePermissionState
    @Published public private(set) var currentCoordinate: GuidanceCoordinate?
    @Published public private(set) var trackedPathCoordinates: [GuidanceCoordinate] = []

    public var configuration: LiveDriveConfiguration {
        didSet {
            applyConfiguration()
            recomputeSummary(force: true)
        }
    }

    private let locationManager = CLLocationManager()
    private var analysisState = TripAnalysisState()
    private var lastAcceptedLocation: CLLocation?
    private var lastAcceptedSampleTimestamp: Date?
    private var lastSummaryComputation: Date?
    private var pendingTripStart = false
    private var acceptedLocationCount = 0
    private var accumulatedActiveDuration: TimeInterval = 0
    private var currentActiveIntervalStartedAt: Date?
    private var elapsedTimer: Timer?
    private var hasReachedProjectedPaceSpeed = false

    private static let projectedPaceStartSpeedMPH: Double = 7
    private static let maximumTrackedPathCoordinateCount = 700

    public init(configuration: LiveDriveConfiguration = LiveDriveConfiguration()) {
        self.configuration = configuration
        self.permissionState = .notDetermined
        super.init()
        locationManager.delegate = self
        applyConfiguration()
        permissionState = Self.permissionState(for: locationManager.authorizationStatus)
    }

    public func startTrip(requiresBackgroundContinuation: Bool = false) {
        guard !isTracking, !isPaused else { return }
        prepareForNewTrip()
        pendingTripStart = true

        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            permissionState = .authorizedAlways
            beginTrackingUpdates()
        case .authorizedWhenInUse:
            permissionState = .authorizedWhenInUse
            beginTrackingUpdates()
            if requiresBackgroundContinuation {
                locationManager.requestAlwaysAuthorization()
            }
        case .notDetermined:
            permissionState = .notDetermined
            if requiresBackgroundContinuation {
                locationManager.requestAlwaysAuthorization()
            } else {
                locationManager.requestWhenInUseAuthorization()
            }
        case .denied:
            permissionState = .denied
            pendingTripStart = false
        case .restricted:
            permissionState = .restricted
            pendingTripStart = false
        @unknown default:
            permissionState = .notDetermined
            pendingTripStart = false
        }
    }

    public func pauseTrip() {
        guard isTracking else { return }
        pendingTripStart = false
        isTracking = false
        isPaused = true
        currentSpeed = 0
        finishActiveInterval(at: Date())
        lastAcceptedLocation = nil
        lastAcceptedSampleTimestamp = nil
        locationManager.stopUpdatingLocation()
        updateBackgroundLocationBehavior()
        recomputeSummary(force: true)
    }

    public func resumeTrip() {
        guard isPaused, !didFinishTrip else { return }
        isPaused = false
        beginTrackingUpdates()
    }

    public func endTrip() {
        guard isTracking || isPaused || hasTripData else { return }
        pendingTripStart = false
        if isTracking {
            finishActiveInterval(at: Date())
        } else {
            updateTripDuration(now: Date())
        }
        isTracking = false
        isPaused = false
        didFinishTrip = true
        currentSpeed = 0
        locationManager.stopUpdatingLocation()
        updateBackgroundLocationBehavior()
        recomputeSummary(force: true)
    }

    public func stopTrip() {
        pauseTrip()
    }

    public func resetTrip() {
        locationManager.stopUpdatingLocation()
        pendingTripStart = false
        isTracking = false
        isPaused = false
        didFinishTrip = false
        currentSpeed = 0
        topSpeed = 0
        distanceTraveled = 0
        tripDuration = 0
        timeAboveTargetSpeed = 0
        timeBelowTargetSpeed = 0
        estimatedTimeLostBelowTargetPace = 0
        expectedArrivalTime = nil
        tripSummary = TripSummary()
        analysisResult = TripAnalysisResult()
        currentSpeedLimitMPH = nil
        analysisState = TripAnalysisState()
        lastAcceptedLocation = nil
        currentCoordinate = nil
        trackedPathCoordinates = []
        lastAcceptedSampleTimestamp = nil
        lastSummaryComputation = nil
        hasReachedProjectedPaceSpeed = false
        acceptedLocationCount = 0
        accumulatedActiveDuration = 0
        currentActiveIntervalStartedAt = nil
        invalidateElapsedTimer()
        updateBackgroundLocationBehavior()
    }

    public func requestBackgroundContinuationAuthorization() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            permissionState = .authorizedAlways
        case .authorizedWhenInUse, .notDetermined:
            locationManager.requestAlwaysAuthorization()
        case .denied:
            permissionState = .denied
        case .restricted:
            permissionState = .restricted
        @unknown default:
            permissionState = .notDetermined
        }
    }

    public func updateSpeedLimitEstimate(_ speedLimitMPH: Int?) {
        currentSpeedLimitMPH = speedLimitMPH
    }

    public func refreshAuthorizationState() {
        permissionState = Self.permissionState(for: locationManager.authorizationStatus)
        updateBackgroundLocationBehavior()
    }

    public var snapshot: LiveDriveSnapshot {
        LiveDriveSnapshot(
            currentSpeed: currentSpeed,
            topSpeed: topSpeed,
            distanceTraveled: distanceTraveled,
            tripDuration: tripDuration,
            timeAboveTargetSpeed: timeAboveTargetSpeed,
            timeBelowTargetSpeed: timeBelowTargetSpeed,
            estimatedTimeLostBelowTargetPace: estimatedTimeLostBelowTargetPace,
            expectedArrivalTime: expectedArrivalTime,
            tripSummary: tripSummary,
            sampleCount: acceptedLocationCount,
            isPaused: isPaused,
            didFinishTrip: didFinishTrip
        )
    }

    private var hasTripData: Bool {
        distanceTraveled > 0 || tripDuration > 0 || acceptedLocationCount > 0
    }

    private func prepareForNewTrip() {
        resetTrip()
        didFinishTrip = false
    }

    private func applyConfiguration() {
        locationManager.activityType = .automotiveNavigation
        locationManager.desiredAccuracy = configuration.desiredAccuracy
        locationManager.distanceFilter = configuration.distanceFilterMeters
        locationManager.pausesLocationUpdatesAutomatically = false
        updateBackgroundLocationBehavior()
    }

    private func beginTrackingUpdates() {
        isTracking = true
        isPaused = false
        didFinishTrip = false
        pendingTripStart = false
        startActiveInterval(at: Date())
        updateBackgroundLocationBehavior()
        locationManager.startUpdatingLocation()
    }

    private func updateBackgroundLocationBehavior() {
        let allowsBackgroundContinuation = isTracking && permissionState.supportsBackgroundContinuation
        locationManager.allowsBackgroundLocationUpdates = allowsBackgroundContinuation
        locationManager.showsBackgroundLocationIndicator = allowsBackgroundContinuation
    }

    private func startActiveInterval(at date: Date) {
        currentActiveIntervalStartedAt = date
        updateTripDuration(now: date)
        startElapsedTimer()
    }

    private func finishActiveInterval(at date: Date) {
        if let currentActiveIntervalStartedAt {
            accumulatedActiveDuration += max(date.timeIntervalSince(currentActiveIntervalStartedAt), 0)
        }
        currentActiveIntervalStartedAt = nil
        invalidateElapsedTimer()
        updateTripDuration(now: date)
    }

    private func updateTripDuration(now: Date) {
        let activeInterval = currentActiveIntervalStartedAt.map { max(now.timeIntervalSince($0), 0) } ?? 0
        tripDuration = max((accumulatedActiveDuration + activeInterval) / 60, 0)
    }

    private func startElapsedTimer() {
        invalidateElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateTripDuration(now: Date())
            }
        }
        RunLoop.main.add(elapsedTimer!, forMode: .common)
    }

    private func invalidateElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func handleLocation(_ location: CLLocation) {
        guard isTracking else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else { return }

        if let lastAcceptedSampleTimestamp {
            let updateInterval = location.timestamp.timeIntervalSince(lastAcceptedSampleTimestamp)
            if updateInterval < configuration.locationUpdateThrottleSeconds {
                return
            }
        }

        let speedMilesPerHour = resolvedSpeedMilesPerHour(for: location)
        let previousLocation = lastAcceptedLocation
        let hadReachedProjectedPaceSpeed = hasReachedProjectedPaceSpeed
        let shouldIncludePaceSegment = configuration.baselineRouteDistanceMiles <= 0 ||
            hadReachedProjectedPaceSpeed

        if speedMilesPerHour > Self.projectedPaceStartSpeedMPH {
            hasReachedProjectedPaceSpeed = true
        }

        if let previousLocation, shouldIncludePaceSegment {
            let elapsedMinutes = max(location.timestamp.timeIntervalSince(previousLocation.timestamp) / 60, 0)
            let distanceIncrementMiles = max(previousLocation.distance(from: location) / 1_609.344, 0)

            analysisState = TripAnalysisEngine.applying(
                update: TripAnalysisUpdate(
                    deltaDistanceMiles: distanceIncrementMiles,
                    deltaTimeMinutes: elapsedMinutes,
                    speedMilesPerHour: speedMilesPerHour,
                    speedLimitMilesPerHour: currentSpeedLimitMPH.map(Double.init)
                ),
                to: analysisState,
                speedLimitMilesPerHour: currentSpeedLimitMPH.map(Double.init)
            )

            distanceTraveled = analysisState.distanceTraveledMiles
            timeAboveTargetSpeed = analysisState.timeAboveTargetSpeed
            timeBelowTargetSpeed = analysisState.timeBelowTargetSpeed
        }

        currentSpeed = speedMilesPerHour
        if location.speed >= 0 {
            topSpeed = max(topSpeed, speedMilesPerHour)
        }
        updateTripDuration(now: location.timestamp)
        lastAcceptedLocation = location
        let acceptedCoordinate = GuidanceCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        currentCoordinate = acceptedCoordinate
        appendTrackedPathCoordinate(acceptedCoordinate)
        lastAcceptedSampleTimestamp = location.timestamp
        acceptedLocationCount += 1

        recomputeSummary(force: false)
    }

    private func appendTrackedPathCoordinate(_ coordinate: GuidanceCoordinate) {
        if let lastCoordinate = trackedPathCoordinates.last,
           lastCoordinate.location.distance(from: coordinate.location) < 6 {
            return
        }

        trackedPathCoordinates.append(coordinate)
        if trackedPathCoordinates.count > Self.maximumTrackedPathCoordinateCount {
            trackedPathCoordinates.removeFirst(trackedPathCoordinates.count - Self.maximumTrackedPathCoordinateCount)
        }
    }

    private func resolvedSpeedMilesPerHour(for location: CLLocation) -> Double {
        if location.speed >= 0 {
            return location.speed * 2.2369362920544
        }

        guard
            let previousLocation = lastAcceptedLocation,
            location.timestamp > previousLocation.timestamp
        else {
            return 0
        }

        let elapsedHours = location.timestamp.timeIntervalSince(previousLocation.timestamp) / 3_600
        guard elapsedHours > 0 else { return 0 }
        let miles = previousLocation.distance(from: location) / 1_609.344
        return max(miles / elapsedHours, 0)
    }

    private func recomputeSummary(force: Bool) {
        let now = lastAcceptedSampleTimestamp ?? Date()

        if !force,
           let lastSummaryComputation,
           now.timeIntervalSince(lastSummaryComputation) < configuration.summaryUpdateIntervalSeconds {
            return
        }

        let result = TripAnalysisEngine.summarize(
            state: analysisState,
            baselineRouteETAMinutes: configuration.baselineRouteETAMinutes,
            baselineRouteDistanceMiles: configuration.baselineRouteDistanceMiles
        )

        analysisResult = result
        tripSummary = result.summary
        estimatedTimeLostBelowTargetPace = result.timeLostBelowTargetPace
        expectedArrivalTime = result.actualTravelMinutes > 0 && configuration.baselineRouteDistanceMiles > 0
            ? now.addingTimeInterval(result.remainingTravelMinutes * 60)
            : nil
        lastSummaryComputation = now
    }

    private static func permissionState(for status: CLAuthorizationStatus) -> LiveDrivePermissionState {
        switch status {
        case .authorizedAlways:
            return .authorizedAlways
        case .authorizedWhenInUse:
            return .authorizedWhenInUse
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
}

extension LiveDriveTracker: CLLocationManagerDelegate {
    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            for location in locations {
                self.handleLocation(location)
            }
        }
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        Task { @MainActor [weak self] in
            guard let self else { return }

            self.permissionState = Self.permissionState(for: status)
            self.updateBackgroundLocationBehavior()

            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                if self.pendingTripStart {
                    self.beginTrackingUpdates()
                }
            case .denied, .restricted:
                self.pendingTripStart = false
                self.isTracking = false
                self.isPaused = false
                self.updateBackgroundLocationBehavior()
                self.locationManager.stopUpdatingLocation()
                self.invalidateElapsedTimer()
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
}
#endif
