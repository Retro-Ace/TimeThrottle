import AVFoundation
import Combine
import CoreLocation
import Foundation
#if canImport(OSLog)
import OSLog
#endif
#if canImport(TimeThrottleCore)
import TimeThrottleCore
#endif

@MainActor
final class ScannerViewModel: ObservableObject {
    enum PlaybackState: Equatable {
        case stopped
        case loading
        case playing
        case paused
        case failed(String)
    }

    @Published var mode: ScannerSystemListMode = .nearby
    @Published private(set) var systems: [ScannerSystem] = []
    @Published private(set) var nearbySystems: [ScannerSystem] = []
    @Published private(set) var latestCalls: [ScannerCall] = []
    @Published private(set) var talkgroups: [ScannerTalkgroup] = []
    @Published private(set) var selectedSystem: ScannerSystem?
    @Published private(set) var userCoordinate: GuidanceCoordinate?
    @Published private(set) var isLoadingSystems = false
    @Published private(set) var isLoadingNearby = false
    @Published private(set) var isLoadingCalls = false
    @Published private(set) var systemsErrorMessage: String?
    @Published private(set) var nearbyMessage: String?
    @Published private(set) var callsErrorTitle: String?
    @Published private(set) var callsErrorMessage: String?
    @Published private(set) var callsEmptyTitle = "No latest calls"
    @Published private(set) var callsEmptyMessage = "This public feed has no recent calls available from the provider."
    @Published var searchText = ""
    @Published private(set) var currentCall: ScannerCall?
    @Published private(set) var playbackState: PlaybackState = .stopped

    private let service: OpenMHzScannerService
    private let locationProvider: ScannerLocationProvider
    private let geocodeCache: ScannerGeocodeCache
    private let geocoder = CLGeocoder()
    private let observerStore = ScannerNotificationObserverStore()
    private var didLoadSystems = false
    private var player: AVPlayer?

    init(
        service: OpenMHzScannerService = OpenMHzScannerService(),
        geocodeCache: ScannerGeocodeCache = ScannerGeocodeCache()
    ) {
        self.service = service
        self.locationProvider = ScannerLocationProvider()
        self.geocodeCache = geocodeCache
        observeAudioInterruptions()
    }

    var activeSystems: [ScannerSystem] {
        ScannerSystemFilters.activeSystems(systems)
    }

    var browseSystems: [ScannerSystem] {
        ScannerSystemFilters.search(activeSystems, query: searchText)
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var hasSystems: Bool {
        !systems.isEmpty
    }

    var isPlaying: Bool {
        playbackState == .playing
    }

    var canStartPlayback: Bool {
        switch playbackState {
        case .playing, .loading, .paused:
            return true
        case .stopped, .failed:
            return latestCalls.contains { canPlay($0) }
        }
    }

    func canPlay(_ call: ScannerCall) -> Bool {
        call.resolvedAudioURL(relativeTo: service.baseURL) != nil
    }

    func loadSystemsIfNeeded() async {
        guard !didLoadSystems else {
            if mode == .nearby, nearbySystems.isEmpty {
                await refreshNearby()
            }
            return
        }
        await loadSystems()
    }

    func loadSystems() async {
        isLoadingSystems = true
        systemsErrorMessage = nil

        do {
            let loadedSystems = try await service.fetchSystems()
            systems = loadedSystems
            didLoadSystems = true
            isLoadingSystems = false
            if mode == .nearby {
                await refreshNearby()
            }
        } catch {
            isLoadingSystems = false
            Self.logScannerFailure("systems", error: error)
            systemsErrorMessage = "Scanner systems are unavailable right now. Browse will update when the provider responds."
        }
    }

    func setMode(_ newMode: ScannerSystemListMode) {
        mode = newMode
        if newMode == .nearby {
            Task { await refreshNearby() }
        }
    }

    func refreshNearby() async {
        guard !systems.isEmpty else {
            nearbySystems = []
            nearbyMessage = "Scanner systems are unavailable right now."
            return
        }

        isLoadingNearby = true
        nearbyMessage = nil

        let coordinate = await locationProvider.currentCoordinate()
        userCoordinate = coordinate

        guard let coordinate else {
            nearbySystems = []
            mode = ScannerNearbyModeResolver.resolvedMode(requested: .nearby, userCoordinate: nil)
            nearbyMessage = locationProvider.userFacingMessage ?? "Location is unavailable. Browse scanner systems instead."
            isLoadingNearby = false
            return
        }

        let systemsWithCoordinates = await geocodedSystems(from: activeSystems)
        nearbySystems = Array(ScannerNearbySorter.sortedSystems(systemsWithCoordinates, from: coordinate).prefix(12))
        if nearbySystems.isEmpty {
            nearbyMessage = "No nearby public scanner systems were found. Browse all systems instead."
        }
        isLoadingNearby = false
    }

    func selectSystem(_ system: ScannerSystem) async {
        if selectedSystem?.id != system.id {
            stop()
        }

        selectedSystem = system
        latestCalls = []
        talkgroups = []
        callsErrorTitle = nil
        callsErrorMessage = nil
        callsEmptyTitle = "No latest calls"
        callsEmptyMessage = "This public feed has no recent calls available from the provider."
        isLoadingCalls = true

        let systemShortName = system.shortName.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let calls = try await service.fetchLatestCalls(for: systemShortName)
            guard selectedSystem?.id == system.id else { return }
            latestCalls = calls.sorted { lhs, rhs in
                (lhs.timestamp ?? .distantPast) > (rhs.timestamp ?? .distantPast)
            }

            if latestCalls.isEmpty {
                callsEmptyTitle = "No recent calls"
                callsEmptyMessage = "The provider returned an empty calls list for this system."
            } else if !latestCalls.contains(where: { canPlay($0) }) {
                callsEmptyTitle = "No playable recent calls"
                callsEmptyMessage = "The provider returned recent call metadata, but none included a playable audio URL."
            }
        } catch {
            guard selectedSystem?.id == system.id else { return }
            Self.logScannerFailure("calls for \(systemShortName)", error: error)
            latestCalls = []
            callsErrorTitle = Self.callsErrorTitle(for: error)
            callsErrorMessage = Self.callsErrorMessage(for: error)
        }
        isLoadingCalls = false

        do {
            let groups = try await service.fetchTalkgroups(for: systemShortName)
            guard selectedSystem?.id == system.id else { return }
            talkgroups = groups
        } catch {
            guard selectedSystem?.id == system.id else { return }
            Self.logScannerFailure("talkgroups for \(systemShortName)", error: error)
            talkgroups = []
        }
    }

