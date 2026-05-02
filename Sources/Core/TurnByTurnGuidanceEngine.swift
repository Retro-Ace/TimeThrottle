import Combine
import CoreLocation
import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(MapKit)
import MapKit
#endif

public struct GuidanceCoordinate: Codable, Equatable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    public var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

public enum RouteStepTransportType: String, Codable, Sendable {
    case automobile
    case walking
    case transit
    case any
    case unknown
}

#if canImport(MapKit)
public extension RouteStepTransportType {
    init(mapKitType: MKDirectionsTransportType) {
        if mapKitType.contains(.automobile) {
            self = .automobile
        } else if mapKitType.contains(.walking) {
            self = .walking
        } else if mapKitType.contains(.transit) {
            self = .transit
        } else if mapKitType.contains(.any) {
            self = .any
        } else {
            self = .unknown
        }
    }
}
#endif

public struct RouteManeuverStep: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var instruction: String
    public var distanceMeters: Double
    public var geometry: [GuidanceCoordinate]
    public var transportType: RouteStepTransportType

    public init(
        id: UUID = UUID(),
        instruction: String,
        distanceMeters: Double,
        geometry: [GuidanceCoordinate],
        transportType: RouteStepTransportType
    ) {
        self.id = id
        self.instruction = instruction
        self.distanceMeters = distanceMeters
        self.geometry = geometry
        self.transportType = transportType
    }
}

public struct TurnByTurnGuidanceState: Equatable, Sendable {
    public var activeStepIndex: Int?
    public var nextInstruction: String?
    public var distanceToNextManeuverMeters: Double?
    public var routeProgress: Double
    public var isOffRoute: Bool
    public var isMuted: Bool

    public init(
        activeStepIndex: Int? = nil,
        nextInstruction: String? = nil,
        distanceToNextManeuverMeters: Double? = nil,
        routeProgress: Double = 0,
        isOffRoute: Bool = false,
        isMuted: Bool = false
    ) {
        self.activeStepIndex = activeStepIndex
        self.nextInstruction = nextInstruction
        self.distanceToNextManeuverMeters = distanceToNextManeuverMeters
        self.routeProgress = routeProgress
        self.isOffRoute = isOffRoute
        self.isMuted = isMuted
    }
}

public struct RerouteRequest: Equatable, Sendable {
    public var currentLocation: GuidanceCoordinate
    public var destination: GuidanceCoordinate
    public var reason: String

    public init(currentLocation: GuidanceCoordinate, destination: GuidanceCoordinate, reason: String) {
        self.currentLocation = currentLocation
        self.destination = destination
        self.reason = reason
    }
}

public struct GuidanceLocationSample: Equatable, Sendable {
    public var coordinate: GuidanceCoordinate
    public var timestamp: Date
    public var horizontalAccuracyMeters: CLLocationAccuracy
    public var speedMetersPerSecond: Double?
    public var courseDegrees: CLLocationDirection?
    public var courseAccuracyDegrees: CLLocationDirection?

    public init(
        coordinate: GuidanceCoordinate,
        timestamp: Date = Date(),
        horizontalAccuracyMeters: CLLocationAccuracy = 10,
        speedMetersPerSecond: Double? = nil,
        courseDegrees: CLLocationDirection? = nil,
        courseAccuracyDegrees: CLLocationDirection? = nil
    ) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.speedMetersPerSecond = speedMetersPerSecond
        self.courseDegrees = courseDegrees
        self.courseAccuracyDegrees = courseAccuracyDegrees
    }

    public var speedMilesPerHour: Double? {
        speedMetersPerSecond.map { $0 * 2.2369362920544 }
    }
}

public struct GuidanceRouteMatchDiagnostics: Equatable, Sendable {
    public var rawCoordinate: GuidanceCoordinate
    public var horizontalAccuracyMeters: CLLocationAccuracy
    public var speedMilesPerHour: Double?
    public var courseDegrees: CLLocationDirection?
    public var courseAccuracyDegrees: CLLocationDirection?
    public var distanceToRouteMeters: CLLocationDistance?
    public var snappedRouteProgressMeters: Double?
    public var offRouteSampleCount: Int
    public var offRouteElapsedSeconds: TimeInterval
    public var rerouteThresholdMeters: CLLocationDistance
    public var rerouteDecision: String

