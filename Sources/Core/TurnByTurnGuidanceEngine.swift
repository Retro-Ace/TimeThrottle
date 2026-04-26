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

@MainActor
public final class TurnByTurnGuidanceEngine: ObservableObject {
    @Published public private(set) var state = TurnByTurnGuidanceState()
    @Published public private(set) var voiceSettings: VoiceGuidanceSettings

    public var offRouteThresholdMeters: CLLocationDistance
    public var spokenPromptDistanceMeters: CLLocationDistance
    public var minimumPromptIntervalSeconds: TimeInterval

    private var steps: [RouteManeuverStep] = []
    private var destination: GuidanceCoordinate?
    private var routeDistanceMeters: Double = 0
    private var cumulativeStepEndMeters: [Double] = []
    private var lastSpokenStepID: UUID?
    private var lastSpokenPromptAt: Date?
    private var hasSpokenOffRoutePrompt = false
    #if canImport(AVFoundation)
    private let speechSynthesizer = AVSpeechSynthesizer()
    #endif

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
        destination: GuidanceCoordinate? = nil
    ) {
        self.steps = steps.filter { !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.geometry.isEmpty }
        self.routeDistanceMeters = max(routeDistanceMeters, 0)
        self.destination = destination
        self.cumulativeStepEndMeters = Self.cumulativeDistances(for: self.steps)
        self.lastSpokenStepID = nil
        self.lastSpokenPromptAt = nil
        self.hasSpokenOffRoutePrompt = false
        refreshState(activeStepIndex: self.steps.isEmpty ? nil : 0, distanceToNext: firstStepDistance, progressMeters: 0, isOffRoute: false)
    }

    public func reset() {
        steps = []
        destination = nil
        routeDistanceMeters = 0
        cumulativeStepEndMeters = []
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
        guard !steps.isEmpty else {
            state = TurnByTurnGuidanceState(isMuted: voiceSettings.isMuted)
            return
        }

        let current = currentLocation.location
        let nearestStepIndex = nearestStepIndex(to: current)
        let distanceToNext = nearestStepIndex.flatMap { distanceToStepEnd(from: current, stepIndex: $0) }
        let nearestRouteDistance = nearestDistanceToRoute(from: current)
        let isOffRoute = nearestRouteDistance.map { $0 > offRouteThresholdMeters } ?? false
        let progressMeters = nearestStepIndex.map { cumulativeStepEndMeters[safe: $0 - 1] ?? 0 } ?? 0

        let wasOffRoute = state.isOffRoute
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
            reason: "Off-route threshold exceeded"
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

    private func nearestStepIndex(to location: CLLocation) -> Int? {
        steps.indices.min { left, right in
            let leftDistance = nearestDistance(from: location, to: steps[left].geometry) ?? .greatestFiniteMagnitude
            let rightDistance = nearestDistance(from: location, to: steps[right].geometry) ?? .greatestFiniteMagnitude
            return leftDistance < rightDistance
        }
    }

    private func distanceToStepEnd(from location: CLLocation, stepIndex: Int) -> Double? {
        guard let end = steps[safe: stepIndex]?.geometry.last?.location else { return nil }
        return location.distance(from: end)
    }

    private func nearestDistanceToRoute(from location: CLLocation) -> Double? {
        let routeGeometry = steps.flatMap(\.geometry)
        return nearestDistance(from: location, to: routeGeometry)
    }

    private func nearestDistance(from location: CLLocation, to geometry: [GuidanceCoordinate]) -> Double? {
        guard !geometry.isEmpty else { return nil }
        return geometry.map { location.distance(from: $0.location) }.min()
    }

    private static func cumulativeDistances(for steps: [RouteManeuverStep]) -> [Double] {
        var runningTotal = 0.0
        return steps.map { step in
            runningTotal += max(step.distanceMeters, 0)
            return runningTotal
        }
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