    func refreshSelectedSystem() async {
        guard let selectedSystem else { return }
        await selectSystem(selectedSystem)
    }

    func play(_ call: ScannerCall) {
        guard let url = call.resolvedAudioURL(relativeTo: service.baseURL) else {
            Self.logScannerMessage("Scanner call missing playable audio URL id=\(call.id)")
            playbackState = .failed("No playable audio URL is available for this call.")
            currentCall = call
            return
        }

        guard configureAudioSessionForPlayback() else { return }
        currentCall = call
        playbackState = .loading

        let item = AVPlayerItem(url: url)
        removePlaybackEndObserver()
        let playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playNextCall()
            }
        }
        observerStore.setPlaybackEndObserver(playbackEndObserver)

        let player = AVPlayer(playerItem: item)
        self.player = player
        player.play()
        playbackState = .playing
        Self.logScannerMessage("Scanner playback started call=\(call.id)")
    }

    func togglePlayback() {
        switch playbackState {
        case .playing:
            pause()
        case .paused:
            resume()
        case .stopped, .failed:
            if let firstPlayable = latestCalls.first(where: { $0.resolvedAudioURL(relativeTo: service.baseURL) != nil }) {
                play(firstPlayable)
            } else if latestCalls.isEmpty {
                playbackState = .failed("No recent scanner calls are loaded for playback.")
            } else {
                playbackState = .failed("Recent scanner calls loaded, but none include a playable audio URL.")
            }
        case .loading:
            pause()
        }
    }

    func pause() {
        player?.pause()
        if currentCall != nil {
            playbackState = .paused
        }
    }

    func resume() {
        guard player != nil else {
            playbackState = .stopped
            return
        }
        guard configureAudioSessionForPlayback() else { return }
        player?.play()
        playbackState = .playing
    }

    func stop() {
        player?.pause()
        player = nil
        currentCall = nil
        playbackState = .stopped
        removePlaybackEndObserver()
        releaseAudioSession()
    }

    func playNextCall() {
        guard let currentCall,
              let currentIndex = latestCalls.firstIndex(where: { $0.id == currentCall.id }) else {
            stop()
            return
        }

        let remainingCalls = latestCalls.dropFirst(currentIndex + 1)
        guard let nextCall = remainingCalls.first(where: { $0.resolvedAudioURL(relativeTo: service.baseURL) != nil }) else {
            stop()
            return
        }

        play(nextCall)
    }

    private func geocodedSystems(from systems: [ScannerSystem]) async -> [ScannerSystem] {
        var resolvedSystems: [ScannerSystem] = []

        for system in systems.prefix(80) {
            if let cachedCoordinate = geocodeCache.coordinate(for: system) {
                resolvedSystems.append(system.withCoordinate(cachedCoordinate))
                continue
            }

            guard let address = geocodeAddress(for: system) else {
                resolvedSystems.append(system)
                continue
            }

            if let coordinate = await geocode(address: address) {
                geocodeCache.store(coordinate, for: system)
                resolvedSystems.append(system.withCoordinate(coordinate))
            } else {
                resolvedSystems.append(system)
            }
        }

        return resolvedSystems
    }

    private func geocodeAddress(for system: ScannerSystem) -> String? {
        let parts = [system.city, system.county, system.state, system.country]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).scannerViewNonEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func geocode(address: String) async -> GuidanceCoordinate? {
        do {
            let placemarks = try await geocoder.geocodeAddressString(address)
            guard let coordinate = placemarks.first?.location?.coordinate else { return nil }
            return GuidanceCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        } catch {
            return nil
        }
    }

    @discardableResult
    private func configureAudioSessionForPlayback() -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetoothHFP, .allowAirPlay])
            try session.setActive(true)
            return true
        } catch {
            playbackState = .failed("Scanner audio could not start on this device.")
            return false
        }
    }

    private func releaseAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // The player is already stopped; keep UI quiet if iOS rejects deactivation.
        }
    }

    private func observeAudioInterruptions() {
        let interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let typeRawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleAudioInterruption(typeRawValue: typeRawValue)
            }
        }
        observerStore.setInterruptionObserver(interruptionObserver)
    }

    private func handleAudioInterruption(typeRawValue: UInt?) {
        guard let typeRawValue,
              let type = AVAudioSession.InterruptionType(rawValue: typeRawValue) else {
            return
        }

        switch type {
        case .began:
            pause()
        case .ended:
            playbackState = currentCall == nil ? .stopped : .paused
        @unknown default:
            break
        }
    }

    private func removePlaybackEndObserver() {
        observerStore.removePlaybackEndObserver()
    }

    private static func callsErrorTitle(for error: Error) -> String {
        if let scannerError = error as? ScannerServiceError {
            switch scannerError {
            case .httpStatus:
                return "Provider unavailable"
            case .decodeFailure, .invalidResponse:
                return "Network or decode failure"
            case .invalidEndpoint:
                return "Scanner endpoint unavailable"
            }
        }

        if error is DecodingError {
            return "Network or decode failure"
        }

        return "Latest calls unavailable"
    }

    private static func callsErrorMessage(for error: Error) -> String {
        if let scannerError = error as? ScannerServiceError {
            switch scannerError {
            case .invalidEndpoint:
                return "The selected scanner system does not have a usable provider identifier."
            case .invalidResponse:
                return "The scanner provider returned a response TimeThrottle could not read."
            case .httpStatus(let statusCode):
                return "The scanner provider returned HTTP \(statusCode) for latest calls."
            case .decodeFailure(let message):
                return message
            }
        }

        if error is DecodingError {
            return "The scanner provider returned call data in an unexpected format."
        }

        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty
            ? "Latest scanner calls are unavailable for this system right now."
            : description
    }

    private static func logScannerFailure(_ context: String, error: Error) {
        #if canImport(OSLog)
        logger.error("Scanner \(context, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        #endif
    }

    private static func logScannerMessage(_ message: String) {
        #if canImport(OSLog)
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    #if canImport(OSLog)
    private static let logger = Logger(subsystem: "com.timethrottle.app", category: "ScannerUI")
    #endif
}

private final class ScannerNotificationObserverStore {
    private var playbackEndObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    deinit {
        removePlaybackEndObserver()
        removeInterruptionObserver()
    }

    func setPlaybackEndObserver(_ observer: NSObjectProtocol) {
        removePlaybackEndObserver()
        playbackEndObserver = observer
    }

    func setInterruptionObserver(_ observer: NSObjectProtocol) {
        removeInterruptionObserver()
        interruptionObserver = observer
    }

    func removePlaybackEndObserver() {
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
    }

    private func removeInterruptionObserver() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
    }
}