    public init(
        rawCoordinate: GuidanceCoordinate,
        horizontalAccuracyMeters: CLLocationAccuracy,
        speedMilesPerHour: Double?,
        courseDegrees: CLLocationDirection?,
        courseAccuracyDegrees: CLLocationDirection?,
        distanceToRouteMeters: CLLocationDistance?,
        snappedRouteProgressMeters: Double?,
        offRouteSampleCount: Int,
        offRouteElapsedSeconds: TimeInterval,
        rerouteThresholdMeters: CLLocationDistance,
        rerouteDecision: String
    ) {
        self.rawCoordinate = rawCoordinate
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.speedMilesPerHour = speedMilesPerHour
        self.courseDegrees = courseDegrees
        self.courseAccuracyDegrees = courseAccuracyDegrees
        self.distanceToRouteMeters = distanceToRouteMeters
        self.snappedRouteProgressMeters = snappedRouteProgressMeters
        self.offRouteSampleCount = offRouteSampleCount
        self.offRouteElapsedSeconds = offRouteElapsedSeconds
        self.rerouteThresholdMeters = rerouteThresholdMeters
        self.rerouteDecision = rerouteDecision
    }
}

@MainActor
public final class TurnByTurnGuidanceEngine: ObservableObject {
    @Published public private(set) var state = TurnByTurnGuidanceState()
    @Published public private(set) var voiceSettings: VoiceGuidanceSettings
    public private(set) var lastRouteMatchDiagnostics: GuidanceRouteMatchDiagnostics?

    public var offRouteThresholdMeters: CLLocationDistance
    public var spokenPromptDistanceMeters: CLLocationDistance
    public var minimumPromptIntervalSeconds: TimeInterval

    private var steps: [RouteManeuverStep] = []
    private var routeGeometry: [GuidanceCoordinate] = []
    private var destination: GuidanceCoordinate?
    private var routeDistanceMeters: Double = 0
    private var cumulativeStepEndMeters: [Double] = []
    private var cumulativeRouteGeometryMeters: [Double] = []
    private var lastSnappedGeometryProgressMeters: Double = 0
    private var possibleOffRouteStartedAt: Date?
    private var consecutiveOffRouteSamples = 0
    private var lastSpokenStepID: UUID?
    private var lastSpokenPromptAt: Date?
    private var hasSpokenOffRoutePrompt = false
    #if canImport(AVFoundation)
    private let speechSynthesizer = AVSpeechSynthesizer()
    #endif

    private static let maximumRouteMatchAccuracyMeters: CLLocationAccuracy = 100
    private static let staleLocationSampleSeconds: TimeInterval = 15
    private static let minimumOffRouteSpeedMPH: Double = 7
    private static let minimumOffRouteDistanceMeters: CLLocationDistance = 45
    private static let minimumOffRouteSampleCount = 4
    private static let minimumOffRouteDurationSeconds: TimeInterval = 8
    private static let routeProgressBacktrackToleranceMeters: Double = 60
    private static let maneuverToleranceDistanceMeters: CLLocationDistance = 120

    public init(
        offRouteThresholdMeters: CLLocationDistance = 75,
        spokenPromptDistanceMeters: CLLocationDistance = 500,
        minimumPromptIntervalSeconds: TimeInterval = 7,
        voiceSettings: VoiceGuidanceSettings = VoiceGuidanceSettings()
    ) {
        self.offRouteThresholdMeters = offRouteThresholdMeters
        self.spokenPromptDistanceMeters = spokenPromptDistanceMeters
        self.minimumPromptIntervalSeconds = minimumPromptIntervalSeconds
        self.voiceSettings = voiceSettings
        self.state = TurnByTurnGuidanceState(isMuted: voiceSettings.isMuted)
    }

    public func loadRoute(
        steps: [RouteManeuverStep],
        routeDistanceMeters: Double,
        destination: GuidanceCoordinate? = nil,
        routeGeometry: [GuidanceCoordinate] = []
    ) {
        self.steps = steps.filter { !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.geometry.isEmpty }
        self.routeGeometry = Self.normalizedRouteGeometry(routeGeometry.isEmpty ? self.steps.flatMap(\.geometry) : routeGeometry)
        self.routeDistanceMeters = max(routeDistanceMeters, 0)
        self.destination = destination
        self.cumulativeStepEndMeters = Self.cumulativeDistances(for: self.steps)
        self.cumulativeRouteGeometryMeters = Self.cumulativeCoordinateDistances(for: self.routeGeometry)
        self.lastSnappedGeometryProgressMeters = 0
        self.possibleOffRouteStartedAt = nil
        self.consecutiveOffRouteSamples = 0
        self.lastRouteMatchDiagnostics = nil
        self.lastSpokenStepID = nil
        self.lastSpokenPromptAt = nil
        self.hasSpokenOffRoutePrompt = false
        refreshState(activeStepIndex: self.steps.isEmpty ? nil : 0, distanceToNext: firstStepDistance, progressMeters: 0, isOffRoute: false)
    }

    public func reset() {
        steps = []
        routeGeometry = []
        destination = nil
        routeDistanceMeters = 0
        cumulativeStepEndMeters = []
        cumulativeRouteGeometryMeters = []
        lastSnappedGeometryProgressMeters = 0
        possibleOffRouteStartedAt = nil
        consecutiveOffRouteSamples = 0
        lastRouteMatchDiagnostics = nil
        lastSpokenStepID = nil
        lastSpokenPromptAt = nil
        hasSpokenOffRoutePrompt = false
        state = TurnByTurnGuidanceState(isMuted: voiceSettings.isMuted)
    }

    public func setMuted(_ isMuted: Bool) {
        voiceSettings.isMuted = isMuted
        state.isMuted = isMuted
        if isMuted {
            #if canImport(AVFoundation)
            speechSynthesizer.stopSpeaking(at: .immediate)
            #endif
        }
    }

    public func applyVoiceSettings(_ settings: VoiceGuidanceSettings) {
        voiceSettings = settings
        setMuted(settings.isMuted)
    }

    public func setSpeechRate(_ speechRate: Float) {
        voiceSettings.speechRate = min(max(speechRate, 0.36), 0.58)
    }

    public func selectVoice(identifier: String?) {
        voiceSettings.selectedVoiceIdentifier = identifier
    }

    public var availableVoiceOptions: [VoiceGuidanceVoiceOption] {
        VoiceGuidanceVoiceCatalog.availableEnglishVoices()
    }

    public func update(progressDistanceMeters: Double) {
        guard !steps.isEmpty else {
            state = TurnByTurnGuidanceState(isMuted: voiceSettings.isMuted)
            return
        }

        let progress = max(progressDistanceMeters, 0)
        let activeIndex = cumulativeStepEndMeters.firstIndex { progress < $0 } ?? max(steps.count - 1, 0)
        let distanceToNext = max(cumulativeStepEndMeters[safe: activeIndex] ?? routeDistanceMeters - progress, 0) - progress
        refreshState(activeStepIndex: activeIndex, distanceToNext: max(distanceToNext, 0), progressMeters: progress, isOffRoute: state.isOffRoute)
        speakPromptIfNeeded()
    }

    public func update(currentLocation: GuidanceCoordinate) {
        update(
            sample: GuidanceLocationSample(
                coordinate: currentLocation,
                horizontalAccuracyMeters: 10,
                speedMetersPerSecond: (Self.minimumOffRouteSpeedMPH + 1) / 2.2369362920544
            )
        )
    }