private extension String {
    var scannerViewNonEmpty: String? {
        isEmpty ? nil : self
    }
}

@MainActor
final class ScannerLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<GuidanceCoordinate?, Never>?
    private(set) var userFacingMessage: String?

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func currentCoordinate() async -> GuidanceCoordinate? {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if let location = manager.location {
                return GuidanceCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            }
            return await requestOneLocation()
        case .notDetermined:
            return await requestAuthorizationThenLocation()
        case .denied:
            userFacingMessage = "Location access is off. Browse scanner systems instead."
            return nil
        case .restricted:
            userFacingMessage = "Location is restricted on this device. Browse scanner systems instead."
            return nil
        @unknown default:
            userFacingMessage = "Location is unavailable. Browse scanner systems instead."
            return nil
        }
    }

    private func requestOneLocation() async -> GuidanceCoordinate? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            userFacingMessage = nil
            manager.requestLocation()
        }
    }

    private func requestAuthorizationThenLocation() async -> GuidanceCoordinate? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            userFacingMessage = nil
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                if self.continuation != nil {
                    self.manager.requestLocation()
                }
            case .denied:
                self.userFacingMessage = "Location access is off. Browse scanner systems instead."
                self.resume(nil)
            case .restricted:
                self.userFacingMessage = "Location is restricted on this device. Browse scanner systems instead."
                self.resume(nil)
            case .notDetermined:
                break
            @unknown default:
                self.userFacingMessage = "Location is unavailable. Browse scanner systems instead."
                self.resume(nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let location else {
                self.userFacingMessage = "Location is unavailable. Browse scanner systems instead."
                self.resume(nil)
                return
            }

            self.resume(GuidanceCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.userFacingMessage = "Location is unavailable. Browse scanner systems instead."
            self?.resume(nil)
        }
    }

    private func resume(_ coordinate: GuidanceCoordinate?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }
}