    public func update(sample: GuidanceLocationSample) {
        guard !steps.isEmpty else {
            state = TurnByTurnGuidanceState(isMuted: voiceSettings.isMuted)
            return
        }

        guard isRouteDecisionSampleUsable(sample) else {
            resetOffRouteTracking()
            clearConfirmedOffRouteStateForBlockedSample()
            updateDiagnostics(
                sample: sample,
                match: nil,
                threshold: offRouteThresholdMeters,
                elapsed: 0,
                decision: "blocked: invalid or stale location sample"
            )
            return
        }

        guard let match = nearestRouteMatch(to: sample.coordinate) else {
            resetOffRouteTracking()
            clearConfirmedOffRouteStateForBlockedSample()
            updateDiagnostics(
                sample: sample,
                match: nil,
                threshold: offRouteThresholdMeters,
                elapsed: 0,
                decision: "blocked: no active route geometry"
            )
            return
        }

        let progressMeters = scaledRouteProgressMeters(forGeometryProgress: match.progressMeters)
        let nearestStepIndex = activeStepIndex(forProgressMeters: progressMeters)
        let distanceToNext = nearestStepIndex.map { max((cumulativeStepEndMeters[safe: $0] ?? routeDistanceMeters) - progressMeters, 0) }
        let wasOffRoute = state.isOffRoute
        let isOffRoute = updateOffRouteState(
            sample: sample,
            match: match,
            distanceToNextManeuverMeters: distanceToNext
        )

        refreshState(
            activeStepIndex: nearestStepIndex,
            distanceToNext: distanceToNext,
            progressMeters: progressMeters,
            isOffRoute: isOffRoute
        )
        if isOffRoute, !wasOffRoute, !hasSpokenOffRoutePrompt {
            hasSpokenOffRoutePrompt = true
            speakSystemPrompt("You are off route.")
        } else if !isOffRoute {
            hasSpokenOffRoutePrompt = false
        }
        speakPromptIfNeeded()
    }

    public func makeRerouteRequest(from currentLocation: GuidanceCoordinate) -> RerouteRequest? {
        guard state.isOffRoute, let destination else { return nil }
        return RerouteRequest(
            currentLocation: currentLocation,
            destination: destination,
            reason: "Confirmed sustained off-route"
        )
    }

    public func speakCurrentPrompt() {
        speakPrompt(force: true)
    }

    public func speakTestPrompt() {
        speakSystemPrompt("Continue on route.")
    }

    public func speakSystemPrompt(_ message: String) {
        speak(message: normalizedPrompt(message), force: true)
    }

    private var firstStepDistance: Double? {
        guard let first = steps.first else { return nil }
        return first.distanceMeters
    }

    private func refreshState(
        activeStepIndex: Int?,
        distanceToNext: Double?,
        progressMeters: Double,
        isOffRoute: Bool
    ) {
        let step = activeStepIndex.flatMap { steps[safe: $0] }
        let progress = routeDistanceMeters > 0 ? min(max(progressMeters / routeDistanceMeters, 0), 1) : 0
        state = TurnByTurnGuidanceState(
            activeStepIndex: activeStepIndex,
            nextInstruction: step?.instruction,
            distanceToNextManeuverMeters: distanceToNext,
            routeProgress: progress,
            isOffRoute: isOffRoute,
            isMuted: voiceSettings.isMuted
        )
    }

    private func speakPromptIfNeeded() {
        guard let distance = state.distanceToNextManeuverMeters,
              distance <= spokenPromptDistanceMeters else {
            return
        }

        speakPrompt(force: false)
    }

    private func speakPrompt(force: Bool) {
        guard !voiceSettings.isMuted,
              let activeIndex = state.activeStepIndex,
              let step = steps[safe: activeIndex],
              !step.instruction.isEmpty else {
            return
        }

        guard force || lastSpokenStepID != step.id else { return }
        guard force || canSpeakPromptNow() else { return }
        lastSpokenStepID = step.id

        let prompt = navigationPrompt(for: step, distanceMeters: state.distanceToNextManeuverMeters)
        speak(message: prompt, force: force)
    }

    private func speak(message: String, force: Bool) {
        guard !voiceSettings.isMuted else { return }
        guard force || canSpeakPromptNow() else { return }
        lastSpokenPromptAt = Date()

        #if canImport(AVFoundation)
        configureAudioSessionForGuidance()
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .word)
        }
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = voiceSettings.speechRate
        utterance.volume = voiceSettings.volume
        utterance.pitchMultiplier = 1.0
        if let identifier = voiceSettings.selectedVoiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        } else if let fallbackIdentifier = VoiceGuidanceVoiceCatalog.bestAvailableEnglishVoiceIdentifier(),
                  let voice = AVSpeechSynthesisVoice(identifier: fallbackIdentifier) {
            utterance.voice = voice
        }
        speechSynthesizer.speak(utterance)
        #endif
    }

    private func canSpeakPromptNow() -> Bool {
        guard let lastSpokenPromptAt else { return true }
        return Date().timeIntervalSince(lastSpokenPromptAt) >= minimumPromptIntervalSeconds
    }

    private func navigationPrompt(for step: RouteManeuverStep, distanceMeters: Double?) -> String {
        let instruction = normalizedPrompt(step.instruction)
        guard let distanceMeters, distanceMeters > 60 else {
            return instruction
        }

        return "In \(spokenDistanceString(distanceMeters)), \(instruction.lowercasedFirstLetter)"
    }

    private func normalizedPrompt(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Continue on route." }
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            return trimmed
        }
        return "\(trimmed)."
    }

    private func spokenDistanceString(_ meters: Double) -> String {
        let feet = meters * 3.28084
        if feet < 900 {
            let rounded = max(50, Int((feet / 50).rounded()) * 50)
            return "\(rounded) feet"
        }

        let miles = feet / 5_280
        if miles < 10 {
            return String(format: "%.1f miles", miles)
        }

        return "\(Int(miles.rounded())) miles"
    }

    #if canImport(AVFoundation) && os(iOS)
    private func configureAudioSessionForGuidance() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }
    #elseif canImport(AVFoundation)
    private func configureAudioSessionForGuidance() {}
    #endif

    private func isRouteDecisionSampleUsable(_ sample: GuidanceLocationSample) -> Bool {
        guard sample.horizontalAccuracyMeters >= 0,
              sample.horizontalAccuracyMeters <= Self.maximumRouteMatchAccuracyMeters else {
            return false
        }

        return Date().timeIntervalSince(sample.timestamp) <= Self.staleLocationSampleSeconds
    }

    private func activeStepIndex(forProgressMeters progressMeters: Double) -> Int? {
        guard !steps.isEmpty else { return nil }
        return cumulativeStepEndMeters.firstIndex { progressMeters < $0 } ?? max(steps.count - 1, 0)
    }

    private func nearestRouteMatch(to coordinate: GuidanceCoordinate) -> RouteMatch? {
        guard routeGeometry.count >= 2 else { return nil }

        let minimumProgressMeters = max(0, lastSnappedGeometryProgressMeters - Self.routeProgressBacktrackToleranceMeters)
        let allMatches = routeGeometry.indices.dropLast().compactMap { index -> RouteMatch? in
            guard let startDistance = cumulativeRouteGeometryMeters[safe: index] else { return nil }
            return Self.match(
                coordinate: coordinate,
                segmentStart: routeGeometry[index],
                segmentEnd: routeGeometry[index + 1],
                segmentStartDistanceMeters: startDistance,
                segmentIndex: index
            )
        }

        let forwardMatches = allMatches.filter { $0.progressMeters >= minimumProgressMeters }
        let candidates = forwardMatches.isEmpty ? allMatches : forwardMatches
        return candidates.min(by: { $0.distanceMeters < $1.distanceMeters })
    }

    private func scaledRouteProgressMeters(forGeometryProgress geometryProgressMeters: Double) -> Double {
        let geometryDistanceMeters = cumulativeRouteGeometryMeters.last ?? 0
        guard routeDistanceMeters > 0, geometryDistanceMeters > 0 else {
            return geometryProgressMeters
        }

        return min(max((geometryProgressMeters / geometryDistanceMeters) * routeDistanceMeters, 0), routeDistanceMeters)
    }

    private func updateOffRouteState(
        sample: GuidanceLocationSample,
        match: RouteMatch,
        distanceToNextManeuverMeters: Double?
    ) -> Bool {
        let threshold = offRouteThreshold(for: sample, distanceToNextManeuverMeters: distanceToNextManeuverMeters)
        guard let speedMPH = sample.speedMilesPerHour, speedMPH > Self.minimumOffRouteSpeedMPH else {
            resetOffRouteTracking()
            if match.distanceMeters <= threshold {
                rememberSnappedProgress(match)
            }
            updateDiagnostics(
                sample: sample,
                match: match,
                threshold: threshold,
                elapsed: 0,
                decision: "blocked: vehicle below off-route speed threshold"
            )
            return false
        }

        var isPotentiallyOffRoute = match.distanceMeters > threshold
        if let courseMismatch = courseMismatchDegrees(sample: sample, match: match),
           courseMismatch < 20,
           match.distanceMeters < threshold * 1.35 {
            isPotentiallyOffRoute = false
        }

        guard isPotentiallyOffRoute else {
            resetOffRouteTracking()
            rememberSnappedProgress(match)
            updateDiagnostics(
                sample: sample,
                match: match,
                threshold: threshold,
                elapsed: 0,
                decision: "blocked: within route tolerance"
            )
            return false
        }

        if possibleOffRouteStartedAt == nil {
            possibleOffRouteStartedAt = sample.timestamp
        }
        consecutiveOffRouteSamples += 1

        let elapsed = max(sample.timestamp.timeIntervalSince(possibleOffRouteStartedAt ?? sample.timestamp), 0)
        let isConfirmed = consecutiveOffRouteSamples >= Self.minimumOffRouteSampleCount &&
            elapsed >= Self.minimumOffRouteDurationSeconds
        let decision = isConfirmed ? "allowed: sustained off-route confirmed" : "blocked: waiting for sustained off-route"
        updateDiagnostics(
            sample: sample,
            match: match,
            threshold: threshold,
            elapsed: elapsed,
            decision: decision
        )
        return isConfirmed
    }

    private func rememberSnappedProgress(_ match: RouteMatch) {
        lastSnappedGeometryProgressMeters = max(lastSnappedGeometryProgressMeters, match.progressMeters)
    }

    private func resetOffRouteTracking() {
        possibleOffRouteStartedAt = nil
        consecutiveOffRouteSamples = 0
    }

    private func clearConfirmedOffRouteStateForBlockedSample() {
        guard state.isOffRoute else { return }
        refreshState(
            activeStepIndex: state.activeStepIndex,
            distanceToNext: state.distanceToNextManeuverMeters,
            progressMeters: state.routeProgress * max(routeDistanceMeters, 0),
            isOffRoute: false
        )
        hasSpokenOffRoutePrompt = false
    }

    private func offRouteThreshold(
        for sample: GuidanceLocationSample,
        distanceToNextManeuverMeters: Double?
    ) -> CLLocationDistance {
        var threshold = max(
            Self.minimumOffRouteDistanceMeters,
            offRouteThresholdMeters,
            sample.horizontalAccuracyMeters * 2
        )

        if let distanceToNextManeuverMeters,
           distanceToNextManeuverMeters <= Self.maneuverToleranceDistanceMeters {
            threshold *= 1.5
        }

        return threshold
    }

    private func courseMismatchDegrees(sample: GuidanceLocationSample, match: RouteMatch) -> CLLocationDirection? {
        guard let course = sample.courseDegrees,
              let courseAccuracy = sample.courseAccuracyDegrees,
              course >= 0,
              courseAccuracy >= 0,
              courseAccuracy <= 45,
              let routeBearing = match.routeBearingDegrees else {
            return nil
        }

        let difference = abs(course - routeBearing).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    private func updateDiagnostics(
        sample: GuidanceLocationSample,
        match: RouteMatch?,
        threshold: CLLocationDistance,
        elapsed: TimeInterval,
        decision: String
    ) {
        lastRouteMatchDiagnostics = GuidanceRouteMatchDiagnostics(
            rawCoordinate: sample.coordinate,
            horizontalAccuracyMeters: sample.horizontalAccuracyMeters,
            speedMilesPerHour: sample.speedMilesPerHour,
            courseDegrees: sample.courseDegrees,
            courseAccuracyDegrees: sample.courseAccuracyDegrees,
            distanceToRouteMeters: match?.distanceMeters,
            snappedRouteProgressMeters: match.map { scaledRouteProgressMeters(forGeometryProgress: $0.progressMeters) },
            offRouteSampleCount: consecutiveOffRouteSamples,
            offRouteElapsedSeconds: elapsed,
            rerouteThresholdMeters: threshold,
            rerouteDecision: decision
        )
    }

    private static func normalizedRouteGeometry(_ geometry: [GuidanceCoordinate]) -> [GuidanceCoordinate] {
        geometry.reduce(into: []) { result, coordinate in
            if let last = result.last, last.location.distance(from: coordinate.location) < 1 {
                return
            }
            result.append(coordinate)
        }
    }

    private static func cumulativeCoordinateDistances(for geometry: [GuidanceCoordinate]) -> [Double] {
        guard !geometry.isEmpty else { return [] }
        var distances = Array(repeating: 0.0, count: geometry.count)
        for index in geometry.indices.dropFirst() {
            distances[index] = distances[index - 1] + geometry[index - 1].location.distance(from: geometry[index].location)
        }
        return distances
    }

    private static func match(
        coordinate: GuidanceCoordinate,
        segmentStart: GuidanceCoordinate,
        segmentEnd: GuidanceCoordinate,
        segmentStartDistanceMeters: Double,
        segmentIndex: Int
    ) -> RouteMatch? {
        let originLatitudeRadians = coordinate.latitude * .pi / 180
        let point = ProjectedPoint(coordinate: coordinate, originLatitudeRadians: originLatitudeRadians)
        let start = ProjectedPoint(coordinate: segmentStart, originLatitudeRadians: originLatitudeRadians)
        let end = ProjectedPoint(coordinate: segmentEnd, originLatitudeRadians: originLatitudeRadians)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let segmentLengthSquared = dx * dx + dy * dy
        guard segmentLengthSquared > 0 else { return nil }

        let rawT = ((point.x - start.x) * dx + (point.y - start.y) * dy) / segmentLengthSquared
        let t = min(max(rawT, 0), 1)
        let snappedPoint = ProjectedPoint(x: start.x + dx * t, y: start.y + dy * t)
        let distanceMeters = hypot(point.x - snappedPoint.x, point.y - snappedPoint.y)
        let segmentLengthMeters = segmentStart.location.distance(from: segmentEnd.location)
        let snappedCoordinate = GuidanceCoordinate(
            latitude: segmentStart.latitude + (segmentEnd.latitude - segmentStart.latitude) * t,
            longitude: segmentStart.longitude + (segmentEnd.longitude - segmentStart.longitude) * t
        )

        return RouteMatch(
            distanceMeters: distanceMeters,
            progressMeters: segmentStartDistanceMeters + segmentLengthMeters * t,
            snappedCoordinate: snappedCoordinate,
            routeBearingDegrees: bearingDegrees(from: segmentStart, to: segmentEnd),
            segmentIndex: segmentIndex
        )
    }

    private static func bearingDegrees(from start: GuidanceCoordinate, to end: GuidanceCoordinate) -> CLLocationDirection? {
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude) - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
        guard x != 0 || y != 0 else { return nil }
        let degrees = atan2(y, x) * 180 / .pi
        return degrees >= 0 ? degrees : degrees + 360
    }

    private static func cumulativeDistances(for steps: [RouteManeuverStep]) -> [Double] {
        var runningTotal = 0.0
        return steps.map { step in
            runningTotal += max(step.distanceMeters, 0)
            return runningTotal
        }
    }
}

private struct RouteMatch {
    var distanceMeters: CLLocationDistance
    var progressMeters: Double
    var snappedCoordinate: GuidanceCoordinate
    var routeBearingDegrees: CLLocationDirection?
    var segmentIndex: Int
}

private struct ProjectedPoint {
    private static let earthRadiusMeters = 6_371_000.0

    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(coordinate: GuidanceCoordinate, originLatitudeRadians: Double) {
        let latitudeRadians = coordinate.latitude * .pi / 180
        let longitudeRadians = coordinate.longitude * .pi / 180
        self.x = longitudeRadians * cos(originLatitudeRadians) * Self.earthRadiusMeters
        self.y = latitudeRadians * Self.earthRadiusMeters
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private extension String {
    var lowercasedFirstLetter: String {
        guard let first else { return self }
        return first.lowercased() + String(dropFirst())
    }
}
