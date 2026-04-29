import Foundation
import Combine
import CoreLocation
import SwiftUI
#if canImport(TimeThrottleCore)
import TimeThrottleCore
#endif
#if os(iOS)
import UIKit
#endif
#if canImport(WeatherKit)
import WeatherKit
#endif
#if canImport(OSLog)
import OSLog
#endif

private enum LiveDriveScreenState: Equatable {
    case setup
    case driving
    case tripComplete
}

private enum LiveDriveSheetDestination: String, Identifiable {
    case tripHistory
    case scanner

    var id: String { rawValue }
}

private enum LiveDriveMetricEmphasis {
    case standard
    case strong
    case hero
}

private enum LiveDriveHUDSize: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case normal = "Normal"
    case large = "Large"

    var id: String { rawValue }

    var scale: CGFloat {
        switch self {
        case .compact: return 0.9
        case .normal: return 1
        case .large: return 1.12
        }
    }
}

private enum TripExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case summary = "Summary"

    var id: String { rawValue }
}

private struct LiveDriveRouteContext {
    var routes: [RouteEstimate]
    var selectedRouteID: UUID
    var routeLabel: String
    var baselineRouteETAMinutes: Double
    var baselineRouteDistanceMiles: Double

    var selectedRoute: RouteEstimate? {
        routes.first(where: { $0.id == selectedRouteID }) ?? routes.first
    }
}

private struct RouteWeatherDisplayEntry: Identifiable, Equatable {
    var id = UUID()
    var coordinate: GuidanceCoordinate?
    var isForecastAvailable: Bool
    var title: String
    var arrivalText: String
    var forecastText: String
    var detailText: String
    var temperatureText: String?
    var aqiText: String?
    var alertText: String?
    var advisorySummary: String?
    var advisoryAffectedArea: String?
    var advisoryIssuedText: String?
    var advisorySource: String?
    var advisorySourceURL: URL?
}

struct RouteWeatherMapCheckpoint: Identifiable, Equatable {
    var id: UUID
    var coordinate: GuidanceCoordinate
    var title: String
    var arrivalText: String
    var forecastText: String
    var detailText: String
    var temperatureText: String?
    var systemImage: String
}

private struct MapWeatherChipContent: Equatable {
    var systemImage: String
    var temperatureText: String
    var aqiText: String?
}

private enum CameraAlertThreshold: Int, CaseIterable {
    case fiveHundredFeet = 500
    case oneHundredFiftyFeet = 150
    case fiftyFeet = 50

    static func current(for distanceFeet: Double) -> CameraAlertThreshold? {
        if distanceFeet <= Double(fiftyFeet.rawValue) { return .fiftyFeet }
        if distanceFeet <= Double(oneHundredFiftyFeet.rawValue) { return .oneHundredFiftyFeet }
        if distanceFeet <= Double(fiveHundredFeet.rawValue) { return .fiveHundredFeet }
        return nil
    }

    var emphasisTitle: String {
        switch self {
        case .fiveHundredFeet:
            return "Camera report ahead"
        case .oneHundredFiftyFeet:
            return "Camera report close"
        case .fiftyFeet:
            return "Camera report nearby"
        }
    }
}

private struct ActiveCameraWarning: Equatable {
    var alert: EnforcementAlert
    var distanceFeet: Double
    var threshold: CameraAlertThreshold

    var distanceText: String {
        "\(Int(distanceFeet.rounded())) ft"
    }
}

private struct AircraftSpeechMemory: Equatable {
    var lastSpokenAt: Date
    var lastBand: Int
}

public struct RouteComparisonView: View {
    private let brandLogo: Image?
    private let resultBrandLogo: Image?
    private let mapPreview: ([RouteEstimate], UUID?) -> AnyView
    private let weatherProvider: WeatherRouteProvider
    private let speedLimitProvider = OSMSpeedLimitService()
    private let aircraftProvider = OpenSkyAircraftProvider()
    private let enforcementAlertService = EnforcementAlertService()
    private let aircraftRefreshPublisher = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    private let aircraftProjectionPublisher = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private let enforcementAlertRefreshPublisher = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private let aircraftRefreshIntervalSeconds: TimeInterval = 15
    private let aircraftStaleTimeoutSeconds: TimeInterval = 90
    private let enforcementAlertRefreshIntervalSeconds: TimeInterval = 10
    private let enforcementAlertMaximumRefreshIntervalSeconds: TimeInterval = 90
    private let routeActiveEnforcementRefreshMovementMiles: Double = 0.75
    private let noRouteEnforcementRefreshMovementMiles: Double = 1.0
    private static let guidanceVoiceIdentifierStorageKey = "timethrottle.voice.selectedVoiceIdentifier"
    #if canImport(OSLog)
    private static let routeIntelligenceLogger = Logger(subsystem: "com.timethrottle.app", category: "RouteIntelligence")
    #endif

    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedRouteAddressField: RouteAddressField?
    @State private var routeOriginInputMode: RouteOriginInputMode = .currentLocation
    @State private var fromAddressText = ""
    @State private var fromResolvedPlace: ResolvedRoutePlace?
    @State private var toAddressText = ""
    @State private var toResolvedPlace: ResolvedRoutePlace?
    @State private var routeOptions: [RouteEstimate] = []
    @State private var selectedRouteID: UUID?
    @State private var hoveredRouteID: UUID?
    @State private var routeErrorMessage: String?
    @State private var isCalculatingRoute = false
    @State private var routeLookupGeneration = 0
    @State private var didRunCaptureBootstrap = false
    @State private var shareSheetItems: [Any] = []
    @State private var isShareSheetPresented = false
    @AppStorage("timethrottle.preferredNavigationProvider") private var navigationProviderPreferenceRawValue = NavigationProvider.appleMaps.rawValue
    @State private var liveDriveRouteContext: LiveDriveRouteContext?
    @State private var liveDriveFinishedTrip: CompletedTripRecord?
    @State private var liveDriveNavigationProviderPending: NavigationProvider?
    @State private var liveDriveNavigationHandoffMessage: String?
    @State private var routeWeatherRouteID: UUID?
    @State private var routeWeatherEntries: [RouteWeatherDisplayEntry] = []
    @State private var routeWeatherMessage = "Forecast unavailable"
    @State private var isRouteWeatherLoading = false
    @State private var isRouteWeatherVisible = false
    @State private var currentWeatherEntry: RouteWeatherDisplayEntry?
    @State private var currentWeatherMessage = "Weather unavailable"
    @State private var isCurrentWeatherLoading = false
    @State private var lastCurrentWeatherLookupAt: Date?
    @State private var lastCurrentWeatherLookupCoordinate: GuidanceCoordinate?
    @State private var speedLimitDisplayText = "Unavailable"
    @State private var speedLimitDetailText = "OpenStreetMap estimate"
    @State private var lastSpeedLimitLookupAt: Date?
    @AppStorage("timethrottle.voice.selectedVoiceIdentifier") private var storedGuidanceVoiceIdentifier = ""
    @AppStorage("timethrottle.voice.speechRate") private var storedGuidanceSpeechRate = Double(VoiceGuidanceSettings.defaultSpeechRate)
    @AppStorage("timethrottle.voice.volume") private var storedGuidanceVolume = Double(VoiceGuidanceSettings.defaultVolume)
    @AppStorage("timethrottle.voice.isMuted") private var isVoiceGuidanceMuted = false
    @AppStorage("timethrottle.mapMode") private var mapModeRawValue = LiveDriveMapMode.standard.rawValue
    @AppStorage("timethrottle.hudSize") private var hudSizeRawValue = LiveDriveHUDSize.normal.rawValue
    @AppStorage("timethrottle.keepScreenAwake") private var keepScreenAwake = false
    @AppStorage("timethrottle.enforcementAlertsEnabled") private var areEnforcementAlertsEnabled = true
    @AppStorage("timethrottle.redLightCameraAlertsEnabled") private var areRedLightCameraAlertsEnabled = true
    @AppStorage("timethrottle.enforcementReportAlertsEnabled") private var areEnforcementReportAlertsEnabled = true
    @AppStorage("timethrottle.cameraAlertAudioEnabled") private var isCameraAlertAudioEnabled = true
    @State private var isGuidanceRerouting = false
    @State private var guidanceRerouteMessage: String?
    @State private var lastGuidanceRerouteAt: Date?
    @AppStorage("timethrottle.aircraftLayerEnabled") private var showsAircraftLayer = true
    @AppStorage("timethrottle.aircraftAlertAudioEnabled") private var isAircraftAlertAudioEnabled = true
    @State private var aircraftLayer = AircraftLayerState(isVisible: true)
    @State private var aircraftStatusText = "Checking"
    @State private var lastAircraftPollAt: Date?
    @State private var aircraftProjectionDate = Date()
    @State private var spokenAircraftAlertHistory: [String: AircraftSpeechMemory] = [:]
    @State private var enforcementAlerts: [EnforcementAlert] = []
    @State private var enforcementAlertStatusText = "Not updated yet"
    @State private var lastEnforcementAlertLookupAt: Date?
    @State private var lastEnforcementAlertLookupCoordinate: GuidanceCoordinate?
    @State private var lastEnforcementAlertRouteContextID: String?
    @State private var enforcementAlertsLastUpdatedAt: Date?
    @State private var spokenCameraAlertThresholds: [String: Set<Int>] = [:]
    @State private var isRouteFreeLoggingMode = false
    @State private var isRouteSetupPanelPresented = false
    @State private var isMapOptionsPresented = false
    @State private var isVoiceSelectionPresented = false
    @State private var isDeleteAllTripsConfirmationPresented = false
    @AppStorage("timethrottle.defaultTripExportFormat") private var defaultTripExportFormatRawValue = TripExportFormat.csv.rawValue
    @State private var presentedSheetDestination: LiveDriveSheetDestination?
    @State private var isNavigationProviderChoicePresented = false
    @StateObject private var currentLocationResolver = CurrentLocationResolver()
    @StateObject private var autocompleteController = AppleMapsAutocompleteController()
    @StateObject private var tracker = LiveDriveTracker()
    @StateObject private var guidanceEngine = TurnByTurnGuidanceEngine()
    @StateObject private var tripHistoryStore = TripHistoryStore()
    @StateObject private var scannerViewModel = ScannerViewModel()

    public init<MapPreview: View>(
        configuration: RouteComparisonConfiguration = RouteComparisonConfiguration(),
        brandLogo: Image? = nil,
        resultBrandLogo: Image? = nil,
        @ViewBuilder mapPreview: @escaping ([RouteEstimate], UUID?) -> MapPreview
    ) {
        _ = configuration
        self.brandLogo = brandLogo
        self.resultBrandLogo = resultBrandLogo
        self.mapPreview = { routes, selectedRouteID in
            AnyView(mapPreview(routes, selectedRouteID))
        }
        #if canImport(WeatherKit)
        if #available(iOS 16.0, macOS 13.0, *) {
            self.weatherProvider = WeatherRouteProvider(forecastClient: WeatherKitRouteWeatherForecastClient())
        } else {
            self.weatherProvider = WeatherRouteProvider()
        }
        #else
        self.weatherProvider = WeatherRouteProvider()
        #endif
    }

    private var isMobileLayout: Bool {
        true
    }

    private var heroHeight: CGFloat {
        if isMobileLayout {
            return liveDriveScreenState == .setup ? 92 : 160
        }

        return 260
    }

    private var heroLogoHeight: CGFloat {
        isMobileLayout ? 72 : 84
    }

    private var heroSubtitleFont: Font {
        isMobileLayout ? .subheadline.weight(.medium) : .system(size: 16, weight: .medium, design: .rounded)
    }

    private var sectionHeaderFont: Font {
        isMobileLayout ? .headline.weight(.semibold) : .system(size: 19, weight: .bold, design: .rounded)
    }

    private var descriptionFont: Font {
        isMobileLayout ? .subheadline.weight(.medium) : .system(size: 13, weight: .medium, design: .rounded)
    }

    private var panelHeaderFont: Font {
        isMobileLayout ? .headline.weight(.semibold) : .system(size: 16, weight: .bold, design: .rounded)
    }

    private var panelDescriptionFont: Font {
        isMobileLayout ? .subheadline.weight(.medium) : .system(size: 12, weight: .medium, design: .rounded)
    }

    private var routeStatusFont: Font {
        isMobileLayout ? .subheadline.weight(.semibold) : .system(size: 12, weight: .semibold, design: .rounded)
    }

    private var inputLabelFont: Font {
        isMobileLayout ? .subheadline.weight(.semibold) : .system(size: 13, weight: .semibold, design: .rounded)
    }

    private var unitFont: Font {
        isMobileLayout ? .headline.weight(.semibold) : .system(size: 18, weight: .semibold, design: .rounded)
    }

    private var headerGradientStart: Color {
        Color(red: 0.18, green: 0.77, blue: 0.47)
    }

    private var headerGradientEnd: Color {
        Color(red: 0.43, green: 0.90, blue: 0.66)
    }

    private var mobileContentHorizontalPadding: CGFloat {
        isMobileLayout ? 0 : Layout.screenPadding
    }

    private var shouldRunCaptureBootstrap: Bool {
        ProcessInfo.processInfo.environment["TIMETHROTTLE_AUTOCAPTURE"] == "1"
    }

    private var isPolishedLiveDriveSetup: Bool {
        isMobileLayout && liveDriveScreenState == .setup
    }

    private var usesDarkLiveDriveTheme: Bool {
        isMobileLayout
    }

    private var setupBackgroundTop: Color {
        Color(red: 0.05, green: 0.07, blue: 0.11)
    }

    private var setupBackgroundBottom: Color {
        Color(red: 0.09, green: 0.12, blue: 0.18)
    }

    private var setupHeaderTop: Color {
        Color(red: 0.07, green: 0.09, blue: 0.13)
    }

    private var setupHeaderBottom: Color {
        Color(red: 0.12, green: 0.16, blue: 0.21)
    }

    private var setupSurface: Color {
        Color(red: 0.11, green: 0.14, blue: 0.18)
    }

    private var setupSurfaceRaised: Color {
        Color(red: 0.14, green: 0.17, blue: 0.22)
    }

    private var setupSurfaceMuted: Color {
        Color(red: 0.16, green: 0.19, blue: 0.24)
    }

    private var setupFieldFill: Color {
        Color(red: 0.17, green: 0.20, blue: 0.25)
    }

    private var setupPanelBorder: Color {
        Color.white.opacity(0.08)
    }

    private var setupFieldBorder: Color {
        Color.white.opacity(0.10)
    }

    private var setupPrimaryText: Color {
        Color.white.opacity(0.94)
    }

    private var setupSecondaryText: Color {
        Color(red: 0.68, green: 0.73, blue: 0.79)
    }

    private var setupTertiaryText: Color {
        Color.white.opacity(0.58)
    }

    private var setupSelectionFill: Color {
        Color(red: 0.17, green: 0.29, blue: 0.23)
    }

    private var setupSelectionBorder: Color {
        Palette.success.opacity(0.62)
    }

    private var setupChipFill: Color {
        Color(red: 0.13, green: 0.20, blue: 0.17)
    }

    private var setupChipBorder: Color {
        Palette.success.opacity(0.34)
    }

    private var setupErrorFill: Color {
        Color(red: 0.23, green: 0.15, blue: 0.15)
    }

    private var setupErrorBorder: Color {
        Palette.danger.opacity(0.30)
    }

    private var setupShadowColor: Color {
        .black.opacity(0.30)
    }

    private var routeSourceEndpoint: RouteLookupEndpoint? {
        switch routeOriginInputMode {
        case .currentLocation:
            guard let currentPlace = currentLocationResolver.currentPlace else { return nil }
            return .currentLocation(currentPlace)
        case .custom:
            if let fromResolvedPlace {
                return .resolvedPlace(fromResolvedPlace)
            }

            let query = Self.normalizedAddress(fromAddressText)
            guard !query.isEmpty else { return nil }
            return .query(query)
        }
    }

    private var routeDestinationEndpoint: RouteLookupEndpoint? {
        if let toResolvedPlace {
            return .resolvedPlace(toResolvedPlace)
        }

        let query = Self.normalizedAddress(toAddressText)
        guard !query.isEmpty else { return nil }
        return .query(query)
    }

    private var normalizedFromAddress: String {
        routeSourceEndpoint?.signature ?? ""
    }

    private var normalizedToAddress: String {
        routeDestinationEndpoint?.signature ?? ""
    }

    private var currentLocationFieldLabel: String {
        if currentLocationResolver.isResolving && currentLocationResolver.currentPlace == nil {
            return "Finding Current Location..."
        }

        return currentLocationResolver.currentPlace?.title ?? "Current Location"
    }

    private var currentLocationDetailText: String {
        if let subtitle = currentLocationResolver.currentPlace?.subtitle, !subtitle.isEmpty {
            return subtitle
        }

        if let errorMessage = currentLocationResolver.errorMessage {
            return errorMessage
        }

        return "Use your live position as the route start."
    }

    private var fromSuggestions: [AppleMapsAutocompleteController.Suggestion] {
        autocompleteController.activeField == .from ? autocompleteController.suggestions : []
    }

    private var toSuggestions: [AppleMapsAutocompleteController.Suggestion] {
        autocompleteController.activeField == .to ? autocompleteController.suggestions : []
    }

    private var routeOptionsAreCurrent: Bool {
        guard let firstRoute = routeOptions.first else { return false }
        return firstRoute.sourceQuery == normalizedFromAddress && firstRoute.destinationQuery == normalizedToAddress
    }

    private var activeRouteOptions: [RouteEstimate] {
        routeOptionsAreCurrent ? routeOptions : []
    }

    private var activeRouteEstimate: RouteEstimate? {
        guard routeOptionsAreCurrent else { return nil }

        if let selectedRouteID, let route = routeOptions.first(where: { $0.id == selectedRouteID }) {
            return route
        }

        return routeOptions.first
    }

    private var routeNeedsRefresh: Bool {
        guard !routeOptions.isEmpty else { return false }
        return !routeOptionsAreCurrent
    }

    private var liveDriveIsRunning: Bool {
        tracker.isTracking
    }

    private var liveDriveHasTripData: Bool {
        tracker.isTracking || tracker.isPaused || tracker.distanceTraveled > 0 || tracker.tripDuration > 0 || tracker.snapshot.sampleCount > 0
    }

    private var liveDriveScreenState: LiveDriveScreenState {
        if tracker.isTracking || tracker.isPaused {
            return .driving
        }

        if tracker.didFinishTrip || liveDriveFinishedTrip != nil || liveDriveHasTripData {
            return .tripComplete
        }

        return .setup
    }

    private var liveDriveCurrentRouteLabel: String {
        guard let route = activeRouteEstimate, !routeNeedsRefresh else {
            return ""
        }

        let routeName = route.routeName.isEmpty ? "\(route.sourceName) to \(route.destinationName)" : route.routeName
        return "\(routeName) • \(Self.milesString(route.distanceMiles)) mi • \(Self.durationString(route.expectedTravelMinutes))"
    }

    private var liveDriveRouteLabel: String {
        if isRouteFreeLoggingMode {
            return "Free Drive"
        }

        return liveDriveRouteContext?.routeLabel ?? liveDriveCurrentRouteLabel
    }

    private var liveDriveHUDRoute: RouteEstimate? {
        liveDriveCapturedRoute ?? liveDriveSetupRoute
    }

    private var routeWeatherOptionsRoute: RouteEstimate? {
        guard !isRouteFreeLoggingMode else { return nil }
        return liveDriveCapturedRoute ?? liveDriveSetupRoute
    }

    private var liveDriveHUDRouteTitle: String {
        guard let route = liveDriveHUDRoute else { return liveDriveRouteLabel }
        return route.destinationName
    }

    private var liveDriveHUDRouteContextText: String {
        guard let route = liveDriveHUDRoute else { return liveDriveRouteLabel }
        return "From \(route.sourceName)"
    }

    private var liveDriveHUDRouteMetaText: String {
        var parts: [String] = []

        if let route = liveDriveHUDRoute {
            let trimmedRouteName = route.routeName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedRouteName.isEmpty {
                parts.append(trimmedRouteName)
            }

            parts.append("\(Self.milesString(route.distanceMiles)) mi")
        } else if liveDriveBaselineDistanceMiles > 0 {
            parts.append("\(Self.milesString(liveDriveBaselineDistanceMiles)) mi")
        }

        return parts.isEmpty ? liveDriveRouteLabel : parts.joined(separator: " • ")
    }

    private var liveDriveHUDNavigationLabel: String? {
        switch preferredNavigationProvider {
        case .appleMaps, .googleMaps, .waze:
            return preferredNavigationProvider.rawValue
        case .askEveryTime:
            return liveDriveNavigationHandoffMessage == nil ? "Navigation app" : "Navigation status"
        }
    }

    private var liveDriveHUDNavigationMessage: String? {
        if let liveDriveNavigationHandoffMessage {
            return liveDriveNavigationHandoffMessage
        }

        if preferredNavigationProvider == .askEveryTime {
            return "You’ll choose a navigation app when the trip starts."
        }

        return nil
    }

    private var liveDriveHUDGuidanceState: LiveDriveHUDGuidanceState {
        let state = guidanceEngine.state
        return LiveDriveHUDGuidanceState(
            nextInstruction: state.nextInstruction,
            maneuverDistance: state.distanceToNextManeuverMeters.map(Self.guidanceDistanceString),
            isMuted: state.isMuted,
            isOffRoute: state.isOffRoute,
            rerouteStatus: guidanceRerouteHUDText,
            speedLimitEstimate: speedLimitDisplayText,
            speedLimitDetail: speedLimitDetailText,
            weatherAlert: routeWeatherHUDText,
            isAircraftVisible: showsAircraftLayer,
            aircraftSummary: showsAircraftLayer ? aircraftStatusText : "Off",
            enforcementAlertSummary: enforcementHUDText
        )
    }

    private var liveDriveHUDVoiceState: LiveDriveHUDVoiceState {
        let settings = guidanceEngine.voiceSettings
        let voices = guidanceEngine.availableVoiceOptions.map {
            LiveDriveHUDVoiceOption(
                identifier: $0.identifier,
                name: $0.name,
                language: $0.language
            )
        }
        let selectedVoiceName = voices.first(where: { $0.identifier == settings.selectedVoiceIdentifier })?.name
            ?? voices.first?.name
            ?? "System voice"

        return LiveDriveHUDVoiceState(
            selectedVoiceIdentifier: settings.selectedVoiceIdentifier,
            selectedVoiceName: selectedVoiceName,
            speechRate: Double(settings.speechRate),
            isMuted: settings.isMuted,
            availableVoices: voices
        )
    }

    private var guidanceRerouteHUDText: String? {
        if isGuidanceRerouting {
            return "Rerouting..."
        }

        return guidanceRerouteMessage
    }

    private var routeWeatherHUDText: String? {
        guard isRouteWeatherVisible else { return nil }
        if isRouteWeatherLoading { return nil }
        if routeWeatherOptionsRoute == nil {
            if isCurrentWeatherLoading { return nil }
            if let alert = currentWeatherEntry?.alertText { return alert }
            return currentWeatherEntry?.temperatureText.map { "Current weather \($0)" }
        }
        if let alert = routeWeatherEntries.compactMap(\.alertText).first { return alert }
        return routeWeatherEntries.contains(where: { $0.temperatureText?.isEmpty == false })
            ? "\(routeWeatherEntries.count) planned checkpoints"
            : nil
    }

    private var routeWeatherOptionsDescription: String {
        if isRouteWeatherLoading {
            return "Loading route forecast..."
        }

        if routeWeatherOptionsRoute == nil {
            if isRouteWeatherVisible {
                return "Weather follows your current location."
            }

            return "Show current weather when no route is selected."
        }

        if isRouteWeatherVisible {
            return "Forecasts are matched to expected arrival times."
        }

        return "Show forecast checkpoints for the selected route."
    }

    private var enforcementHUDText: String? {
        guard areEnforcementAlertsEnabled else { return "Off" }
        guard !enforcementAlerts.isEmpty else { return nil }

        if enforcementAlerts.count == 1 {
            switch enforcementAlerts[0].type {
            case .speedCamera, .redLightCamera:
                return "Camera ahead"
            case .policeReported:
                return "Reported nearby"
            case .other:
                return "Enforcement nearby"
            }
        }

        return enforcementAlertStatusText
    }

    private var enforcementAlertOptionsStatusText: String {
        guard areEnforcementAlertsEnabled else { return "Off" }
        return enforcementAlertStatusText
    }

    private var liveDriveHUDMapContent: AnyView? {
        guard let selectedRoute = liveDriveHUDRoute else { return nil }
        let routes = liveDriveRouteContext?.routes ?? liveDriveSetupRouteOptions
        #if os(iOS)
        return AnyView(
            LiveDriveHUDMapView(
                routes: routes,
                selectedRouteID: selectedRoute.id,
                aircraft: mapAircraftMarkers,
                enforcementAlerts: mapEnforcementAlertMarkers,
                weatherCheckpoints: mapWeatherCheckpointMarkers,
                mapMode: selectedMapMode
            )
        )
        #else
        return AnyView(mapPreview(routes, selectedRoute.id))
        #endif
    }

    private var fullRouteMapRoute: RouteEstimate? {
        liveDriveScreenState == .driving ? liveDriveHUDRoute : nil
    }

    private var fullRouteMapRoutes: [RouteEstimate] {
        if liveDriveScreenState == .driving {
            if let liveDriveRouteContext {
                return liveDriveRouteContext.routes
            }

            return liveDriveSetupRouteOptions
        }

        if isRouteSetupPanelPresented {
            return liveDriveSetupRouteOptions
        }

        return []
    }

    private var mapAircraftMarkers: [Aircraft] {
        guard showsAircraftLayer, !aircraftLayer.isStale else { return [] }
        return AircraftPositionProjection.projectedAircraft(
            from: aircraftLayer.aircraft.filter { !$0.isStale },
            reference: passiveMapCoordinate,
            now: aircraftProjectionDate,
            staleTimeoutSeconds: aircraftStaleTimeoutSeconds
        )
    }

    private var mapEnforcementAlertMarkers: [EnforcementAlert] {
        guard areEnforcementAlertsEnabled else { return [] }
        return Array(enforcementAlerts.filter { !$0.isStale }.prefix(EnforcementAlertVisibilityPolicy.routeActiveVisibleLimit))
    }

    private var activeCameraWarning: ActiveCameraWarning? {
        guard liveDriveScreenState == .driving,
              areEnforcementAlertsEnabled,
              let coordinate = tracker.currentCoordinate ?? passiveMapCoordinate else {
            return nil
        }

        return mapEnforcementAlertMarkers
            .filter { !$0.isStale }
            .compactMap { alert -> ActiveCameraWarning? in
                let distanceFeet = coordinate.location.distance(from: alert.coordinate.location) * 3.28084
                guard let threshold = CameraAlertThreshold.current(for: distanceFeet) else { return nil }
                return ActiveCameraWarning(alert: alert, distanceFeet: distanceFeet, threshold: threshold)
            }
            .sorted { lhs, rhs in
                if lhs.distanceFeet != rhs.distanceFeet {
                    return lhs.distanceFeet < rhs.distanceFeet
                }

                return lhs.alert.id < rhs.alert.id
            }
            .first
    }

    private var mapWeatherCheckpointMarkers: [RouteWeatherMapCheckpoint] {
        guard liveDriveScreenState == .driving,
              isRouteWeatherVisible,
              !isRouteWeatherLoading,
              let routeID = fullRouteMapRoute?.id,
              routeWeatherRouteID == routeID else {
            return []
        }

        return routeWeatherEntries.compactMap { entry in
            guard entry.isForecastAvailable, let coordinate = entry.coordinate else { return nil }
            return RouteWeatherMapCheckpoint(
                id: entry.id,
                coordinate: coordinate,
                title: entry.title,
                arrivalText: entry.arrivalText,
                forecastText: entry.forecastText,
                detailText: entry.detailText,
                temperatureText: entry.temperatureText,
                systemImage: weatherChipSystemImage(for: entry.forecastText)
            )
        }
    }

    private var passiveMapCoordinate: GuidanceCoordinate? {
        if let currentCoordinate = tracker.currentCoordinate {
            return currentCoordinate
        }

        guard let coordinate = currentLocationResolver.currentPlace?.coordinate else { return nil }
        return GuidanceCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func enforcementAlertVisibilityContext(
        near coordinate: GuidanceCoordinate
    ) -> EnforcementAlertVisibilityContext {
        let routeGeometry = liveDriveScreenState == .driving
            ? liveDriveHUDRoute?.routeCoordinates.map {
                GuidanceCoordinate(latitude: $0.latitude, longitude: $0.longitude)
            } ?? []
            : []

        return EnforcementAlertVisibilityContext(
            referenceCoordinate: coordinate,
            routeGeometry: routeGeometry
        )
    }

    private var preferredNavigationProvider: NavigationProvider {
        let provider = NavigationProvider(rawValue: navigationProviderPreferenceRawValue) ?? .appleMaps
        return provider == .askEveryTime ? .appleMaps : provider
    }

    private var preferredNavigationProviderBinding: Binding<NavigationProvider> {
        Binding(
            get: { preferredNavigationProvider },
            set: { navigationProviderPreferenceRawValue = $0.rawValue }
        )
    }

    private var selectedMapMode: LiveDriveMapMode {
        LiveDriveMapMode(rawValue: mapModeRawValue) ?? .standard
    }

    private var selectedMapModeBinding: Binding<LiveDriveMapMode> {
        Binding(
            get: { selectedMapMode },
            set: { mapModeRawValue = $0.rawValue }
        )
    }

    private var selectedHUDSize: LiveDriveHUDSize {
        LiveDriveHUDSize(rawValue: hudSizeRawValue) ?? .normal
    }

    private var selectedHUDSizeBinding: Binding<LiveDriveHUDSize> {
        Binding(
            get: { selectedHUDSize },
            set: { hudSizeRawValue = $0.rawValue }
        )
    }

    private var selectedTripExportFormat: TripExportFormat {
        TripExportFormat(rawValue: defaultTripExportFormatRawValue) ?? .csv
    }

    private var selectedTripExportFormatBinding: Binding<TripExportFormat> {
        Binding(
            get: { selectedTripExportFormat },
            set: { defaultTripExportFormatRawValue = $0.rawValue }
        )
    }

    private var navigationVoiceEnabledBinding: Binding<Bool> {
        Binding(
            get: { !isVoiceGuidanceMuted },
            set: { isEnabled in
                isVoiceGuidanceMuted = !isEnabled
                guidanceEngine.setMuted(isVoiceGuidanceMuted)
            }
        )
    }

    private var keepScreenAwakeBinding: Binding<Bool> {
        Binding(
            get: { keepScreenAwake },
            set: {
                keepScreenAwake = $0
                updateIdleTimer()
            }
        )
    }

    private var liveDriveSetupRouteOptions: [RouteEstimate] {
        activeRouteOptions
    }

    private var liveDriveSetupRoute: RouteEstimate? {
        activeRouteEstimate
    }

    private var liveDriveCapturedRouteOptions: [RouteEstimate] {
        liveDriveRouteContext?.routes ?? []
    }

    private var liveDriveCapturedRoute: RouteEstimate? {
        liveDriveRouteContext?.selectedRoute
    }

    private var liveDriveBaselineETAMinutes: Double {
        if isRouteFreeLoggingMode {
            return 0
        }

        if let liveDriveRouteContext, liveDriveRouteContext.baselineRouteETAMinutes > 0 {
            return liveDriveRouteContext.baselineRouteETAMinutes
        }

        if tracker.configuration.baselineRouteETAMinutes > 0 {
            return tracker.configuration.baselineRouteETAMinutes
        }

        return liveDriveSetupRoute?.expectedTravelMinutes ?? 0
    }

    private var liveDriveBaselineDistanceMiles: Double {
        if isRouteFreeLoggingMode {
            return 0
        }

        if let liveDriveRouteContext, liveDriveRouteContext.baselineRouteDistanceMiles > 0 {
            return liveDriveRouteContext.baselineRouteDistanceMiles
        }

        if tracker.configuration.baselineRouteDistanceMiles > 0 {
            return tracker.configuration.baselineRouteDistanceMiles
        }

        return liveDriveSetupRoute?.distanceMiles ?? 0
    }

    private var liveDriveBaselineSpeed: Double {
        let baselineDistanceMiles = liveDriveBaselineDistanceMiles
        let baselineRouteETAMinutes = liveDriveBaselineETAMinutes

        if baselineDistanceMiles > 0, baselineRouteETAMinutes > 0 {
            return baselineDistanceMiles / (baselineRouteETAMinutes / 60)
        }

        return 55
    }

    private var liveDriveDisplayedTimeSaved: Double {
        liveDriveFinishedTrip?.timeSavedBySpeeding ?? tracker.tripSummary.timeSavedBySpeeding
    }

    private var liveDriveDisplayedTimeLost: Double {
        liveDriveFinishedTrip?.timeLostBelowTargetPace ?? tracker.tripSummary.timeLostBelowTargetPace
    }

    private var liveDriveSpeedLimitMeasuredMinutes: Double {
        liveDriveFinishedTrip?.speedLimitMeasuredMinutes ?? tracker.analysisResult.speedLimitMeasuredMinutes
    }

    private var liveDriveHasSpeedLimitAnalysis: Bool {
        liveDriveSpeedLimitMeasuredMinutes > 0
    }

    private var liveDriveDisplayedTimeAboveSpeedLimitText: String {
        liveDriveHasSpeedLimitAnalysis ? Self.durationString(liveDriveDisplayedTimeSaved) : "—"
    }

    private var liveDriveDisplayedTimeBelowSpeedLimitText: String {
        liveDriveHasSpeedLimitAnalysis ? Self.durationString(liveDriveDisplayedTimeLost) : "—"
    }

    private var liveDriveDisplayedNetTimeGain: Double {
        liveDriveFinishedTrip?.netTimeGain ?? tracker.tripSummary.netTimeGain
    }

    private var liveDriveConfigurationForStart: LiveDriveConfiguration? {
        guard
            let route = activeRouteEstimate,
            !routeNeedsRefresh
        else {
            return nil
        }

        return LiveDriveConfiguration(
            baselineRouteETAMinutes: route.expectedTravelMinutes,
            baselineRouteDistanceMiles: route.distanceMiles
        )
    }

    private var liveDrivePermissionMessage: String? {
        switch tracker.permissionState {
        case .denied:
            return "Turn on Location Access in Settings to measure speed and distance."
        case .restricted:
            return "This device restricts Location Access, so TimeThrottle cannot measure speed or distance."
        case .authorizedAlways, .authorizedWhenInUse, .notDetermined:
            return nil
        }
    }

    private var liveDriveShowsSettingsAction: Bool {
        guard tracker.permissionState.requiresSettingsAction,
              let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return false
        }

        return UIApplication.shared.canOpenURL(settingsURL)
    }

    private var liveDriveBackgroundContinuityMessage: String? {
        switch tracker.permissionState {
        case .authorizedAlways, .denied, .restricted:
            return nil
        case .authorizedWhenInUse:
            return "Allow Always Location to keep tracking active while another navigation app is open."
        case .notDetermined:
            return "External navigation needs Always Location so tracking can continue in the background."
        }
    }

    private var liveDriveShowsBackgroundContinuitySettingsAction: Bool {
        guard tracker.permissionState == .authorizedWhenInUse,
              let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return false
        }

        return UIApplication.shared.canOpenURL(settingsURL)
    }

    private var liveDriveNavigationProviderHelperText: String {
        "\(preferredNavigationProvider.rawValue) handoff ready."
    }

    private var liveDriveOverallResultTitle: String {
        isRouteFreeLoggingMode ? "Trip metrics" : "Overall vs Apple ETA"
    }

    private var liveDriveGainSummaryText: String {
        guard liveDriveHasSpeedLimitAnalysis else {
            return "Waiting for an OpenStreetMap speed-limit estimate"
        }

        return "\(Self.durationString(liveDriveDisplayedTimeSaved)) measured above available speed-limit estimates"
    }

    private var liveDriveBelowTargetSummaryText: String {
        guard liveDriveHasSpeedLimitAnalysis else {
            return "Waiting for an OpenStreetMap speed-limit estimate"
        }

        return "\(Self.durationString(liveDriveDisplayedTimeLost)) measured below available speed-limit estimates"
    }

    private var liveDriveProjectedTravelMinutes: Double {
        tracker.analysisResult.projectedTravelMinutes
    }

    private var liveDriveProjectedTravelLabel: String {
        liveDriveProjectedTravelMinutes > 0
            ? Self.durationString(liveDriveProjectedTravelMinutes)
            : "Collecting pace"
    }

    private var liveDriveComparisonScaleMinutes: Double {
        max(1, max(liveDriveBaselineETAMinutes, liveDriveProjectedTravelMinutes))
    }

    private var liveDriveProjectedTravelTint: Color {
        guard liveDriveProjectedTravelMinutes > 0 else { return Palette.cocoa }

        if liveDriveBaselineETAMinutes > 0, liveDriveProjectedTravelMinutes <= liveDriveBaselineETAMinutes {
            return Palette.success
        }

        return Palette.danger
    }

    private var liveDriveHUDAverageSpeed: Double {
        if tracker.tripDuration > 0 {
            return tracker.distanceTraveled / (tracker.tripDuration / 60)
        }

        return tracker.analysisResult.averageTripSpeed
    }

    private var liveDriveHUDAverageSpeedValue: String {
        liveDriveHUDAverageSpeed > 0
            ? "\(Self.speedString(liveDriveHUDAverageSpeed)) mph"
            : "—"
    }

    private var liveDriveTopSpeedText: String {
        if let finishedTopSpeed = liveDriveFinishedTrip?.topSpeedMPH {
            return Self.topSpeedString(finishedTopSpeed)
        }

        return Self.topSpeedString(tracker.topSpeed)
    }

    private var liveDriveHUDAppleETAValue: String {
        liveDriveBaselineETAMinutes > 0
            ? Self.durationString(liveDriveBaselineETAMinutes)
            : "—"
    }

    private var liveDriveHUDLiveETAValue: String {
        if tracker.expectedArrivalTime != nil {
            return liveDriveExpectedArrivalText
        }

        if liveDriveProjectedTravelMinutes > 0 {
            return liveDriveProjectedTravelLabel
        }

        return "Collecting"
    }

    private var liveDriveHUDLiveETADetail: String {
        if tracker.expectedArrivalTime != nil {
            if abs(liveDriveDisplayedNetTimeGain) < 0.01 {
                return "on Apple ETA"
            }

            let delta = Self.durationString(abs(liveDriveDisplayedNetTimeGain))
            return liveDriveDisplayedNetTimeGain > 0
                ? "\(delta) ahead of Apple ETA"
                : "\(delta) behind Apple ETA"
        }

        if liveDriveProjectedTravelMinutes > 0 {
            return "projected at current pace"
        }

        return "projected arrival"
    }

    private var liveDriveControlsSubtitle: String {
        switch liveDriveScreenState {
        case .setup:
            return "Capture the route baseline and start tracking."
        case .driving:
            return tracker.isPaused
                ? "Resume the same trip or end it without losing the finished result."
                : "Tracking against the Apple Maps ETA baseline."
        case .tripComplete:
            return "Your finished trip stays here until you start a new one."
        }
    }

    private var heroSubtitle: String {
        switch liveDriveScreenState {
        case .setup:
            return ""
        case .driving:
            return ""
        case .tripComplete:
            return ""
        }
    }

    private var baselineSummaryTitle: String {
        "Apple Maps ETA"
    }

    private var routeStatusText: String {
        if isCalculatingRoute {
            return "Calculating route..."
        }

        if routeOriginInputMode == .currentLocation {
            if currentLocationResolver.isResolving && currentLocationResolver.currentPlace == nil {
                return "Finding your current location..."
            }

            if let errorMessage = currentLocationResolver.errorMessage {
                return errorMessage
            }
        }

        if let route = activeRouteEstimate {
            let optionsLabel = activeRouteOptions.count == 1 ? "1 route ready" : "\(activeRouteOptions.count) routes ready"
            return "\(optionsLabel) • Selected: \(Self.milesString(route.distanceMiles)) mi • \(Self.durationString(route.expectedTravelMinutes))"
        }

        if let routeErrorMessage {
            return routeErrorMessage
        }

        return ""
    }

    private var routeStatusForeground: Color {
        if isPolishedLiveDriveSetup {
            if isCalculatingRoute {
                return setupSecondaryText
            }

            if routeOriginInputMode == .currentLocation, currentLocationResolver.errorMessage != nil {
                return Color(red: 1.00, green: 0.77, blue: 0.77)
            }

            if activeRouteEstimate != nil {
                return setupPrimaryText
            }

            if routeErrorMessage != nil {
                return Color(red: 1.00, green: 0.77, blue: 0.77)
            }

            return setupSecondaryText
        }

        if isCalculatingRoute {
            return Palette.cocoa
        }

        if routeOriginInputMode == .currentLocation, currentLocationResolver.errorMessage != nil {
            return Palette.danger
        }

        if activeRouteEstimate != nil {
            return Palette.ink
        }

        if routeErrorMessage != nil {
            return Palette.danger
        }

        return Palette.cocoa
    }

    private var routeStatusBackground: Color {
        if isPolishedLiveDriveSetup {
            if routeOriginInputMode == .currentLocation, currentLocationResolver.errorMessage != nil {
                return setupErrorFill
            }

            if activeRouteEstimate != nil {
                return setupChipFill
            }

            if routeErrorMessage != nil {
                return setupErrorFill
            }

            return setupSurfaceMuted
        }

        if routeOriginInputMode == .currentLocation, currentLocationResolver.errorMessage != nil {
            return Palette.dangerBackground
        }

        if activeRouteEstimate != nil {
            return Palette.successBackground
        }

        if routeErrorMessage != nil {
            return Palette.dangerBackground
        }

        return Palette.panelAlt
    }

    private var routeStatusBorder: Color {
        if routeOriginInputMode == .currentLocation, currentLocationResolver.errorMessage != nil || routeErrorMessage != nil {
            return setupErrorBorder
        }

        if activeRouteEstimate != nil {
            return setupChipBorder
        }

        return setupPanelBorder
    }

    private var isCalculateRouteDisabled: Bool {
        isCalculatingRoute || routeSourceEndpoint == nil || routeDestinationEndpoint == nil
    }

    private var shouldShowRouteStatus: Bool {
        isCalculatingRoute || activeRouteEstimate != nil || routeErrorMessage != nil
    }

    private var isStartLiveDriveDisabled: Bool {
        isCalculatingRoute ||
        liveDriveConfigurationForStart == nil ||
        tracker.permissionState == .denied ||
        tracker.permissionState == .restricted
    }

    public var body: some View {
        bodyWithSheets
    }

    private var rootPlatformView: some View {
        PlatformLayout {
            mapFirstRoot
        }
    }

    private var bodyWithCoreObservers: some View {
        rootPlatformView
        .task {
            handleInitialViewTask()
        }
        .onChange(of: routeOriginInputMode) { _, newMode in
            handleRouteOriginInputModeChanged(newMode)
        }
        .onChange(of: fromAddressText) { _, newValue in
            handleFromAddressTextChanged(newValue)
        }
        .onChange(of: toAddressText) { _, newValue in
            handleToAddressTextChanged(newValue)
        }
        .onChange(of: focusedRouteAddressField) { _, newField in
            handleFocusedRouteAddressFieldChanged(newField)
        }
        .onChange(of: tracker.isTracking) { _, isTracking in
            handleTrackingStateChanged(isTracking)
        }
        .onChange(of: tracker.distanceTraveled) { _, newDistance in
            handleDistanceTraveledChanged(newDistance)
        }
        .onChange(of: tracker.currentCoordinate) { _, newCoordinate in
            handleCurrentCoordinateChanged(newCoordinate)
        }
        .onReceive(aircraftRefreshPublisher) { _ in
            handleAircraftRefreshTick()
        }
        .onReceive(aircraftProjectionPublisher) { _ in
            handleAircraftProjectionTick()
        }
        .onReceive(enforcementAlertRefreshPublisher) { _ in
            handleEnforcementAlertRefreshTick()
        }
        .onChange(of: areEnforcementAlertsEnabled) { _, isEnabled in
            handleEnforcementAlertsEnabledChanged(isEnabled)
        }
        .onChange(of: areRedLightCameraAlertsEnabled) { _, _ in
            handleEnforcementAlertFilterChanged()
        }
        .onChange(of: areEnforcementReportAlertsEnabled) { _, _ in
            handleEnforcementAlertFilterChanged()
        }
        .onChange(of: liveDriveScreenState) { _, newState in
            handleLiveDriveScreenStateChanged(newState)
        }
        .onChange(of: currentLocationResolver.currentPlace) { _, _ in
            handleCurrentLocationPlaceChanged()
        }
        .onChange(of: tracker.permissionState) { _, newState in
            handleTrackerPermissionStateChanged(newState)
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChanged(newPhase)
        }
    }

    #if os(iOS)
    private var bodyWithSheets: some View {
        bodyWithCoreObservers
        .sheet(isPresented: $isShareSheetPresented) {
            ShareSheet(activityItems: shareSheetItems)
        }
        .sheet(isPresented: $isMapOptionsPresented) {
            mapOptionsSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $presentedSheetDestination) { destination in
            switch destination {
            case .tripHistory:
                TripHistoryScreen(
                    store: tripHistoryStore,
                    brandLogo: brandLogo,
                    resultBrandLogo: resultBrandLogo
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .scanner:
                ScannerTabView(viewModel: scannerViewModel, showsCloseButton: true)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $isVoiceSelectionPresented) {
            VoiceSelectionSheet(
                voiceState: liveDriveHUDVoiceState,
                onSelectVoice: { identifier in
                    selectGuidanceVoice(identifier)
                },
                onTestVoice: {
                    guidanceEngine.speakTestPrompt()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: isNavigationProviderChoicePresented) { _, isPresented in
            if isPresented {
                isRouteSetupPanelPresented = true
            } else if liveDriveScreenState == .driving {
                isRouteSetupPanelPresented = false
            }
        }
        .confirmationDialog(
            "Choose navigation app",
            isPresented: $isNavigationProviderChoicePresented,
            titleVisibility: .visible
        ) {
            Button(NavigationProvider.appleMaps.rawValue) {
                completeLiveDriveNavigationHandoff(using: .appleMaps)
            }

            Button(NavigationProvider.googleMaps.rawValue) {
                completeLiveDriveNavigationHandoff(using: .googleMaps)
            }

            Button(NavigationProvider.waze.rawValue) {
                completeLiveDriveNavigationHandoff(using: .waze)
            }

            Button("Cancel", role: .cancel) {
                liveDriveNavigationProviderPending = nil
            }
        } message: {
            Text("TimeThrottle starts tracking first, then opens your chosen navigation app.")
        }
    }
    #else
    private var bodyWithSheets: some View {
        bodyWithCoreObservers
    }
    #endif

    private func handleInitialViewTask() {
        applyStoredVoiceSettings()
        migrateNavigationProviderPreferenceIfNeeded()

        if routeOriginInputMode == .currentLocation {
            currentLocationResolver.requestCurrentLocationIfNeeded()
        }

        guard shouldRunCaptureBootstrap, !didRunCaptureBootstrap else { return }
        didRunCaptureBootstrap = true
        calculateAppleMapsRoute()
    }

    private func handleRouteOriginInputModeChanged(_ newMode: RouteOriginInputMode) {
        focusedRouteAddressField = nil
        autocompleteController.clear()
        resetCalculatedRouteState()

        if newMode == .currentLocation {
            currentLocationResolver.requestCurrentLocationIfNeeded()
        }
    }

    private func handleFocusedRouteAddressFieldChanged(_ newField: RouteAddressField?) {
        guard let newField else {
            autocompleteController.clear()
            return
        }

        switch newField {
        case .from:
            if routeOriginInputMode == .custom {
                autocompleteController.updateQuery(fromAddressText, for: .from)
            }
        case .to:
            autocompleteController.updateQuery(toAddressText, for: .to)
        }
    }

    private func handleTrackingStateChanged(_ isTracking: Bool) {
        updateIdleTimer()
        if isTracking {
            processLiveDriveNavigationHandoffIfNeeded()
        }
    }

    private func updateIdleTimer() {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake && (tracker.isTracking || tracker.isPaused)
        #endif
    }

    private func handleDistanceTraveledChanged(_ newDistance: Double) {
        guidanceEngine.update(progressDistanceMeters: newDistance * 1_609.344)

        if let currentCoordinate = tracker.currentCoordinate {
            guidanceEngine.update(currentLocation: currentCoordinate)
        }
    }

    private func handleCurrentCoordinateChanged(_ newCoordinate: GuidanceCoordinate?) {
        guard let newCoordinate else { return }
        guidanceEngine.update(currentLocation: newCoordinate)
        refreshSpeedLimitIfNeeded(near: newCoordinate)
        refreshAircraftIfNeeded(near: newCoordinate)
        refreshEnforcementAlertsIfNeeded(near: newCoordinate)
        refreshCurrentWeatherIfNeeded(near: newCoordinate)
        speakCameraWarningIfNeeded()
        speakAircraftCueIfNeeded(now: Date())
        requestGuidanceRerouteIfNeeded(from: newCoordinate)
    }

    private func handleEnforcementAlertsEnabledChanged(_ isEnabled: Bool) {
        if isEnabled, let coordinate = tracker.currentCoordinate {
            refreshEnforcementAlerts(near: coordinate, force: true)
        } else if isEnabled, let coordinate = passiveMapCoordinate {
            refreshEnforcementAlerts(near: coordinate, force: true)
        } else if isEnabled {
            enforcementAlertStatusText = "Waiting for location"
        } else {
            enforcementAlerts = []
            enforcementAlertStatusText = "Off"
            enforcementAlertsLastUpdatedAt = nil
            lastEnforcementAlertLookupCoordinate = nil
            lastEnforcementAlertRouteContextID = nil
            spokenCameraAlertThresholds = [:]
        }
    }

    private func handleEnforcementAlertFilterChanged() {
        guard areEnforcementAlertsEnabled else { return }
        enforcementAlerts = EnforcementAlertVisibilityPolicy.filteredAlerts(
            from: enforcementAlerts,
            redLightCameraAlertsEnabled: areRedLightCameraAlertsEnabled,
            enforcementReportAlertsEnabled: areEnforcementReportAlertsEnabled
        )

        if let coordinate = tracker.currentCoordinate ?? passiveMapCoordinate {
            refreshEnforcementAlerts(near: coordinate, force: true)
        }
    }

    private func handleLiveDriveScreenStateChanged(_ newState: LiveDriveScreenState) {
        switch newState {
        case .driving:
            isRouteSetupPanelPresented = false
        case .setup, .tripComplete:
            prepareInactiveMapIfNeeded(forceRefresh: false)
        }
    }

    private func handleCurrentLocationPlaceChanged() {
        refreshPassiveMapLayersIfPossible(force: false)
    }

    private func handleTrackerPermissionStateChanged(_ newState: LiveDrivePermissionState) {
        if newState == .denied || newState == .restricted {
            liveDriveNavigationProviderPending = nil
            isNavigationProviderChoicePresented = false
        } else if newState == .authorizedAlways, tracker.isTracking {
            processLiveDriveNavigationHandoffIfNeeded()
        }
    }

    private func handleScenePhaseChanged(_ newPhase: ScenePhase) {
        guard newPhase == .active else { return }
        tracker.refreshAuthorizationState()
        currentLocationResolver.refreshAuthorizationState()

        currentLocationResolver.requestCurrentLocationIfNeeded()
        refreshPassiveMapLayersIfPossible(force: false)

        if tracker.isTracking {
            processLiveDriveNavigationHandoffIfNeeded()
        }
    }

    private var mapFirstRoot: some View {
        ZStack {
            if liveDriveScreenState == .driving {
                if let route = fullRouteMapRoute {
                    fullRouteMapContent(route: route)
                } else {
                    routeFreeMapContent
                }
            } else {
                mapFirstInactiveContent
            }
        }
        .tint(Palette.success)
    }

    private var mapFirstInactiveContent: some View {
        ZStack(alignment: .top) {
            mapFirstInactiveLayer
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)

                    if let weatherChipContent = mapWeatherChipContent {
                        mapWeatherChip(weatherChipContent)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)

                Spacer(minLength: 0)

                mapFirstBottomPanel
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .background(setupBackgroundTop.ignoresSafeArea())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var mapFirstInactiveLayer: some View {
        if let route = routeSetupMapRoute {
            fullRouteMapLayer(route: route)
        } else {
            inactiveMapLayer
        }
    }

    @ViewBuilder
    private var mapFirstBottomPanel: some View {
        switch liveDriveScreenState {
        case .setup:
            if isRouteSetupPanelPresented {
                routeSetupMapPanel
            } else {
                idleMapBottomPanel
            }
        case .tripComplete:
            tripCompleteMapPanel
        case .driving:
            EmptyView()
        }
    }

    private var routeSetupMapRoute: RouteEstimate? {
        guard isRouteSetupPanelPresented else { return nil }
        return liveDriveSetupRoute
    }

    private var idleMapBottomPanel: some View {
        mapFirstPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: inactiveMapStatusSystemImage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(inactiveMapStatusTint)
                        .frame(width: 34, height: 34)
                        .background(setupSurfaceMuted, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(inactiveMapStatusTitle)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(setupPrimaryText)

                        Text(inactiveMapStatusMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(setupSecondaryText)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    mapMenuIconButton
                }

                HStack(spacing: 10) {
                    Button {
                        openRouteSetupPanel()
                    } label: {
                        Label("Choose Route", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Palette.success, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        startRouteFreeLogging()
                    } label: {
                        Label("Log Trip", systemImage: "record.circle")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(setupPrimaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(setupSurfaceMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(setupPanelBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(tracker.permissionState == .denied || tracker.permissionState == .restricted)
                    .opacity((tracker.permissionState == .denied || tracker.permissionState == .restricted) ? 0.55 : 1)
                }
            }
        }
    }

    private var routeSetupMapPanel: some View {
        mapFirstPanel(maxHeight: 650) {
            VStack(alignment: .leading, spacing: 12) {
                mapPanelGrabber

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Choose Route")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(setupPrimaryText)

                        Text("Pick a destination and keep the map in view.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(setupSecondaryText)
                    }

                    Spacer(minLength: 8)

                    mapMenuIconButton

                    Button("Done") {
                        isRouteSetupPanelPresented = false
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(setupPrimaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(setupSurfaceMuted, in: Capsule())
                    .buttonStyle(.plain)
                }

                ScrollView(.vertical, showsIndicators: true) {
                    liveDriveSetupSection
                        .padding(.bottom, 2)
                }
                .frame(maxHeight: 560)
            }
        }
    }

    private var tripCompleteMapPanel: some View {
        mapFirstPanel(maxHeight: 650) {
            VStack(alignment: .leading, spacing: 12) {
                mapPanelGrabber

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Trip Complete")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(setupPrimaryText)

                        Text("Review, share, or start the next drive.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(setupSecondaryText)
                    }

                    Spacer(minLength: 8)

                    mapMenuIconButton
                }

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        liveDriveFinishedResultSection
                        tripCompleteMapActions
                    }
                    .padding(.bottom, 2)
                }
                .frame(maxHeight: 560)
            }
        }
    }

    private var tripCompleteMapActions: some View {
        HStack(spacing: 10) {
            Button {
                presentTripHistorySheet()
            } label: {
                Label("Trip History", systemImage: "clock.arrow.circlepath")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(setupPrimaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(setupSurfaceMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(setupPanelBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            Button {
                startNewLiveDrive()
            } label: {
                Label("New Trip", systemImage: "plus.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Palette.success, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var mapPanelGrabber: some View {
        Capsule()
            .fill(setupSecondaryText.opacity(0.35))
            .frame(width: 46, height: 5)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
    }

    private var mapMenuIconButton: some View {
        Button {
            isMapOptionsPresented = true
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(setupPrimaryText)
                .frame(width: 42, height: 38)
                .background(setupSurfaceMuted, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(setupPanelBorder, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open menu")
    }

    private func mapFirstPanel<Content: View>(
        maxHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: maxHeight)
            .background(setupSurface.opacity(0.95), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(setupPanelBorder, lineWidth: 1)
            }
            .shadow(color: setupShadowColor, radius: 24, y: 12)
    }

    private var routeFreeMapContent: some View {
        ZStack(alignment: .top) {
            inactiveMapLayer
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                freeDriveStatusOverlay
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .scaleEffect(selectedHUDSize.scale, anchor: .top)

                HStack {
                    Spacer(minLength: 0)

                    if let weatherChipContent = mapWeatherChipContent {
                        mapWeatherChip(weatherChipContent)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                Spacer(minLength: 0)

                routeFreeMapBottomDock
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .scaleEffect(selectedHUDSize.scale, anchor: .bottom)
            }
        }
        .background(setupBackgroundTop.ignoresSafeArea())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inactiveMapContent: some View {
        ZStack(alignment: .top) {
            inactiveMapLayer
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)

                    if let weatherChipContent = mapWeatherChipContent {
                        mapWeatherChip(weatherChipContent)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)

                Spacer(minLength: 0)

                inactiveMapBottomOverlay
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .scaleEffect(selectedHUDSize.scale, anchor: .bottom)
            }
        }
        .background(setupBackgroundTop.ignoresSafeArea())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var inactiveMapLayer: some View {
        #if os(iOS)
        LiveDriveHUDMapView(
            routes: [],
            selectedRouteID: nil,
            aircraft: mapAircraftMarkers,
            enforcementAlerts: mapEnforcementAlertMarkers,
            weatherCheckpoints: [],
            mapMode: selectedMapMode
        )
        #else
        mapPreview([], nil)
        #endif
    }

    private var inactiveMapBottomOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
            Image(systemName: inactiveMapStatusSystemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(inactiveMapStatusTint)
                .frame(width: 34, height: 34)
                .background(setupSurfaceMuted, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(inactiveMapStatusTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(setupPrimaryText)

                Text(inactiveMapStatusMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(setupSecondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button {
                isMapOptionsPresented = true
            } label: {
                Label("Menu", systemImage: "line.3.horizontal")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(setupPrimaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(setupSurfaceMuted, in: Capsule())
                    .accessibilityLabel("Open menu")
            }
            .buttonStyle(.plain)
            }

            Button {
                startRouteFreeLogging()
            } label: {
                Label("Log Trip", systemImage: "record.circle")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Palette.success, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(tracker.permissionState == .denied || tracker.permissionState == .restricted)
            .opacity((tracker.permissionState == .denied || tracker.permissionState == .restricted) ? 0.55 : 1)
        }
        .padding(12)
        .background(setupSurface.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(setupPanelBorder, lineWidth: 1)
        }
        .shadow(color: setupShadowColor, radius: 22, y: 10)
    }

    private var freeDriveStatusOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: tracker.isPaused ? "pause.fill" : "record.circle")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tracker.isPaused ? Color.orange : Palette.success)
                    .frame(width: 38, height: 38)
                    .background(setupSurfaceMuted, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(tracker.isPaused ? "Free Drive paused" : "Logging Free Drive")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(setupPrimaryText)

                    Text("\(Self.milesString(tracker.distanceTraveled)) mi • \(Self.durationString(tracker.tripDuration))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(setupSecondaryText)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                mapOverlayMetric(title: "Speed", value: "\(Self.speedString(tracker.currentSpeed)) mph")
                mapOverlayMetric(title: "Limit", value: speedLimitDisplayText)
                mapOverlayMetric(title: "Avg", value: liveDriveHUDAverageSpeedValue)
                mapOverlayMetric(title: "Top", value: liveDriveTopSpeedText)
            }

            HStack(spacing: 8) {
                mapOverlayMetric(title: "Distance", value: "\(Self.milesString(tracker.distanceTraveled)) mi")
                mapOverlayMetric(title: "Elapsed", value: Self.durationString(tracker.tripDuration))
                mapOverlayMetric(title: "Above", value: liveDriveDisplayedTimeAboveSpeedLimitText)
                mapOverlayMetric(title: "Below", value: liveDriveDisplayedTimeBelowSpeedLimitText)
            }
        }
        .padding(12)
        .background(setupSurface.opacity(0.88), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(setupPanelBorder, lineWidth: 1)
        }
    }

    private var routeFreeMapBottomDock: some View {
        HStack(spacing: 10) {
            Button {
                isMapOptionsPresented = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(setupPrimaryText)
                    .frame(width: 54)
                    .padding(.vertical, 12)
                    .background(setupSurfaceMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open menu")

            Button {
                if tracker.isPaused {
                    resumeLiveDrive()
                } else {
                    pauseLiveDrive()
                }
            } label: {
                Label(tracker.isPaused ? "Resume" : "Pause", systemImage: tracker.isPaused ? "play.fill" : "pause.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background((tracker.isPaused ? Palette.success : Color.orange), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                endLiveDrive()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Palette.danger, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(setupSurface.opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(setupPanelBorder, lineWidth: 1)
        }
        .shadow(color: setupShadowColor, radius: 22, y: 10)
    }

    private var inactiveMapStatusTitle: String {
        switch currentLocationResolver.authorizationStatus {
        case .denied, .restricted:
            return "Location unavailable"
        case .notDetermined:
            return "Map ready"
        case .authorizedAlways, .authorizedWhenInUse:
            return "Map ready"
        @unknown default:
            return "Map ready"
        }
    }

    private var inactiveMapStatusMessage: String {
        switch currentLocationResolver.authorizationStatus {
        case .denied:
            return "Enable location access to show your position and nearby passive layers."
        case .restricted:
            return "Location access is restricted, so nearby passive layers may be unavailable."
        case .notDetermined:
            return "Allow location access to show your position. Start a drive to add route guidance and trip tracking."
        case .authorizedAlways, .authorizedWhenInUse:
            return "Start a drive to add route guidance and trip tracking."
        @unknown default:
            return "Start a drive to add route guidance and trip tracking."
        }
    }

    private var inactiveMapStatusSystemImage: String {
        switch currentLocationResolver.authorizationStatus {
        case .denied, .restricted:
            return "location.slash.fill"
        case .notDetermined, .authorizedAlways, .authorizedWhenInUse:
            return "map.fill"
        @unknown default:
            return "map.fill"
        }
    }

    private var inactiveMapStatusTint: Color {
        switch currentLocationResolver.authorizationStatus {
        case .denied, .restricted:
            return Palette.danger
        case .notDetermined, .authorizedAlways, .authorizedWhenInUse:
            return Palette.success
        @unknown default:
            return Palette.success
        }
    }

    private func fullRouteMapContent(route: RouteEstimate) -> some View {
        ZStack(alignment: .top) {
            fullRouteMapLayer(route: route)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                fullRouteMapGuidanceOverlay(route: route)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .scaleEffect(selectedHUDSize.scale, anchor: .top)

                HStack {
                    Spacer(minLength: 0)

                    if let weatherChipContent = mapWeatherChipContent {
                        mapWeatherChip(weatherChipContent)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                HStack {
                    Spacer(minLength: 0)

                    if let aircraft = nearestMapAircraft {
                        nearestAircraftBar(aircraft)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                if let warning = activeCameraWarning {
                    cameraWarningBar(warning)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                }

                Spacer(minLength: 0)

                fullRouteMapBottomOverlay(route: route)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .scaleEffect(selectedHUDSize.scale, anchor: .bottom)
            }
        }
        .background(setupBackgroundTop.ignoresSafeArea())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func fullRouteMapLayer(route: RouteEstimate) -> some View {
        #if os(iOS)
        LiveDriveHUDMapView(
            routes: fullRouteMapRoutes,
            selectedRouteID: route.id,
            aircraft: mapAircraftMarkers,
            enforcementAlerts: mapEnforcementAlertMarkers,
            weatherCheckpoints: mapWeatherCheckpointMarkers,
            mapMode: selectedMapMode
        )
        #else
        mapPreview(fullRouteMapRoutes, route.id)
        #endif
    }

    private func fullRouteMapGuidanceOverlay(route: RouteEstimate) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: guidanceEngine.state.isOffRoute ? "exclamationmark.triangle.fill" : "arrow.turn.up.right")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(guidanceEngine.state.isOffRoute ? Palette.danger : Palette.success)
                    .frame(width: 34, height: 34)
                    .background(setupSurfaceMuted, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(guidanceRerouteHUDText ?? guidanceEngine.state.nextInstruction ?? "Route guidance powered by Apple Maps route data.")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(setupPrimaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(guidanceEngine.state.distanceToNextManeuverMeters.map(Self.guidanceDistanceString) ?? fullRouteMapRouteLabel(route))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(setupSecondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    toggleVoiceGuidanceMute()
                } label: {
                    Image(systemName: guidanceEngine.state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(setupPrimaryText)
                        .frame(width: 34, height: 34)
                        .background(setupSurfaceMuted, in: Circle())
                }
                .buttonStyle(.plain)
            }

            Text("Speed limit estimate where available.")
                .font(.caption.weight(.medium))
                .foregroundStyle(setupTertiaryText)
        }
        .padding(12)
        .background(setupSurface.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(setupPanelBorder, lineWidth: 1)
        }
        .shadow(color: setupShadowColor, radius: 22, y: 10)
    }

    private var mapWeatherChipContent: MapWeatherChipContent? {
        guard liveDriveScreenState == .driving || routeWeatherOptionsRoute == nil else { return nil }
        guard isRouteWeatherVisible, !isRouteWeatherLoading else { return nil }
        let entry: RouteWeatherDisplayEntry?
        if routeWeatherOptionsRoute == nil {
            guard !isCurrentWeatherLoading else { return nil }
            entry = currentWeatherEntry
        } else {
            entry = routeWeatherEntries.first(where: { $0.temperatureText?.isEmpty == false })
        }
        guard let entry else { return nil }
        guard let temperatureText = entry.temperatureText else { return nil }

        return MapWeatherChipContent(
            systemImage: weatherChipSystemImage(for: entry.forecastText),
            temperatureText: temperatureText,
            aqiText: entry.aqiText
        )
    }

    private func mapWeatherChip(_ content: MapWeatherChipContent) -> some View {
        HStack(spacing: 7) {
            Image(systemName: content.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.yellow, Color.white.opacity(0.92), Palette.success)
                .frame(width: 20, height: 20)

            Text(content.temperatureText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(setupPrimaryText)

            if let aqiText = content.aqiText {
                Text(aqiText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(setupSecondaryText)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .background(setupSurface.opacity(0.78), in: Capsule())
        .overlay {
            Capsule()
                .stroke(setupPanelBorder, lineWidth: 1)
        }
        .shadow(color: setupShadowColor, radius: 14, y: 8)
        .accessibilityLabel(weatherChipAccessibilityLabel(content))
    }

    private func weatherChipAccessibilityLabel(_ content: MapWeatherChipContent) -> String {
        [content.temperatureText, content.aqiText]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func weatherChipSystemImage(for forecastText: String) -> String {
        let text = forecastText.lowercased()

        if text.contains("thunder") || text.contains("storm") {
            return "cloud.bolt.rain.fill"
        }

        if text.contains("rain") || text.contains("drizzle") {
            return "cloud.rain.fill"
        }

        if text.contains("snow") || text.contains("sleet") {
            return "cloud.snow.fill"
        }

        if text.contains("cloud") || text.contains("overcast") {
            return "cloud.sun.fill"
        }

        if text.contains("clear") || text.contains("sun") {
            return "sun.max.fill"
        }

        return "cloud.sun.fill"
    }

    private var nearestMapAircraft: Aircraft? {
        guard showsAircraftLayer, !aircraftLayer.isStale else { return nil }
        return aircraftLayer.aircraft
            .filter { !$0.isStale }
            .sorted { lhs, rhs in
                (lhs.distanceMiles ?? .greatestFiniteMagnitude) < (rhs.distanceMiles ?? .greatestFiniteMagnitude)
            }
            .first
    }

    private func nearestAircraftBar(_ aircraft: Aircraft) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "airplane")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white)
                .frame(width: 26, height: 26)
                .background(Palette.success.opacity(0.82), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("NEARBY AIRCRAFT")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(setupSecondaryText)

                HStack(spacing: 6) {
                    Text(aircraft.callsign.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Aircraft" : aircraft.callsign)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(setupPrimaryText)

                    Text(nearestAircraftDistanceText(aircraft))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(setupPrimaryText)

                    Text(nearestAircraftAltitudeText(aircraft))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(setupSecondaryText)

                    if let heading = aircraft.headingDegrees {
                        Image(systemName: "arrow.up")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(setupSecondaryText)
                            .rotationEffect(.degrees(heading))
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(setupSurface.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.success.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: setupShadowColor, radius: 14, y: 8)
        .accessibilityLabel(nearestAircraftAccessibilityLabel(aircraft))
    }

    private func nearestAircraftDistanceText(_ aircraft: Aircraft) -> String {
        guard let distanceMiles = aircraft.distanceMiles else { return "Nearby" }
        return "\(String(format: "%.1f", distanceMiles)) mi"
    }

    private func nearestAircraftAltitudeText(_ aircraft: Aircraft) -> String {
        guard let altitudeFeet = aircraft.altitudeFeet else { return "Alt —" }
        return "\(Int(altitudeFeet.rounded())) ft"
    }

    private func nearestAircraftAccessibilityLabel(_ aircraft: Aircraft) -> String {
        let callsign = aircraft.callsign.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "Low aircraft",
            callsign.isEmpty ? nil : callsign,
            nearestAircraftDistanceText(aircraft),
            nearestAircraftAltitudeText(aircraft)
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private func cameraWarningBar(_ warning: ActiveCameraWarning) -> some View {
        HStack(spacing: 9) {
            Image(systemName: cameraWarningSystemImage(for: warning.alert))
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .background(cameraWarningTint(for: warning).opacity(0.92), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(warning.threshold.emphasisTitle.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(setupSecondaryText)

                HStack(spacing: 6) {
                    Text(cameraWarningTitle(for: warning.alert))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(setupPrimaryText)

                    Text(warning.distanceText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(setupPrimaryText)
                }
            }

            Spacer(minLength: 8)

            Text("Reports vary")
                .font(.caption2.weight(.bold))
                .foregroundStyle(setupSecondaryText)
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(setupSurface.opacity(0.86), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cameraWarningTint(for: warning).opacity(0.32), lineWidth: 1)
        }
        .shadow(color: setupShadowColor, radius: 14, y: 8)
        .accessibilityLabel("\(cameraWarningTitle(for: warning.alert)), \(warning.distanceText). Reports are not guaranteed.")
    }

    private func cameraWarningTitle(for alert: EnforcementAlert) -> String {
        switch alert.type {
        case .speedCamera:
            return "Speed camera report"
        case .redLightCamera:
            return "Red-light camera report"
        case .policeReported, .other:
            return "Camera report"
        }
    }

    private func cameraWarningSystemImage(for alert: EnforcementAlert) -> String {
        switch alert.type {
        case .speedCamera:
            return "speedometer"
        case .redLightCamera:
            return "trafficlight.fill"
        case .policeReported, .other:
            return "camera.viewfinder"
        }
    }

    private func cameraWarningTint(for warning: ActiveCameraWarning) -> Color {
        switch warning.threshold {
        case .fiveHundredFeet:
            return Palette.success
        case .oneHundredFiftyFeet:
            return Color.orange
        case .fiftyFeet:
            return Palette.danger
        }
    }

    private func fullRouteMapBottomOverlay(route: RouteEstimate) -> some View {
        VStack(spacing: 8) {
            if liveDriveScreenState == .driving {
                HStack(spacing: 8) {
                    Button {
                        if tracker.isPaused {
                            resumeLiveDrive()
                        } else {
                            pauseLiveDrive()
                        }
                    } label: {
                        Label(tracker.isPaused ? "Resume" : "Pause", systemImage: tracker.isPaused ? "play.fill" : "pause.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(setupPrimaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(setupSurfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        endLiveDrive()
                    } label: {
                        Label("End Trip", systemImage: "stop.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Palette.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Palette.danger.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                mapOverlayMetric(title: "Speed", value: "\(Self.speedString(tracker.currentSpeed)) mph")
                mapOverlayMetric(title: "Limit", value: speedLimitDisplayText)
                mapOverlayMetric(title: "Apple ETA", value: liveDriveHUDAppleETAValue)
                mapOverlayMetric(title: "Arrive", value: liveDriveHUDLiveETAValue)

                Button {
                    isMapOptionsPresented = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(setupPrimaryText)
                        .frame(width: 42)
                        .frame(height: 38)
                        .background(setupSurfaceMuted, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(setupPanelBorder, lineWidth: 1)
                        }
                        .accessibilityLabel("Open menu")
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                mapOverlayMetric(title: "Route", value: "\(Self.milesString(route.distanceMiles)) mi")
                mapOverlayMetric(title: "Driven", value: "\(Self.milesString(tracker.distanceTraveled)) mi")
                mapOverlayMetric(title: "Avg", value: liveDriveHUDAverageSpeedValue)
                mapOverlayMetric(title: "Top", value: liveDriveTopSpeedText)
            }
        }
        .padding(10)
        .background(setupSurface.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(setupPanelBorder, lineWidth: 1)
        }
        .shadow(color: setupShadowColor, radius: 22, y: 10)
    }

    private var mapOptionsSheet: some View {
        ZStack {
            mobileScreenBackground

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        Text("Menu")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(setupPrimaryText)

                        Spacer(minLength: 12)

                        Button("Done") {
                            isMapOptionsPresented = false
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(setupPrimaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(setupSurfaceMuted, in: Capsule())
                        .buttonStyle(.plain)
                    }

                    menuStatusCard

                    mapOptionsSection(title: "Actions", systemImage: "clock.arrow.circlepath", accent: Color(red: 0.25, green: 0.55, blue: 1.00)) {
                        Button {
                            presentTripHistorySheet()
                        } label: {
                            menuActionRow(
                                title: "Drive History",
                                subtitle: "Review completed trips and shared results.",
                                systemImage: "clock.arrow.circlepath",
                                tint: Color.blue
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            presentScannerSheet()
                        } label: {
                            menuActionRow(
                                title: "Public Scanner Listening",
                                subtitle: "Open public scanner listening.",
                                systemImage: "radio.fill",
                                tint: Palette.success
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    mapOptionsSection(title: "Driving Display", systemImage: "map", accent: Color(red: 0.20, green: 0.78, blue: 0.42)) {
                        Picker("Map Mode", selection: selectedMapModeBinding) {
                            ForEach(LiveDriveMapMode.allCases) { mode in
                                Text(mode.rawValue)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("HUD Size", selection: selectedHUDSizeBinding) {
                            ForEach(LiveDriveHUDSize.allCases) { size in
                                Text(size.rawValue)
                                    .tag(size)
                            }
                        }
                        .pickerStyle(.segmented)

                        Toggle("Keep Screen Awake", isOn: keepScreenAwakeBinding)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(setupPrimaryText)
                            .tint(Color.yellow)
                    }

                    mapOptionsSection(title: "Weather", systemImage: "cloud.sun.fill", accent: Color(red: 1.00, green: 0.62, blue: 0.16)) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(routeWeatherOptionsRoute == nil ? "Current Weather" : "Route Forecast")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(setupPrimaryText)

                                Text(routeWeatherOptionsDescription)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(setupSecondaryText)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 8)

                            Button(action: toggleRouteWeatherFromOptions) {
                                Text(isRouteWeatherVisible ? "Hide" : "Show")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(setupPrimaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(setupSurfaceMuted, in: Capsule())
                                    .overlay {
                                        Capsule().stroke(setupPanelBorder, lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                        }

                        if routeWeatherOptionsRoute == nil {
                            if isCurrentWeatherLoading {
                                Text("Loading current weather...")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(setupSecondaryText)
                                    .padding(.top, 2)
                            } else if !isRouteWeatherVisible {
                                Text("Hidden")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(setupSecondaryText)
                                    .padding(.top, 2)
                            } else if let entry = currentWeatherEntry {
                                routeWeatherOptionsRow(entry)
                            } else {
                                Text(currentWeatherMessage)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(setupSecondaryText)
                                    .padding(.top, 2)
                            }
                        } else if !isRouteWeatherVisible {
                            Text("Hidden")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(setupSecondaryText)
                                .padding(.top, 2)
                        } else if routeWeatherEntries.isEmpty {
                            Text(routeWeatherMessage.isEmpty ? "Forecast unavailable" : routeWeatherMessage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(setupSecondaryText)
                                .padding(.top, 2)
                        } else {
                            ScrollView(.vertical, showsIndicators: routeWeatherEntries.count > 2) {
                                VStack(spacing: 8) {
                                    ForEach(routeWeatherEntries) { entry in
                                        routeWeatherOptionsRow(entry)
                                    }
                                }
                            }
                            .frame(maxHeight: routeWeatherEntries.count > 2 ? 178 : nil)
                        }
                    }

                    mapOptionsSection(title: "Alerts", systemImage: "airplane", accent: Color(red: 0.82, green: 0.20, blue: 0.95)) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Nearby Low Aircraft")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(setupPrimaryText)

                                Text(aircraftOptionsStatusText)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(setupSecondaryText)
                            }

                            Spacer(minLength: 8)

                            Button(action: toggleAircraftLayer) {
                                Text(showsAircraftLayer ? "Hide" : "Show")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(setupPrimaryText)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(setupSurfaceMuted, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        Text(aircraftLastUpdatedText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(setupTertiaryText)

                        if !aircraftLayer.aircraft.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(aircraftLayer.aircraft.prefix(5)) { aircraft in
                                    mapOptionsDetailRow(
                                        title: aircraft.callsign,
                                        value: aircraft.distanceMiles.map { "\(String(format: "%.1f", $0)) mi away" } ?? "Nearby",
                                        detail: aircraftOptionsDetailText(for: aircraft)
                                    )
                                }
                            }
                        }
                    }

                    mapOptionsSection(title: "Camera Alerts", systemImage: "camera.viewfinder", accent: Color(red: 1.00, green: 0.57, blue: 0.18)) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Camera and enforcement reports")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(setupPrimaryText)

                                Text(enforcementAlertOptionsStatusText)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(setupSecondaryText)
                            }

                            Spacer(minLength: 8)

                            Toggle("", isOn: $areEnforcementAlertsEnabled)
                                .labelsHidden()
                                .tint(Color(red: 1.00, green: 0.57, blue: 0.18))
                        }

                        Toggle("Red-light cameras", isOn: $areRedLightCameraAlertsEnabled)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(setupPrimaryText)
                            .tint(Color(red: 1.00, green: 0.57, blue: 0.18))
                            .disabled(!areEnforcementAlertsEnabled)
                            .opacity(areEnforcementAlertsEnabled ? 1 : 0.55)

                        Toggle("Enforcement reports", isOn: $areEnforcementReportAlertsEnabled)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(setupPrimaryText)
                            .tint(Color(red: 1.00, green: 0.57, blue: 0.18))
                            .disabled(!areEnforcementAlertsEnabled)
                            .opacity(areEnforcementAlertsEnabled ? 1 : 0.55)

                        Text("Coverage varies by region. Reports are not guaranteed and are informational only.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(setupTertiaryText)
                    }

                    mapOptionsSection(title: "Audio", systemImage: liveDriveHUDVoiceState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", accent: Color(red: 0.12, green: 0.60, blue: 1.00)) {
                        Toggle("Navigation Voice", isOn: navigationVoiceEnabledBinding)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(setupPrimaryText)
                            .tint(Color(red: 0.12, green: 0.60, blue: 1.00))

                        Toggle("Camera Voice", isOn: $isCameraAlertAudioEnabled)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(setupPrimaryText)
                            .tint(Color(red: 1.00, green: 0.57, blue: 0.18))
                            .disabled(!areEnforcementAlertsEnabled)
                            .opacity(areEnforcementAlertsEnabled ? 1 : 0.55)

                        Toggle("ADS-B Voice", isOn: $isAircraftAlertAudioEnabled)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(setupPrimaryText)
                            .tint(Color(red: 0.82, green: 0.20, blue: 0.95))

                        HStack(spacing: 10) {
                            mapOptionsDetailRow(
                                title: "Voice",
                                value: liveDriveHUDVoiceState.isMuted ? "Muted" : liveDriveHUDVoiceState.selectedVoiceName,
                                detail: "Local iOS system voice"
                            )

                            VStack(spacing: 8) {
                                Button(action: toggleVoiceGuidanceMute) {
                                    Text(liveDriveHUDVoiceState.isMuted ? "Unmute" : "Mute")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(setupPrimaryText)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(setupSurfaceMuted, in: Capsule())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    presentVoiceSelectionSheet()
                                } label: {
                                    Text("Choose")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(setupPrimaryText)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(setupSurfaceMuted, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(width: 86)
                        }

                        Button {
                            guidanceEngine.speakTestPrompt()
                        } label: {
                            Label("Test Voice", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(setupPrimaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(setupSurfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(liveDriveHUDVoiceState.isMuted)
                        .opacity(liveDriveHUDVoiceState.isMuted ? 0.55 : 1)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Voice volume")
                                Spacer()
                                Text("\(Int(storedGuidanceVolume * 100))%")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(setupSecondaryText)

                            Slider(
                                value: Binding(
                                    get: { storedGuidanceVolume },
                                    set: { setGuidanceVolume($0) }
                                ),
                                in: 0...1
                            )
                            .tint(Color(red: 0.12, green: 0.60, blue: 1.00))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Speech speed")
                                Spacer()
                                Text(liveDriveHUDVoiceState.speechRate < 0.44 ? "Slower" : "Clear")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(setupSecondaryText)

                            Slider(
                                value: Binding(
                                    get: { liveDriveHUDVoiceState.speechRate },
                                    set: { setGuidanceSpeechRate($0) }
                                ),
                                in: 0.38...0.56
                            )
                            .tint(Palette.success)
                        }
                    }

                    mapOptionsSection(title: "Trip Data", systemImage: "square.and.arrow.up", accent: Color(red: 0.36, green: 0.76, blue: 0.86)) {
                        Picker("Default Export Format", selection: selectedTripExportFormatBinding) {
                            ForEach(TripExportFormat.allCases) { format in
                                Text(format.rawValue)
                                    .tag(format)
                            }
                        }
                        .pickerStyle(.segmented)

                        Button {
                            exportAllTrips()
                        } label: {
                            menuActionRow(
                                title: "Export All Trips",
                                subtitle: exportAllTripsSubtitle,
                                systemImage: "square.and.arrow.up",
                                tint: Color(red: 0.36, green: 0.76, blue: 0.86)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(tripHistoryStore.trips.isEmpty)
                        .opacity(tripHistoryStore.trips.isEmpty ? 0.55 : 1)

                        Button(role: .destructive) {
                            isDeleteAllTripsConfirmationPresented = true
                        } label: {
                            menuActionRow(
                                title: "Delete All Trip History",
                                subtitle: "Remove saved trip results from this device.",
                                systemImage: "trash.fill",
                                tint: Palette.danger
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(tripHistoryStore.trips.isEmpty)
                        .opacity(tripHistoryStore.trips.isEmpty ? 0.55 : 1)

                        mapOptionsDetailRow(
                            title: "Speed Limit",
                            value: speedLimitDisplayText,
                            detail: speedLimitDetailText
                        )
                    }

                    mapOptionsSection(title: "Settings", systemImage: "location.fill", accent: Palette.success) {
                        mapOptionsDetailRow(
                            title: "Background Tracking",
                            value: backgroundTrackingStatusTitle,
                            detail: backgroundTrackingStatusDetail
                        )

                        Button {
                            openLiveDriveSettings()
                        } label: {
                            menuActionRow(
                                title: "Open iOS Location Settings",
                                subtitle: "Review Always Location and background tracking permissions.",
                                systemImage: "gearshape.fill",
                                tint: Palette.success
                            )
                        }
                        .buttonStyle(.plain)

                        if canResetCurrentTripCounters {
                            Button(role: .destructive) {
                                resetCurrentTripCounters()
                            } label: {
                                menuActionRow(
                                    title: "Reset Current Trip Counters",
                                    subtitle: "Clear the active TimeThrottle counters and return to setup.",
                                    systemImage: "arrow.counterclockwise",
                                    tint: Palette.danger
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    mapOptionsSection(title: "Pace", systemImage: "timer", accent: Palette.success) {
                        HStack(spacing: 10) {
                            mapOptionsDetailRow(
                                title: "Time Above Speed Limit",
                                value: liveDriveDisplayedTimeAboveSpeedLimitText,
                                detail: nil
                            )

                            mapOptionsDetailRow(
                                title: "Time Below Speed Limit",
                                value: liveDriveDisplayedTimeBelowSpeedLimitText,
                                detail: nil
                            )
                        }

                        mapOptionsDetailRow(
                            title: "Average speed",
                            value: liveDriveHUDAverageSpeedValue,
                            detail: "Current trip average"
                        )

                        mapOptionsDetailRow(
                            title: "Top speed",
                            value: liveDriveTopSpeedText,
                            detail: "Highest valid GPS speed this trip"
                        )
                    }
                }
                .padding(16)
            }
        }
        .confirmationDialog(
            "Delete all trip history?",
            isPresented: $isDeleteAllTripsConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete All Trip History", role: .destructive) {
                tripHistoryStore.removeAll()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved TimeThrottle trip from this device.")
        }
    }

    private var menuStatusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: liveDriveScreenState == .driving ? "car.fill" : "car")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(liveDriveScreenState == .driving ? Palette.success : setupSecondaryText)
                .frame(width: 38, height: 38)
                .background(setupSurfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(menuStatusTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(setupPrimaryText)

                Text(menuStatusDetail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(setupSecondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
        }
        .padding(14)
        .background(setupSurface.opacity(0.98), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(setupPanelBorder, lineWidth: 1)
        }
    }

    private var menuStatusTitle: String {
        switch liveDriveScreenState {
        case .driving:
            return tracker.isPaused ? "Paused" : (isRouteFreeLoggingMode ? "Logging Free Drive" : "Driving")
        case .tripComplete:
            return "Trip complete"
        case .setup:
            return "Not driving"
        }
    }

    private var menuStatusDetail: String {
        switch liveDriveScreenState {
        case .driving:
            return "\(Self.milesString(tracker.distanceTraveled)) mi • \(Self.durationString(tracker.tripDuration))"
        case .tripComplete:
            return liveDriveFinishedTrip?.displayRouteTitle ?? "Finished trip ready."
        case .setup:
            return speedLimitDisplayText == "Unavailable" ? "Map and passive layers are ready." : "Speed Limit estimate \(speedLimitDisplayText)"
        }
    }

    private var exportAllTripsSubtitle: String {
        let count = tripHistoryStore.trips.count
        let label = count == 1 ? "trip" : "trips"
        return count == 0 ? "No saved trips yet." : "Share \(count) saved \(label) as \(selectedTripExportFormat.rawValue)."
    }

    private var backgroundTrackingStatusTitle: String {
        switch tracker.permissionState {
        case .authorizedAlways:
            return "Always Location Ready"
        case .authorizedWhenInUse:
            return "Always Location Recommended"
        case .notDetermined:
            return "Location Permission Needed"
        case .denied:
            return "Location Access Off"
        case .restricted:
            return "Location Restricted"
        }
    }

    private var backgroundTrackingStatusDetail: String {
        switch tracker.permissionState {
        case .authorizedAlways:
            return "Background tracking can continue when another navigation app is open."
        case .authorizedWhenInUse:
            return "Enable Always Location if you want TimeThrottle to keep measuring while another app is foregrounded."
        case .notDetermined:
            return "Allow location access to measure speed, distance, and live trip counters."
        case .denied:
            return "Open iOS Settings to restore location access before logging drives."
        case .restricted:
            return "This device restricts location access, so background tracking is unavailable."
        }
    }

    private var canResetCurrentTripCounters: Bool {
        liveDriveScreenState == .driving || tracker.distanceTraveled > 0 || tracker.tripDuration > 0
    }

    private func menuActionRow(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(setupPrimaryText)

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(setupSecondaryText)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(setupTertiaryText)
        }
        .padding(10)
        .background(setupSurfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func mapOptionsSection<Content: View>(
        title: String,
        systemImage: String,
        accent: Color = Palette.success,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(setupPrimaryText)
            }

            content()
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    accent.opacity(0.09),
                    setupSurface.opacity(0.98),
                    setupSurface.opacity(0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(accent.opacity(0.22), lineWidth: 1)
        }
    }

    private func mapOptionsDetailRow(title: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(setupSecondaryText)
                .lineLimit(1)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(setupPrimaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(setupTertiaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(setupSurfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func routeWeatherOptionsRow(_ entry: RouteWeatherDisplayEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            mapOptionsDetailRow(
                title: entry.title,
                value: entry.forecastText,
                detail: "\(entry.arrivalText) • \(entry.detailText)"
            )

            if let alertText = entry.alertText {
                VStack(alignment: .leading, spacing: 5) {
                    Label(alertText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.danger)

                    if let advisorySummary = entry.advisorySummary, !advisorySummary.isEmpty {
                        Text(advisorySummary)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(setupSecondaryText)
                            .lineLimit(3)
                    }

                    let context = [
                        entry.advisoryAffectedArea.map { "Area: \($0)" },
                        entry.advisoryIssuedText.map { "Issued \($0)" },
                        entry.advisorySource.map { "Source: \($0)" }
                    ].compactMap { $0 }

                    if !context.isEmpty {
                        Text(context.joined(separator: " • "))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(setupTertiaryText)
                            .lineLimit(3)
                    }

                    if let url = entry.advisorySourceURL {
                        Link("Learn More", destination: url)
                            .font(.caption.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(setupSurfaceMuted.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var aircraftOptionsStatusText: String {
        if !showsAircraftLayer {
            return "Aircraft layer is off."
        }

        if aircraftLayer.isStale {
            return "No fresh nearby aircraft."
        }

        return aircraftStatusText
    }

    private var aircraftLastUpdatedText: String {
        guard let lastUpdated = aircraftLayer.lastUpdated else {
            return showsAircraftLayer ? "Not updated yet." : "Aircraft polling starts when the layer is shown."
        }

        let prefix = aircraftLayer.isStale ? "Last fresh update" : "Last updated"
        return "\(prefix) \(Self.relativeAgeString(since: lastUpdated))"
    }

    private func aircraftOptionsDetailText(for aircraft: Aircraft) -> String {
        [
            aircraft.altitudeFeet.map { "Alt \(Int($0.rounded())) ft" },
            aircraft.groundSpeedMPH.map { "Speed \(Int($0.rounded())) mph" },
            aircraft.headingDegrees.map { "Heading \(Int($0.rounded()))°" },
            aircraft.dataAgeSeconds.map { "Data age \(Self.durationSecondsString($0))" }
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    private func enforcementAlertDetailText(for alert: EnforcementAlert) -> String {
        [
            alert.source.isEmpty ? nil : alert.source,
            alert.confidence.map { "Confidence \(Int(($0 * 100).rounded()))%" },
            alert.bearingDegrees.map { "Bearing \(Int($0.rounded()))°" },
            alert.lastUpdated.map { "Updated \(Self.relativeAgeString(since: $0))" },
            alert.isStale ? "Stale" : nil
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    private static func relativeAgeString(since date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date).rounded()))
        if seconds < 60 {
            return "\(seconds)s ago"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }

        return "\(minutes / 60)h ago"
    }

    private static func durationSecondsString(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m"
    }

    private func fullRouteMapRouteLabel(_ route: RouteEstimate) -> String {
        let routeName = route.routeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return routeName.isEmpty ? route.destinationName : routeName
    }

    private func mapOverlayMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(setupSecondaryText)
                .lineLimit(1)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(setupPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tabEmptyState(title: String, message: String, systemImage: String) -> some View {
        ZStack {
            mobileScreenBackground

            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Palette.success)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(setupPrimaryText)

                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(setupSecondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
            }
            .padding(24)
        }
    }

    private var mobileScreen: some View {
        ZStack(alignment: .top) {
            mobileScreenBackground
            mobileHeaderBackdrop

            if isPolishedLiveDriveSetup {
                liveDriveSetupSurfaceBackdrop
            }

            mobileBody
        }
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private var mobileScreenBackground: some View {
        if usesDarkLiveDriveTheme {
            ZStack {
                LinearGradient(
                    colors: [setupBackgroundTop, setupBackgroundBottom, Color(red: 0.08, green: 0.10, blue: 0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [Palette.success.opacity(0.16), .clear],
                    center: .top,
                    startRadius: 16,
                    endRadius: 260
                )
                .offset(y: -84)
            }
            .ignoresSafeArea()
        } else {
            #if os(iOS)
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            #else
            Palette.workspace
                .ignoresSafeArea()
            #endif
        }
    }

    @ViewBuilder
    private var mobileLiveDriveContentBackdrop: some View {
        if usesDarkLiveDriveTheme {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.10, blue: 0.15),
                        Color(red: 0.09, green: 0.12, blue: 0.17),
                        Color(red: 0.07, green: 0.09, blue: 0.13)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [
                        Palette.success.opacity(0.08),
                        .clear
                    ],
                    center: .top,
                    startRadius: 24,
                    endRadius: 320
                )
                .offset(y: -120)
            }
        } else {
            EmptyView()
        }
    }

    private var mobileHeaderBackdrop: some View {
        headerBackground
            .frame(maxWidth: .infinity)
            .frame(height: 92, alignment: .top)
            .ignoresSafeArea(.container, edges: .top)
            .allowsHitTesting(false)
    }

    private var liveDriveSetupSurfaceBackdrop: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [setupSurface.opacity(0.98), setupSurfaceRaised.opacity(0.96)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(setupPanelBorder, lineWidth: 1)
            }
            .shadow(color: setupShadowColor, radius: 32, y: 16)
            .padding(.top, heroHeight + 78)
            .padding(.horizontal, 0)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
    }

    private var desktopBody: some View {
        ScrollView {
            VStack(spacing: 0) {
                desktopHeaderSection
                glassDivider

                VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                    controls
                    summarySection
                    contentSection
                }
                .padding(.horizontal, Layout.screenPadding)
                .padding(.top, Layout.sectionSpacing)
                .padding(.bottom, Layout.screenPadding)
                .background(Palette.workspace)
            }
        }
        .background(Palette.workspace.ignoresSafeArea())
    }

    private var mobileBody: some View {
        ScrollView {
            VStack(spacing: 0) {
                mobileHeaderSection
                glassDivider

                VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                    mobileLiveDriveFlow
                }
                .padding(.horizontal, mobileContentHorizontalPadding)
                .padding(.top, isPolishedLiveDriveSetup ? 8 : Layout.sectionSpacing)
                .padding(.bottom, Layout.screenPadding)
                .background {
                    if usesDarkLiveDriveTheme {
                        mobileLiveDriveContentBackdrop
                    } else if isPolishedLiveDriveSetup {
                        Color.clear
                    } else {
                        Palette.workspace
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if usesDarkLiveDriveTheme {
                mobileLiveDriveContentBackdrop
            } else {
                Palette.workspace
            }
        }
    }

    private var mobileLiveDriveFlow: some View {
        VStack(alignment: .leading, spacing: liveDriveScreenState == .setup ? 10 : Layout.sectionSpacing) {
            switch liveDriveScreenState {
            case .setup:
                liveDriveSetupSection
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .driving:
                liveDriveRouteContextSection
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                liveDriveComparisonSection
                    .transition(.opacity)
                liveDriveSafetySection
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .tripComplete:
                liveDriveFinishedResultSection
                    .transition(.opacity)
                liveDriveRouteContextSection
                    .transition(.opacity)
                liveDriveSafetySection
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28, extraBounce: 0), value: liveDriveScreenState)
    }

    private var headerBackground: some View {
        ZStack {
            if usesDarkLiveDriveTheme {
                Rectangle()
                    .fill(Color(red: 0.05, green: 0.07, blue: 0.11))

                LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.12, blue: 0.18).opacity(0.96),
                        Color(red: 0.08, green: 0.11, blue: 0.16).opacity(0.92),
                        Color(red: 0.07, green: 0.10, blue: 0.15).opacity(0.86)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.22, green: 0.62, blue: 0.52).opacity(0.19),
                        Color(red: 0.14, green: 0.30, blue: 0.42).opacity(0.10),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 18,
                    endRadius: 250
                )
                .offset(x: 12, y: -28)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.018),
                        Color.white.opacity(0.008),
                        Color.black.opacity(0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [
                        headerGradientStart.opacity(0.98),
                        headerGradientEnd.opacity(0.94),
                        Color.white.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.14),
                        .clear,
                        Color.white.opacity(0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 8,
                    endRadius: 260
                )
            }
        }
    }

    private var desktopHeaderSection: some View {
        VStack(spacing: 14) {
            logoLockup

            platformBadge
        }
        .padding(.top, 28)
        .padding(.bottom, 22)
        .padding(.horizontal, Layout.screenPadding)
        .frame(maxWidth: .infinity, minHeight: heroHeight)
        .background {
            headerBackground
        }
    }

    private var mobileHeaderSection: some View {
        VStack(spacing: liveDriveScreenState == .setup ? 0 : 12) {
            logoLockup
                .frame(maxWidth: .infinity, alignment: .center)

            if liveDriveScreenState != .setup {
                liveDriveHeaderStatus
            }
        }
        .padding(.horizontal, Layout.screenPadding)
        .padding(.top, liveDriveScreenState == .setup ? 18 : 38)
        .padding(.bottom, liveDriveScreenState == .setup ? 4 : 18)
        .safeAreaPadding(.top, 34)
        .frame(maxWidth: .infinity, minHeight: heroHeight, alignment: .bottom)
        .background {
            headerBackground
                .ignoresSafeArea(.container, edges: .top)
        }
    }

    private var liveDriveHeaderStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: liveDriveHeaderStatusIconName)
                .font(.caption.weight(.bold))

            Text(liveDriveHeaderStatusTitle)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(usesDarkLiveDriveTheme ? setupSurfaceMuted : Color.white.opacity(0.18), in: Capsule())
        .overlay {
            if usesDarkLiveDriveTheme {
                Capsule()
                    .stroke(setupPanelBorder, lineWidth: 1)
            }
        }
    }

    private var liveDriveHeaderStatusTitle: String {
        let elapsedMinutes = liveDriveFinishedTrip?.elapsedDriveMinutes ?? tracker.tripDuration
        let elapsedText = Self.durationString(elapsedMinutes)

        if liveDriveScreenState == .tripComplete {
            return "Trip complete • \(elapsedText)"
        }

        return tracker.isPaused
            ? "Trip paused • \(elapsedText)"
            : "Trip in progress • \(elapsedText)"
    }

    private var liveDriveHeaderStatusIconName: String {
        if liveDriveScreenState == .tripComplete {
            return "checkmark.circle.fill"
        }

        return tracker.isPaused ? "pause.circle.fill" : "location.fill"
    }

    private var logoLockup: some View {
        Group {
                if let brandLogo {
                    brandLogo
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(height: heroLogoHeight)
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                } else {
                    EmptyView()
                }
            }
        }

    @ViewBuilder
    private var platformBadge: some View {
        EmptyView()
    }

    private var glassDivider: some View {
        Rectangle()
            .fill(usesDarkLiveDriveTheme ? setupPanelBorder.opacity(0.7) : Color.white.opacity(0.34))
            .frame(height: 1)
            .padding(.horizontal, isMobileLayout ? 0 : Layout.screenPadding)
    }

    @ViewBuilder
    private var controls: some View {
        liveDriveSetupSection
    }

    private var appleMapsRouteInputs: some View {
        VStack(alignment: .leading, spacing: isPolishedLiveDriveSetup ? 6 : 12) {
            currentLocationOriginField

            routeAddressInputField(
                text: $toAddressText,
                placeholder: "Destination address",
                field: .to
            )

            routeAutocompleteList(suggestions: toSuggestions, field: .to)

            if shouldShowRouteStatus {
                routeStatusView
            }
        }
    }

    private var routeOriginModePicker: some View {
        HStack(spacing: isPolishedLiveDriveSetup ? 6 : 8) {
            ForEach(RouteOriginInputMode.allCases) { mode in
                Button {
                    routeOriginInputMode = mode
                } label: {
                    Text(mode.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            routeOriginInputMode == mode
                                ? (isPolishedLiveDriveSetup ? setupPrimaryText : Color.white)
                                : (isPolishedLiveDriveSetup ? setupSecondaryText : Palette.cocoa)
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, isPolishedLiveDriveSetup ? 8 : 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            routeOriginModeBackground(for: mode),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(routeOriginModeBorder(for: mode), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(isPolishedLiveDriveSetup ? 4 : 0)
        .background(
            routeOriginModeContainerBackground,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private var routeOriginModeContainerBackground: Color {
        isPolishedLiveDriveSetup ? setupSurfaceMuted : .clear
    }

    private func routeOriginModeBackground(for mode: RouteOriginInputMode) -> Color {
        guard routeOriginInputMode == mode else {
            return isPolishedLiveDriveSetup ? Color.clear : Palette.panelAlt
        }

        return isPolishedLiveDriveSetup ? setupSelectionFill : Palette.success
    }

    private func routeOriginModeBorder(for mode: RouteOriginInputMode) -> Color {
        if routeOriginInputMode == mode {
            return isPolishedLiveDriveSetup ? setupSelectionBorder : Palette.success
        }

        return isPolishedLiveDriveSetup ? setupFieldBorder : Palette.surfaceBorder
    }

    private var routeInputBackground: Color {
        if isPolishedLiveDriveSetup {
            return setupFieldFill
        }

        return Palette.panelAlt
    }

    private func routeInputBorder(for field: RouteAddressField) -> Color {
        if focusedRouteAddressField == field {
            return Palette.success.opacity(isPolishedLiveDriveSetup ? 0.35 : 0.45)
        }

        return isPolishedLiveDriveSetup ? setupFieldBorder : Palette.surfaceBorder
    }

    private var currentLocationOriginField: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: currentLocationResolver.errorMessage == nil ? "location.fill" : "location.slash.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(currentLocationResolver.errorMessage == nil ? Palette.success : Palette.danger)
                .frame(width: 28, height: 28)
                .background((isPolishedLiveDriveSetup ? setupSelectionFill : Palette.panelAlt), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(currentLocationFieldLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isPolishedLiveDriveSetup ? setupSecondaryText : Palette.cocoa)

                Text(currentLocationDetailText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(currentLocationResolver.errorMessage == nil ? (isPolishedLiveDriveSetup ? setupPrimaryText : Palette.ink) : Palette.danger)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            if currentLocationResolver.isResolving {
                ProgressView()
                    .tint(Palette.success)
            } else if currentLocationResolver.authorizationStatus == .denied {
                Button("Settings") {
                    openLiveDriveSettings()
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.success)
            } else {
                Button("Refresh") {
                    currentLocationResolver.requestCurrentLocation()
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.success)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isPolishedLiveDriveSetup ? setupFieldFill : Palette.panelAlt, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isPolishedLiveDriveSetup ? setupFieldBorder : Palette.surfaceBorder, lineWidth: 1)
        }
    }

    private func routeAddressInputField(
        text: Binding<String>,
        placeholder: String,
        field: RouteAddressField
    ) -> some View {
        HStack(spacing: 10) {
            if isPolishedLiveDriveSetup {
                ZStack {
                    Circle()
                        .fill((field == .from ? setupSelectionFill : setupErrorFill).opacity(0.95))
                        .frame(width: 30, height: 30)

                    Image(systemName: field == .from ? "location.fill" : "mappin.and.ellipse")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(field == .from ? Palette.success : Palette.accentRed)
                }
            } else {
                Image(systemName: field == .from ? "circle.fill" : "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(field == .from ? Palette.success : Palette.accentRed)
            }

            TextField(
                "",
                text: text,
                prompt: Text(placeholder)
                    .foregroundStyle(isPolishedLiveDriveSetup ? setupTertiaryText : Palette.cocoa.opacity(0.75))
            )
                .focused($focusedRouteAddressField, equals: field)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .foregroundStyle(isPolishedLiveDriveSetup ? setupPrimaryText : Palette.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
                .submitLabel(field == .from ? .next : .search)
                .onSubmit {
                    handleAddressFieldSubmit(field)
                }

            if field == .to && !text.wrappedValue.isEmpty {
                Button {
                    clearDestinationField()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isPolishedLiveDriveSetup ? setupSecondaryText.opacity(0.85) : Palette.cocoa.opacity(0.75))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear destination")
            }
        }
        .padding(.horizontal, isPolishedLiveDriveSetup ? 14 : 14)
        .frame(minHeight: isPolishedLiveDriveSetup ? 52 : 50, alignment: .leading)
        .background(routeInputBackground, in: RoundedRectangle(cornerRadius: isPolishedLiveDriveSetup ? 18 : 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isPolishedLiveDriveSetup ? 18 : 14, style: .continuous)
                .stroke(routeInputBorder(for: field), lineWidth: 1)
        }
        .shadow(color: isPolishedLiveDriveSetup ? .black.opacity(0.04) : .clear, radius: 12, y: 5)
    }

    @ViewBuilder
    private func routeAutocompleteList(
        suggestions: [AppleMapsAutocompleteController.Suggestion],
        field: RouteAddressField
    ) -> some View {
        if !suggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    Button {
                        selectAutocompleteSuggestion(suggestion, for: field)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isPolishedLiveDriveSetup ? setupPrimaryText : Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(isPolishedLiveDriveSetup ? setupSecondaryText : Palette.cocoa)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < suggestions.count - 1 {
                        Rectangle()
                            .fill(isPolishedLiveDriveSetup ? setupPanelBorder : Palette.surfaceBorder.opacity(0.6))
                            .frame(height: 1)
                    }
                }
            }
            .background((isPolishedLiveDriveSetup ? setupFieldFill : Color.white).opacity(isPolishedLiveDriveSetup ? 0.98 : 1), in: RoundedRectangle(cornerRadius: isPolishedLiveDriveSetup ? 18 : 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: isPolishedLiveDriveSetup ? 18 : 14, style: .continuous)
                    .stroke(isPolishedLiveDriveSetup ? setupFieldBorder : Palette.surfaceBorder.opacity(1), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isPolishedLiveDriveSetup ? 0.08 : 0.05), radius: isPolishedLiveDriveSetup ? 20 : 14, y: isPolishedLiveDriveSetup ? 10 : 6)
        }
    }

    private func compactMetricField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(inputLabelFont)
                .foregroundStyle(isPolishedLiveDriveSetup ? setupSecondaryText : Palette.cocoa)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                BrandedTextField(
                    text: text,
                    placeholder: placeholder,
                    fontSize: 24,
                    fontWeight: .bold,
                    compact: true,
                    foregroundColor: isPolishedLiveDriveSetup ? setupPrimaryText : Palette.ink,
                    backgroundColor: isPolishedLiveDriveSetup ? setupFieldFill : Color.white.opacity(0.97),
                    borderColor: isPolishedLiveDriveSetup ? setupFieldBorder : Palette.surfaceBorder,
                    placeholderColor: isPolishedLiveDriveSetup ? setupTertiaryText : Palette.cocoa.opacity(0.75)
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(unit)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isPolishedLiveDriveSetup ? setupSecondaryText : Palette.cocoa)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var routeStatusView: some View {
        HStack(spacing: 12) {
            if isCalculatingRoute {
                ProgressView()
                    .tint(isPolishedLiveDriveSetup ? setupSecondaryText : Palette.cocoa)
            }

            Text(routeStatusText)
                .font(routeStatusFont)
                .foregroundStyle(routeStatusForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, isMobileLayout ? 12 : 13)
        .padding(.vertical, isMobileLayout ? 7 : 10)
        .background(routeStatusBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isPolishedLiveDriveSetup ? routeStatusBorder : .clear, lineWidth: isPolishedLiveDriveSetup ? 1 : 0)
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        liveDriveSummarySection
    }

    private var liveDriveSetupSection: some View {
        SectionCard(
            padding: isPolishedLiveDriveSetup ? 12 : Layout.sectionPadding,
            background: isPolishedLiveDriveSetup ? setupSurface : Palette.panel,
            border: isPolishedLiveDriveSetup ? setupPanelBorder : Palette.surfaceBorder,
            shadowColor: isPolishedLiveDriveSetup ? setupShadowColor : .black.opacity(0.05),
            shadowRadius: isPolishedLiveDriveSetup ? 28 : 18,
            shadowYOffset: isPolishedLiveDriveSetup ? 12 : 8
        ) {
            VStack(alignment: .leading, spacing: 7) {
                InsetPanel(
                    background: isPolishedLiveDriveSetup ? setupSurfaceRaised : Palette.panel,
                    border: isPolishedLiveDriveSetup ? setupPanelBorder : Palette.surfaceBorder,
                    shadowColor: isPolishedLiveDriveSetup ? setupShadowColor.opacity(0.75) : .black.opacity(0.04),
                    shadowRadius: isPolishedLiveDriveSetup ? 18 : 12,
                    shadowYOffset: isPolishedLiveDriveSetup ? 8 : 6
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        appleMapsRouteInputs
                    }
                }

                if let route = liveDriveSetupRoute {
                    routePreviewSection(routes: liveDriveSetupRouteOptions, selectedRoute: route)
                }

                InsetPanel(
                    background: isPolishedLiveDriveSetup ? setupSurfaceRaised : Palette.panel,
                    border: isPolishedLiveDriveSetup ? setupPanelBorder : Palette.surfaceBorder,
                    shadowColor: isPolishedLiveDriveSetup ? setupShadowColor.opacity(0.75) : .black.opacity(0.04),
                    shadowRadius: isPolishedLiveDriveSetup ? 18 : 12,
                    shadowYOffset: isPolishedLiveDriveSetup ? 8 : 6
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        liveDriveNavigationProviderSection

                        if let liveDriveNavigationHandoffMessage {
                            liveDriveHelperNote(liveDriveNavigationHandoffMessage)
                        }

                        if let liveDriveBackgroundContinuityMessage {
                            liveDriveHelperNote(
                                liveDriveBackgroundContinuityMessage,
                                showsSettingsAction: liveDriveShowsBackgroundContinuitySettingsAction,
                                actionTitle: "Always Location"
                            )
                        }

                        if let liveDrivePermissionMessage {
                            liveDriveStatusBanner(
                                title: "Location access needed",
                                message: liveDrivePermissionMessage,
                                showsSettingsAction: liveDriveShowsSettingsAction
                            )
                        }

                        Button {
                            startLiveDrive()
                        } label: {
                            Label("Start Drive", systemImage: "location.fill")
                                .font(.headline)
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 13)
                                .background(Palette.success, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .shadow(color: Palette.success.opacity(isPolishedLiveDriveSetup ? 0.28 : 0.20), radius: 6, y: 3)
                        }
                        .buttonStyle(.plain)
                        .opacity(isStartLiveDriveDisabled ? 0.55 : 1)
                        .disabled(isStartLiveDriveDisabled)

                        liveDriveLegalityNote
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var liveDriveSummarySection: some View {
        if liveDriveScreenState != .setup {
            liveDriveTripSummarySection
        } else {
            liveDriveSetupSection
        }
    }

    @ViewBuilder
    private var liveDriveContentSection: some View {
        if liveDriveScreenState == .driving {
            liveDriveActivePanelSection
        } else if liveDriveScreenState == .tripComplete {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                if liveDriveFinishedTrip?.hasRouteBaseline != false {
                    liveDriveComparisonSection
                }
                liveDriveRouteContextSection
                liveDriveTripSummarySection
                liveDriveSafetySection
            }
        }
    }

    private var liveDriveActivePanelSection: some View {
        SectionCard(
            background: usesDarkLiveDriveTheme ? setupSurface : Palette.panel,
            border: usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder,
            shadowColor: usesDarkLiveDriveTheme ? setupShadowColor : .black.opacity(0.05),
            shadowRadius: usesDarkLiveDriveTheme ? 24 : 18,
            shadowYOffset: usesDarkLiveDriveTheme ? 10 : 8
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    mobileSectionHeader(
                        title: "Active Drive",
                        subtitle: liveDriveRouteLabel
                    )

                    Spacer(minLength: 8)

                    Button {
                        isRouteSetupPanelPresented = false
                    } label: {
                        Image(systemName: "map.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(setupPrimaryText)
                            .frame(width: 38, height: 38)
                            .background(setupSurfaceMuted, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(setupPanelBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open Map")
                }

                if let route = liveDriveCapturedRoute {
                    routeMapPanel(routes: liveDriveCapturedRouteOptions, selectedRoute: route)
                }

                if !isRouteFreeLoggingMode {
                    timeComparisonRows(
                        baselineTitle: "Apple Maps ETA",
                        baselineMinutes: liveDriveBaselineETAMinutes,
                        comparisonTitle: "Live projected time",
                        comparisonMinutes: liveDriveProjectedTravelMinutes,
                        comparisonTint: liveDriveProjectedTravelTint,
                        comparisonLabel: liveDriveProjectedTravelLabel,
                        scaleMinutes: liveDriveComparisonScaleMinutes
                    )
                }

                liveDriveActiveProgressGrid

                if !isRouteFreeLoggingMode, liveDriveProjectedTravelMinutes > 0 {
                    mobileHelperCard("Expected arrival at your current pace: \(liveDriveExpectedArrivalText)")
                }

                liveDriveActiveControls
                liveDriveLegalityNote
            }
        }
    }

    private var liveDriveActiveProgressGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            SummaryCard(title: "Above Limit", value: liveDriveDisplayedTimeAboveSpeedLimitText, tint: Palette.success, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
            SummaryCard(title: "Below Limit", value: liveDriveDisplayedTimeBelowSpeedLimitText, tint: Palette.danger, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
            SummaryCard(title: "Driven", value: "\(Self.milesString(tracker.distanceTraveled)) mi", tint: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
            SummaryCard(title: "Avg speed", value: liveDriveHUDAverageSpeedValue, tint: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
        }
    }

    private var liveDriveActiveControls: some View {
        HStack(spacing: 10) {
            if tracker.isPaused {
                Button {
                    resumeLiveDrive()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Palette.success, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    pauseLiveDrive()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!tracker.isTracking)
                .opacity(tracker.isTracking ? 1 : 0.55)
            }

            Button {
                endLiveDrive()
            } label: {
                Label("End Trip", systemImage: "stop.fill")
                    .font(.headline)
                    .foregroundStyle(Palette.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background((usesDarkLiveDriveTheme ? setupErrorFill : Palette.dangerBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(usesDarkLiveDriveTheme ? setupErrorBorder : Palette.danger.opacity(0.18), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private var liveDriveComparisonSection: some View {
        SectionCard(
            background: usesDarkLiveDriveTheme ? setupSurface : Palette.panel,
            border: usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder,
            shadowColor: usesDarkLiveDriveTheme ? setupShadowColor : .black.opacity(0.05),
            shadowRadius: usesDarkLiveDriveTheme ? 24 : 18,
            shadowYOffset: usesDarkLiveDriveTheme ? 10 : 8
        ) {
            VStack(alignment: .leading, spacing: 10) {
                timeComparisonRows(
                    baselineTitle: "Apple Maps ETA",
                    baselineMinutes: liveDriveBaselineETAMinutes,
                    comparisonTitle: "Live projected time",
                    comparisonMinutes: liveDriveProjectedTravelMinutes,
                    comparisonTint: liveDriveProjectedTravelTint,
                    comparisonLabel: liveDriveProjectedTravelLabel,
                    scaleMinutes: liveDriveComparisonScaleMinutes
                )

                if liveDriveProjectedTravelMinutes > 0 {
                    mobileHelperCard("Expected arrival at your current pace: \(liveDriveExpectedArrivalText)")
                }
            }
        }
    }

    @ViewBuilder
    private var liveDriveRouteContextSection: some View {
        if let route = liveDriveCapturedRoute {
            SectionCard(
                background: usesDarkLiveDriveTheme ? setupSurface : Palette.panel,
                border: usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder,
                shadowColor: usesDarkLiveDriveTheme ? setupShadowColor : .black.opacity(0.05),
                shadowRadius: usesDarkLiveDriveTheme ? 24 : 18,
                shadowYOffset: usesDarkLiveDriveTheme ? 10 : 8
            ) {
                VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                    mobileSectionHeader(
                        title: "Live route",
                        subtitle: liveDriveRouteLabel
                    )
                    routeMapPanel(routes: liveDriveCapturedRouteOptions, selectedRoute: route)
                }
            }
        }
    }

    private var liveDriveTripSummarySection: some View {
        SectionCard(
            background: usesDarkLiveDriveTheme ? setupSurface : Palette.panel,
            border: usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder,
            shadowColor: usesDarkLiveDriveTheme ? setupShadowColor : .black.opacity(0.05),
            shadowRadius: usesDarkLiveDriveTheme ? 24 : 18,
            shadowYOffset: usesDarkLiveDriveTheme ? 10 : 8
        ) {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                mobileSectionHeader(
                    title: "Trip Summary So Far",
                    subtitle: liveDriveRouteLabel
                )

                if let liveDriveNavigationHandoffMessage {
                    mobileHelperCard(liveDriveNavigationHandoffMessage)
                }

                VStack(alignment: .leading, spacing: 16) {
                    liveDriveSummaryBlock(
                        title: "You gained",
                        value: liveDriveGainSummaryText,
                        tint: Palette.success,
                        isNarrative: true
                    )

                    liveDriveSummaryBlock(
                        title: "You spent",
                        value: liveDriveBelowTargetSummaryText,
                        tint: Palette.danger,
                        isNarrative: true
                    )

                    if !isRouteFreeLoggingMode {
                        liveDriveSummaryBlock(
                            title: liveDriveOverallResultTitle,
                            value: liveDriveVerdict,
                            tint: liveDriveVerdictTint,
                            isNarrative: true
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var liveDriveFinishedResultSection: some View {
        if let completedTrip = liveDriveFinishedTrip {
            SectionCard(
                background: usesDarkLiveDriveTheme ? setupSurface : Palette.panel,
                border: usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder,
                shadowColor: usesDarkLiveDriveTheme ? setupShadowColor : .black.opacity(0.05),
                shadowRadius: usesDarkLiveDriveTheme ? 24 : 18,
                shadowYOffset: usesDarkLiveDriveTheme ? 10 : 8
            ) {
                VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                    mobileSectionHeader(
                        title: "Trip result",
                        subtitle: "Review the finished result or share it."
                    )

                    InsetPanel(
                        background: usesDarkLiveDriveTheme ? setupSurfaceRaised : Palette.panel,
                        border: usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder,
                        shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.75) : .black.opacity(0.04),
                        shadowRadius: usesDarkLiveDriveTheme ? 18 : 12,
                        shadowYOffset: usesDarkLiveDriveTheme ? 8 : 6
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(completedTrip.displayRouteTitle)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink)

                                Text(completedTrip.routeLabel)
                                    .font(panelDescriptionFont)
                                    .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)

                                Text(completedTrip.completedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)
                            }

                            if completedTrip.hasRouteBaseline {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Overall vs Apple ETA")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)

                                    Text(Self.netString(completedTrip.netTimeGain))
                                        .font(.system(size: 34, weight: .bold, design: .rounded))
                                        .foregroundStyle(completedTrip.netTimeGain >= 0 ? Palette.success : Palette.danger)

                                    Text(liveDriveVerdict(for: completedTrip.netTimeGain))
                                        .font(panelDescriptionFont)
                                        .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)
                                }
                            }

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)
                                ],
                                spacing: 12
                            ) {
                                if completedTrip.hasRouteBaseline {
                                    SummaryCard(title: "Time Above Speed Limit", value: Self.speedLimitMetricString(completedTrip.timeSavedBySpeeding, measuredMinutes: completedTrip.speedLimitMeasuredMinutes), tint: Palette.success, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
                                    SummaryCard(title: "Time Below Speed Limit", value: Self.speedLimitMetricString(completedTrip.timeLostBelowTargetPace, measuredMinutes: completedTrip.speedLimitMeasuredMinutes), tint: Palette.danger, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
                                }
                                SummaryCard(title: "Distance driven", value: "\(Self.milesString(completedTrip.distanceDrivenMiles)) mi", tint: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
                                SummaryCard(title: "Elapsed drive time", value: Self.durationString(completedTrip.elapsedDriveMinutes), tint: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
                                SummaryCard(title: "Average trip speed", value: "\(Self.speedString(completedTrip.averageTripSpeed)) mph", tint: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
                                SummaryCard(title: "Top speed", value: Self.topSpeedString(completedTrip.topSpeedMPH), tint: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
                                if !completedTrip.hasRouteBaseline {
                                    SummaryCard(title: "Time Above Speed Limit", value: Self.speedLimitMetricString(completedTrip.timeSavedBySpeeding, measuredMinutes: completedTrip.speedLimitMeasuredMinutes), tint: Palette.success, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
                                    SummaryCard(title: "Time Below Speed Limit", value: Self.speedLimitMetricString(completedTrip.timeLostBelowTargetPace, measuredMinutes: completedTrip.speedLimitMeasuredMinutes), tint: Palette.danger, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
                                }
                            }

                            Text(finishedTripMetricExplanation(for: completedTrip))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)

                            Button {
                                shareFinishedTrip()
                            } label: {
                                Label("Share Trip Result", systemImage: "square.and.arrow.up")
                                    .font(.headline)
                                    .foregroundStyle(Color.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 12)
                                    .background(Palette.success, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var liveDriveSafetySection: some View {
        SectionCard(
            background: usesDarkLiveDriveTheme ? setupSurface : Palette.panel,
            border: usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder,
            shadowColor: usesDarkLiveDriveTheme ? setupShadowColor : .black.opacity(0.05),
            shadowRadius: usesDarkLiveDriveTheme ? 24 : 18,
            shadowYOffset: usesDarkLiveDriveTheme ? 10 : 8
        ) {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                mobileSectionHeader(
                    title: liveDriveScreenState == .driving ? "Drive controls" : "Trip controls",
                    subtitle: liveDriveControlsSubtitle
                )

                VStack(spacing: 12) {
                    if liveDriveScreenState == .driving {
                        if tracker.isTracking {
                            Button {
                                pauseLiveDrive()
                            } label: {
                                Label("Pause", systemImage: "pause.fill")
                                    .font(.headline)
                                    .foregroundStyle(Color.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 14)
                                    .background(Palette.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        if tracker.isPaused {
                            Button {
                                resumeLiveDrive()
                            } label: {
                                Label("Resume", systemImage: "play.fill")
                                    .font(.headline)
                                    .foregroundStyle(Color.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 14)
                                    .background(Palette.success, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            isRouteSetupPanelPresented = false
                        } label: {
                            Label("Open Map", systemImage: "map.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background((usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panelAlt), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }

                    if liveDriveScreenState == .tripComplete {
                        Button {
                            presentTripHistorySheet()
                        } label: {
                            Label("View Trip History", systemImage: "clock.arrow.circlepath")
                                .font(.headline)
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            startNewLiveDrive()
                        } label: {
                            Label("Start New Trip", systemImage: "plus.circle.fill")
                                .font(.headline)
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(Palette.success, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            endLiveDrive()
                        } label: {
                            Label("End Trip", systemImage: "stop.fill")
                                .font(.headline)
                                .foregroundStyle(Palette.danger)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background((usesDarkLiveDriveTheme ? setupErrorFill : Palette.dangerBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(usesDarkLiveDriveTheme ? setupErrorBorder : Palette.danger.opacity(0.18), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }

                    liveDriveLegalityNote
                }
            }
        }
    }

    @ViewBuilder
    private func mobilePillGrid(items: [StatPill]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 130), spacing: 10),
                GridItem(.flexible(minimum: 130), spacing: 10)
            ],
            spacing: 10
        ) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, pill in
                pill
            }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        liveDriveContentSection
    }

    @ViewBuilder
    private var finishedTripBrandLogo: some View {
        if let resultBrandLogo {
            resultBrandLogo
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 72, height: 72)
        } else {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(Palette.success)
        }
    }

    private func mobileSectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(panelHeaderFont)
                .foregroundStyle(usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(panelDescriptionFont)
                    .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)
            }
        }
    }

    private var liveDriveNavigationProviderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Navigation App")
                .font(inputLabelFont)
                .foregroundStyle(isPolishedLiveDriveSetup ? setupSecondaryText : Palette.cocoa)

            Menu {
                ForEach(NavigationProvider.selectableCases) { provider in
                    Button {
                        preferredNavigationProviderBinding.wrappedValue = provider
                    } label: {
                        Label(provider.rawValue, systemImage: preferredNavigationProvider == provider ? "checkmark" : navigationProviderIconName(for: provider))
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: navigationProviderIconName(for: preferredNavigationProvider))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.success)
                        .frame(width: 18)

                    Text(preferredNavigationProvider.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isPolishedLiveDriveSetup ? setupPrimaryText : Palette.ink)

                    Spacer(minLength: 12)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isPolishedLiveDriveSetup ? setupTertiaryText : Palette.cocoa.opacity(0.65))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isPolishedLiveDriveSetup ? setupFieldFill : Palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isPolishedLiveDriveSetup ? setupFieldBorder : Palette.surfaceBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func navigationProviderIconName(for provider: NavigationProvider) -> String {
        switch provider {
        case .appleMaps:
            return "map.fill"
        case .googleMaps:
            return "globe.americas.fill"
        case .waze:
            return "car.fill"
        case .askEveryTime:
            return "questionmark.circle.fill"
        }
    }

    private var liveDriveLegalityNote: some View {
        Text("Always obey traffic laws and road conditions.")
            .font(.footnote.weight(.medium))
            .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mobileHelperCard(_ text: String) -> some View {
        Text(text)
            .font(panelDescriptionFont)
            .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panelAlt), in: RoundedRectangle(cornerRadius: Layout.innerCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Layout.innerCorner, style: .continuous)
                    .stroke(usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder.opacity(0.8), lineWidth: 1)
            }
    }

    @ViewBuilder
    private func liveDriveHelperNote(
        _ message: String,
        showsSettingsAction: Bool = false,
        actionTitle: String = "Allow Always Location"
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.success)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(panelDescriptionFont)
                    .foregroundStyle(isPolishedLiveDriveSetup ? setupSecondaryText : Palette.cocoa)

                if showsSettingsAction {
                    Button(actionTitle) {
                        openLiveDriveSettings()
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.success)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isPolishedLiveDriveSetup ? setupSurfaceMuted.opacity(0.92) : Palette.panelAlt.opacity(0.72)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isPolishedLiveDriveSetup ? setupPanelBorder : Color.black.opacity(0.05), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func liveDriveStatusBanner(
        title: String,
        message: String,
        showsSettingsAction: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "location.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(isPolishedLiveDriveSetup ? setupPrimaryText : Palette.ink)

            Text(message)
                .font(panelDescriptionFont)
                .foregroundStyle(isPolishedLiveDriveSetup ? setupSecondaryText : Palette.cocoa)

            if showsSettingsAction {
                Button {
                    openLiveDriveSettings()
                } label: {
                    Label("Open Settings", systemImage: "gearshape.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Palette.success, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background((isPolishedLiveDriveSetup ? setupErrorFill : Palette.dangerBackground.opacity(0.45)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isPolishedLiveDriveSetup ? setupErrorBorder : Palette.danger.opacity(0.18), lineWidth: 1)
        }
    }

    private func routePreviewSection(routes: [RouteEstimate], selectedRoute: RouteEstimate) -> some View {
        Group {
            if isMobileLayout {
                VStack(alignment: .leading, spacing: 7) {
                    routeOptionsPanel(routes: routes, selectedRoute: selectedRoute)
                    routeMapPanel(routes: routes, selectedRoute: selectedRoute)
                }
            } else {
                HStack(alignment: .top, spacing: Layout.innerSpacing) {
                    routeOptionsPanel(routes: routes, selectedRoute: selectedRoute)
                        .frame(width: Layout.sidePanelWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 10) {
                        routeMapPanel(routes: routes, selectedRoute: selectedRoute)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(isMobileLayout ? 8 : 14)
        .background((usesDarkLiveDriveTheme ? setupSurfaceRaised : Palette.panel), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder, lineWidth: 1)
        }
        .shadow(color: usesDarkLiveDriveTheme ? setupShadowColor : .black.opacity(0.08), radius: 25, y: 10)
    }

    private func routeOptionsPanel(routes: [RouteEstimate], selectedRoute: RouteEstimate) -> some View {
        VStack(alignment: .leading, spacing: isMobileLayout ? 7 : 10) {
            Text("Route options")
                .font(panelHeaderFont)
                .foregroundStyle(usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink)

            VStack(spacing: isMobileLayout ? 6 : 8) {
                ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                    routeOptionCard(route: route, index: index, isSelected: route.id == selectedRoute.id)
                }
            }
        }
    }

    private func routeMapPanel(routes: [RouteEstimate], selectedRoute: RouteEstimate) -> some View {
        VStack(alignment: .leading, spacing: isMobileLayout ? 7 : 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Route preview")
                    .font(panelHeaderFont)
                    .foregroundStyle(usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink)
                Text(selectedRoute.routeName.isEmpty ? "\(selectedRoute.sourceName) to \(selectedRoute.destinationName)" : selectedRoute.routeName)
                    .font(panelDescriptionFont)
                    .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)
            }

            mapPreview(routes, selectedRoute.id)
                .frame(minHeight: isMobileLayout ? 190 : 280, maxHeight: isMobileLayout ? 214 : 348)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .background((usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder, lineWidth: 1)
                }
                .shadow(color: usesDarkLiveDriveTheme ? setupShadowColor : .black.opacity(0.10), radius: 30, y: 12)

            if isMobileLayout {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        StatPill(title: "Selected route", value: "\(Self.milesString(selectedRoute.distanceMiles)) mi", foreground: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, background: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.pill, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder.opacity(0.5))
                        StatPill(title: "Apple ETA", value: Self.durationString(selectedRoute.expectedTravelMinutes), foreground: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, background: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.pill, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder.opacity(0.5))
                        StatPill(title: "Options", value: "\(routes.count)", foreground: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, background: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.pill, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder.opacity(0.5))
                    }
                }
            } else {
                HStack(spacing: 10) {
                    StatPill(title: "Selected route", value: "\(Self.milesString(selectedRoute.distanceMiles)) mi", foreground: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, background: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.pill, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder.opacity(0.5))
                    StatPill(title: "Apple ETA", value: Self.durationString(selectedRoute.expectedTravelMinutes), foreground: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, background: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.pill, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder.opacity(0.5))
                    StatPill(title: "Options", value: "\(routes.count)", foreground: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, background: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.pill, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder.opacity(0.5))
                }
            }
        }
    }

    private func routeOptionCard(route: RouteEstimate, index: Int, isSelected: Bool) -> some View {
        let isHovered = hoveredRouteID == route.id
        let row = Button {
            selectedRouteID = route.id
            refreshRouteWeather(for: route)
        } label: {
            RouteOptionRow(
                title: index == 0 ? "Fastest" : "Option \(index + 1)",
                duration: Self.durationString(route.expectedTravelMinutes),
                distance: "\(Self.milesString(route.distanceMiles)) mi",
                isSelected: isSelected,
                isHovered: isHovered,
                compact: isMobileLayout,
                usesDarkTheme: usesDarkLiveDriveTheme
            )
        }
        .buttonStyle(.plain)

        return hoveredRouteButton(row, routeID: route.id)
    }

    @ViewBuilder
    private func hoveredRouteButton<Content: View>(_ content: Content, routeID: UUID) -> some View {
        content
    }

    private func makeCompletedTripRecord() -> CompletedTripRecord? {
        if isRouteFreeLoggingMode || liveDriveRouteContext == nil {
            let averageTripSpeed = tracker.tripDuration > 0
                ? tracker.distanceTraveled / (tracker.tripDuration / 60)
                : tracker.analysisResult.averageTripSpeed

            return CompletedTripRecord(
                completedAt: Date(),
                sourceName: "Current Location",
                destinationName: "No destination",
                routeLabel: "Free Drive",
                baselineRouteETAMinutes: 0,
                baselineRouteDistanceMiles: 0,
                distanceDrivenMiles: tracker.distanceTraveled,
                elapsedDriveMinutes: tracker.tripDuration,
                averageTripSpeed: averageTripSpeed,
                topSpeedMPH: tracker.topSpeed > 0 ? tracker.topSpeed : nil,
                timeSavedBySpeeding: tracker.tripSummary.timeSavedBySpeeding,
                timeLostBelowTargetPace: tracker.tripSummary.timeLostBelowTargetPace,
                netTimeGain: 0,
                speedLimitMeasuredMinutes: tracker.analysisResult.speedLimitMeasuredMinutes,
                speedLimitUnavailableMinutes: tracker.analysisResult.speedLimitUnavailableMinutes
            )
        }

        guard let routeContext = liveDriveRouteContext else { return nil }

        let selectedRoute = routeContext.selectedRoute
        let sourceName = selectedRoute?.sourceName ?? routeContext.routeLabel
        let destinationName = selectedRoute?.destinationName ?? "Destination"
        let averageTripSpeed = tracker.tripDuration > 0
            ? tracker.distanceTraveled / (tracker.tripDuration / 60)
            : tracker.analysisResult.averageTripSpeed

        return CompletedTripRecord(
            completedAt: Date(),
            sourceName: sourceName,
            destinationName: destinationName,
            routeLabel: routeContext.routeLabel,
            baselineRouteETAMinutes: routeContext.baselineRouteETAMinutes,
            baselineRouteDistanceMiles: routeContext.baselineRouteDistanceMiles,
            distanceDrivenMiles: tracker.distanceTraveled,
            elapsedDriveMinutes: tracker.tripDuration,
            averageTripSpeed: averageTripSpeed,
            topSpeedMPH: tracker.topSpeed > 0 ? tracker.topSpeed : nil,
            timeSavedBySpeeding: tracker.tripSummary.timeSavedBySpeeding,
            timeLostBelowTargetPace: tracker.tripSummary.timeLostBelowTargetPace,
            netTimeGain: tracker.tripSummary.netTimeGain,
            speedLimitMeasuredMinutes: tracker.analysisResult.speedLimitMeasuredMinutes,
            speedLimitUnavailableMinutes: tracker.analysisResult.speedLimitUnavailableMinutes
        )
    }

    private func finishedTripShareText(for completedTrip: CompletedTripRecord) -> String {
        if !completedTrip.hasRouteBaseline {
            return """
            TimeThrottle trip result
            \(completedTrip.displayRouteTitle)
            Completed: \(completedTrip.completedAt.formatted(date: .abbreviated, time: .shortened))
            Trip type: Free Drive
            Distance driven: \(Self.milesString(completedTrip.distanceDrivenMiles)) mi
            Elapsed drive time: \(Self.durationString(completedTrip.elapsedDriveMinutes))
            Average trip speed: \(Self.speedString(completedTrip.averageTripSpeed)) mph
            Top speed: \(Self.topSpeedString(completedTrip.topSpeedMPH))
            Time Above Speed Limit: \(Self.speedLimitMetricString(completedTrip.timeSavedBySpeeding, measuredMinutes: completedTrip.speedLimitMeasuredMinutes))
            Time Below Speed Limit: \(Self.speedLimitMetricString(completedTrip.timeLostBelowTargetPace, measuredMinutes: completedTrip.speedLimitMeasuredMinutes))
            """
        }

        return """
        TimeThrottle trip result
        \(completedTrip.displayRouteTitle)
        Completed: \(completedTrip.completedAt.formatted(date: .abbreviated, time: .shortened))
        Apple ETA baseline: \(Self.durationString(completedTrip.baselineRouteETAMinutes))
        Overall vs Apple ETA: \(Self.netString(completedTrip.netTimeGain))
        Time Above Speed Limit: \(Self.speedLimitMetricString(completedTrip.timeSavedBySpeeding, measuredMinutes: completedTrip.speedLimitMeasuredMinutes))
        Time Below Speed Limit: \(Self.speedLimitMetricString(completedTrip.timeLostBelowTargetPace, measuredMinutes: completedTrip.speedLimitMeasuredMinutes))
        Distance driven: \(Self.milesString(completedTrip.distanceDrivenMiles)) mi
        Elapsed drive time: \(Self.durationString(completedTrip.elapsedDriveMinutes))
        Average trip speed: \(Self.speedString(completedTrip.averageTripSpeed)) mph
        Top speed: \(Self.topSpeedString(completedTrip.topSpeedMPH))
        """
    }

    private func finishedTripMetricExplanation(for completedTrip: CompletedTripRecord) -> String {
        guard completedTrip.hasRouteBaseline else {
            return "Free Drive trips save distance, elapsed time, speed, and speed-limit time above/below where available. No Apple Maps ETA comparison is created without a route."
        }

        let baselineETA = Self.durationString(completedTrip.baselineRouteETAMinutes)
        return "Overall vs Apple ETA compares the whole trip to Apple Maps' baseline ETA of \(baselineETA). Time Above Speed Limit and Time Below Speed Limit are measured against available OpenStreetMap speed-limit estimates. Speed-limit analysis only includes route segments where an estimate was available."
    }

    private func exportAllTrips() {
        guard !tripHistoryStore.trips.isEmpty else { return }

        switch selectedTripExportFormat {
        case .csv:
            do {
                let fileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("TimeThrottle-Trips-\(Self.exportTimestamp()).csv")
                try allTripsCSV().write(to: fileURL, atomically: true, encoding: .utf8)
                shareSheetItems = [fileURL]
            } catch {
                shareSheetItems = [allTripsSummaryText()]
            }
        case .summary:
            shareSheetItems = [allTripsSummaryText()]
        }

        if isMapOptionsPresented {
            isMapOptionsPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isShareSheetPresented = true
            }
        } else {
            isShareSheetPresented = true
        }
    }

    private func allTripsSummaryText() -> String {
        let lines = tripHistoryStore.trips.map { trip in
            var parts = [
                trip.displayRouteTitle,
                "Completed: \(trip.completedAt.formatted(date: .abbreviated, time: .shortened))",
                "Trip type: \(trip.hasRouteBaseline ? "Routed" : "Free Drive")",
                "Distance driven: \(Self.milesString(trip.distanceDrivenMiles)) mi",
                "Elapsed drive time: \(Self.durationString(trip.elapsedDriveMinutes))",
                "Average trip speed: \(Self.speedString(trip.averageTripSpeed)) mph",
                "Top speed: \(Self.topSpeedString(trip.topSpeedMPH))",
                "Time Above Speed Limit: \(Self.speedLimitMetricString(trip.timeSavedBySpeeding, measuredMinutes: trip.speedLimitMeasuredMinutes))",
                "Time Below Speed Limit: \(Self.speedLimitMetricString(trip.timeLostBelowTargetPace, measuredMinutes: trip.speedLimitMeasuredMinutes))"
            ]

            if trip.hasRouteBaseline {
                parts.append("Apple ETA baseline: \(Self.durationString(trip.baselineRouteETAMinutes))")
                parts.append("Overall vs Apple ETA: \(Self.netString(trip.netTimeGain))")
            }

            return parts.joined(separator: "\n")
        }

        return "TimeThrottle trip export\n\n" + lines.joined(separator: "\n\n---\n\n")
    }

    private func allTripsCSV() -> String {
        let header = [
            "completed_at",
            "trip_type",
            "source",
            "destination",
            "route_label",
            "distance_driven_miles",
            "elapsed_drive_minutes",
            "average_speed_mph",
            "top_speed_mph",
            "time_above_speed_limit_minutes",
            "time_below_speed_limit_minutes",
            "apple_eta_minutes",
            "overall_vs_apple_eta_minutes"
        ]
        let formatter = ISO8601DateFormatter()
        let rows = tripHistoryStore.trips.map { trip in
            [
                formatter.string(from: trip.completedAt),
                trip.hasRouteBaseline ? "Routed" : "Free Drive",
                trip.sourceName,
                trip.destinationName,
                trip.routeLabel,
                Self.csvNumber(trip.distanceDrivenMiles),
                Self.csvNumber(trip.elapsedDriveMinutes),
                Self.csvNumber(trip.averageTripSpeed),
                trip.topSpeedMPH.map(Self.csvNumber) ?? "",
                trip.speedLimitMeasuredMinutes > 0 ? Self.csvNumber(trip.timeSavedBySpeeding) : "",
                trip.speedLimitMeasuredMinutes > 0 ? Self.csvNumber(trip.timeLostBelowTargetPace) : "",
                trip.hasRouteBaseline ? Self.csvNumber(trip.baselineRouteETAMinutes) : "",
                trip.hasRouteBaseline ? Self.csvNumber(trip.netTimeGain) : ""
            ].map(Self.csvEscape).joined(separator: ",")
        }

        return ([header.joined(separator: ",")] + rows).joined(separator: "\n")
    }

    private static func exportTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func openRouteSetupPanel() {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            isRouteSetupPanelPresented = true
        }
        currentLocationResolver.requestCurrentLocationIfNeeded()
        refreshPassiveMapLayersIfPossible(force: false)
    }

    private func presentTripHistorySheet() {
        presentMapSheet(.tripHistory)
    }

    private func presentScannerSheet() {
        presentMapSheet(.scanner)
    }

    private func presentMapSheet(_ destination: LiveDriveSheetDestination) {
        if isMapOptionsPresented {
            isMapOptionsPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                presentedSheetDestination = destination
            }
        } else {
            presentedSheetDestination = destination
        }
    }

    private static func csvNumber(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private func liveDriveMetricCard(
        title: String,
        value: String,
        tint: Color,
        emphasis: LiveDriveMetricEmphasis = .standard
    ) -> some View {
        let valueFont: Font
        let padding: CGFloat

        switch emphasis {
        case .standard:
            valueFont = .system(size: 26, weight: .bold, design: .rounded)
            padding = 16
        case .strong:
            valueFont = .system(size: 30, weight: .bold, design: .rounded)
            padding = 16
        case .hero:
            valueFont = .system(size: 54, weight: .bold, design: .rounded)
            padding = 18
        }

        return VStack(alignment: .leading, spacing: emphasis == .hero ? 10 : 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.cocoa)

            Text(value)
                .font(valueFont)
                .foregroundStyle(tint)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(emphasis == .hero ? tint.opacity(0.20) : Palette.surfaceBorder, lineWidth: emphasis == .hero ? 1.5 : 1)
        }
        .shadow(color: .black.opacity(0.08), radius: emphasis == .hero ? 28 : 22, y: emphasis == .hero ? 12 : 8)
    }

    private func liveDriveSummaryBlock(
        title: String,
        value: String,
        tint: Color,
        isNarrative: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)

            Text(value)
                .font(isNarrative ? .title3.weight(.bold) : .system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var liveDriveExpectedArrivalText: String {
        guard let arrival = tracker.expectedArrivalTime else {
            return "Waiting for enough route progress"
        }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = liveDriveArrivalDisplayTimeZone ?? .autoupdatingCurrent
        return formatter.string(from: arrival)
    }

    private var liveDriveArrivalDisplayTimeZone: TimeZone? {
        liveDriveCapturedRoute?.destinationTimeZone
            ?? liveDriveSetupRoute?.destinationTimeZone
    }

    private func liveDriveVerdict(for netTimeGain: Double) -> String {
        if netTimeGain > 10 {
            return "Overall, you finished comfortably ahead of the Apple Maps ETA."
        }

        if netTimeGain > 0 {
            return "Overall, you finished slightly ahead of the Apple Maps ETA."
        }

        if abs(netTimeGain) < 0.01 {
            return "Overall, you matched the Apple Maps ETA."
        }

        return "Overall, you finished behind the Apple Maps ETA."
    }

    private var liveDriveVerdict: String {
        liveDriveVerdict(for: liveDriveDisplayedNetTimeGain)
    }

    private var liveDriveVerdictTint: Color {
        liveDriveDisplayedNetTimeGain > 0 ? Palette.success : Palette.danger
    }

    private func startLiveDrive() {
        guard let configuration = liveDriveConfigurationForStart,
              let selectedRoute = liveDriveSetupRoute else { return }
        isRouteFreeLoggingMode = false
        liveDriveFinishedTrip = nil
        liveDriveRouteContext = LiveDriveRouteContext(
            routes: liveDriveSetupRouteOptions,
            selectedRouteID: selectedRoute.id,
            routeLabel: liveDriveCurrentRouteLabel,
            baselineRouteETAMinutes: selectedRoute.expectedTravelMinutes,
            baselineRouteDistanceMiles: selectedRoute.distanceMiles
        )
        liveDriveNavigationHandoffMessage = nil
        liveDriveNavigationProviderPending = preferredNavigationProvider
        tracker.configuration = configuration
        speedLimitDisplayText = "Unavailable"
        speedLimitDetailText = "OpenStreetMap estimate"
        tracker.updateSpeedLimitEstimate(nil)
        isRouteWeatherVisible = false
        guidanceRerouteMessage = nil
        aircraftStatusText = showsAircraftLayer ? "Checking" : "Off"
        enforcementAlerts = []
        enforcementAlertsLastUpdatedAt = nil
        enforcementAlertStatusText = areEnforcementAlertsEnabled ? "Checking" : "Off"
        spokenCameraAlertThresholds = [:]
        spokenAircraftAlertHistory = [:]
        guidanceEngine.loadRoute(
            steps: selectedRoute.maneuverSteps,
            routeDistanceMeters: selectedRoute.distanceMiles * 1_609.344,
            destination: GuidanceCoordinate(
                latitude: selectedRoute.destinationCoordinate.latitude,
                longitude: selectedRoute.destinationCoordinate.longitude
            )
        )
        applyStoredVoiceSettings()
        withAnimation(.snappy(duration: 0.28, extraBounce: 0)) {
            tracker.startTrip(requiresBackgroundContinuation: true)
            isRouteSetupPanelPresented = false
        }

        if tracker.isTracking {
            processLiveDriveNavigationHandoffIfNeeded()
            if areEnforcementAlertsEnabled, let coordinate = tracker.currentCoordinate {
                refreshEnforcementAlerts(near: coordinate, force: true)
            }
        }
    }

    private func startRouteFreeLogging() {
        liveDriveFinishedTrip = nil
        liveDriveRouteContext = nil
        liveDriveNavigationProviderPending = nil
        liveDriveNavigationHandoffMessage = nil
        isNavigationProviderChoicePresented = false
        isRouteFreeLoggingMode = true
        tracker.configuration = LiveDriveConfiguration()
        speedLimitDisplayText = "Unavailable"
        speedLimitDetailText = "OpenStreetMap estimate"
        tracker.updateSpeedLimitEstimate(nil)
        guidanceEngine.reset()
        guidanceRerouteMessage = nil
        aircraftStatusText = showsAircraftLayer ? "Checking" : "Off"
        enforcementAlerts = []
        enforcementAlertsLastUpdatedAt = nil
        enforcementAlertStatusText = areEnforcementAlertsEnabled ? "Checking" : "Off"
        spokenCameraAlertThresholds = [:]
        spokenAircraftAlertHistory = [:]
        applyStoredVoiceSettings()

        withAnimation(.snappy(duration: 0.28, extraBounce: 0)) {
            tracker.startTrip(requiresBackgroundContinuation: true)
            isRouteSetupPanelPresented = false
        }

        if areEnforcementAlertsEnabled, let coordinate = tracker.currentCoordinate ?? passiveMapCoordinate {
            refreshEnforcementAlerts(near: coordinate, force: true)
        }

        if isRouteWeatherVisible, let coordinate = tracker.currentCoordinate ?? passiveMapCoordinate {
            refreshCurrentWeather(near: coordinate, force: true)
        }
    }

    private func pauseLiveDrive() {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            tracker.pauseTrip()
        }
    }

    private func resumeLiveDrive() {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            tracker.resumeTrip()
        }
    }

    private func endLiveDrive() {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            let finalCoordinate = tracker.currentCoordinate
            liveDriveNavigationProviderPending = nil
            liveDriveNavigationHandoffMessage = nil
            isNavigationProviderChoicePresented = false
            tracker.endTrip()
            finalizeCompletedTrip()
            liveDriveRouteContext = nil
            guidanceEngine.reset()
            routeWeatherRouteID = nil
            routeWeatherEntries = []
            routeWeatherMessage = "Forecast unavailable"
            isRouteWeatherLoading = false
            speedLimitDisplayText = "Unavailable"
            speedLimitDetailText = "OpenStreetMap estimate"
            tracker.updateSpeedLimitEstimate(nil)
            guidanceRerouteMessage = nil
            isGuidanceRerouting = false
            enforcementAlerts = []
            enforcementAlertsLastUpdatedAt = nil
            lastEnforcementAlertLookupAt = nil
            lastEnforcementAlertLookupCoordinate = nil
            lastEnforcementAlertRouteContextID = nil
            enforcementAlertStatusText = areEnforcementAlertsEnabled ? "Checking" : "Off"
            spokenCameraAlertThresholds = [:]
            isRouteSetupPanelPresented = false

            if areEnforcementAlertsEnabled, let finalCoordinate {
                refreshEnforcementAlerts(near: finalCoordinate, force: true)
            }
        }
    }

    private func startNewLiveDrive() {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            liveDriveRouteContext = nil
            liveDriveNavigationProviderPending = nil
            liveDriveNavigationHandoffMessage = nil
            liveDriveFinishedTrip = nil
            isRouteFreeLoggingMode = false
            isNavigationProviderChoicePresented = false
            tracker.resetTrip()
            guidanceEngine.reset()
            speedLimitDisplayText = "Unavailable"
            speedLimitDetailText = "OpenStreetMap estimate"
            tracker.updateSpeedLimitEstimate(nil)
            guidanceRerouteMessage = nil
            isGuidanceRerouting = false
            aircraftLayer = AircraftLayerState(isVisible: showsAircraftLayer)
            aircraftStatusText = showsAircraftLayer ? "Checking" : "Off"
            enforcementAlerts = []
            enforcementAlertsLastUpdatedAt = nil
            lastEnforcementAlertLookupAt = nil
            lastEnforcementAlertLookupCoordinate = nil
            lastEnforcementAlertRouteContextID = nil
            enforcementAlertStatusText = areEnforcementAlertsEnabled ? "Checking" : "Off"
            spokenCameraAlertThresholds = [:]
            spokenAircraftAlertHistory = [:]
            isRouteSetupPanelPresented = true
        }
    }

    private func resetCurrentTripCounters() {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            liveDriveRouteContext = nil
            liveDriveNavigationProviderPending = nil
            liveDriveNavigationHandoffMessage = nil
            liveDriveFinishedTrip = nil
            isRouteFreeLoggingMode = false
            isNavigationProviderChoicePresented = false
            tracker.resetTrip()
            guidanceEngine.reset()
            speedLimitDisplayText = "Unavailable"
            speedLimitDetailText = "OpenStreetMap estimate"
            tracker.updateSpeedLimitEstimate(nil)
            guidanceRerouteMessage = nil
            isGuidanceRerouting = false
            isMapOptionsPresented = false
            isRouteSetupPanelPresented = false
        }
    }

    private func processLiveDriveNavigationHandoffIfNeeded() {
        guard tracker.isTracking, let provider = liveDriveNavigationProviderPending else { return }

        guard let route = liveDriveCapturedRoute ?? liveDriveSetupRoute else {
            liveDriveNavigationProviderPending = nil
            liveDriveNavigationHandoffMessage = "No route is ready for navigation handoff."
            return
        }

        guard tracker.permissionState.supportsBackgroundContinuation else {
            switch tracker.permissionState {
            case .authorizedWhenInUse, .notDetermined:
                tracker.requestBackgroundContinuationAuthorization()
                liveDriveNavigationHandoffMessage = pendingBackgroundContinuationMessage(for: provider)
            case .denied, .restricted:
                liveDriveNavigationProviderPending = nil
                liveDriveNavigationHandoffMessage = blockedNavigationHandoffMessage(for: provider)
            case .authorizedAlways:
                break
            }
            return
        }

        switch provider {
        case .askEveryTime:
            liveDriveNavigationProviderPending = nil
            completeLiveDriveNavigationHandoff(using: .appleMaps)
        case .appleMaps, .googleMaps, .waze:
            liveDriveNavigationProviderPending = nil
            Task {
                let outcome = await NavigationHandoffService.handoff(provider: provider, route: route)
                await MainActor.run {
                    liveDriveNavigationHandoffMessage = outcome.userFacingMessage
                }
            }
        }
    }

    private func completeLiveDriveNavigationHandoff(using provider: NavigationProvider) {
        guard let route = liveDriveCapturedRoute ?? liveDriveSetupRoute else {
            liveDriveNavigationHandoffMessage = "No route is ready for navigation handoff."
            return
        }

        guard tracker.permissionState.supportsBackgroundContinuation else {
            switch tracker.permissionState {
            case .authorizedWhenInUse, .notDetermined:
                liveDriveNavigationProviderPending = provider
                tracker.requestBackgroundContinuationAuthorization()
                liveDriveNavigationHandoffMessage = pendingBackgroundContinuationMessage(for: provider)
            case .denied, .restricted:
                liveDriveNavigationHandoffMessage = blockedNavigationHandoffMessage(for: provider)
            case .authorizedAlways:
                break
            }
            return
        }

        isNavigationProviderChoicePresented = false
        liveDriveNavigationProviderPending = nil

        Task {
            let outcome = await NavigationHandoffService.handoff(provider: provider, route: route)
            await MainActor.run {
                liveDriveNavigationHandoffMessage = outcome.userFacingMessage
            }
        }
    }

    private func blockedNavigationHandoffMessage(for provider: NavigationProvider) -> String {
        switch provider {
        case .appleMaps:
            return "Apple Maps did not open because Always Location is required for background tracking. Tracking is still active in TimeThrottle."
        case .googleMaps:
            return "Google Maps did not open because Always Location is required for background tracking. Tracking is still active in TimeThrottle."
        case .waze:
            return "Waze did not open because Always Location is required for background tracking. Tracking is still active in TimeThrottle."
        case .askEveryTime:
            return "External navigation did not open because Always Location is required for background tracking. Tracking is still active in TimeThrottle."
        }
    }

    private func pendingBackgroundContinuationMessage(for provider: NavigationProvider) -> String {
        switch provider {
        case .appleMaps:
            return "Apple Maps will open after Always Location is enabled. Until then, stay in TimeThrottle."
        case .googleMaps:
            return "Google Maps will open after Always Location is enabled. Until then, stay in TimeThrottle."
        case .waze:
            return "Waze will open after Always Location is enabled. Until then, stay in TimeThrottle."
        case .askEveryTime:
            return "Choose an external navigation app after Always Location is enabled."
        }
    }

    private func finalizeCompletedTrip() {
        guard let completedTrip = makeCompletedTripRecord() else { return }
        liveDriveFinishedTrip = completedTrip
        tripHistoryStore.save(completedTrip)
    }

    private func shareFinishedTrip() {
        guard let completedTrip = liveDriveFinishedTrip else { return }
        let shareText = finishedTripShareText(for: completedTrip)

        #if os(iOS)
        if let shareImage = finishedTripShareImage(for: completedTrip) {
            shareSheetItems = [shareImage, shareText]
        } else {
            shareSheetItems = [shareText]
        }
        #else
        shareSheetItems = [shareText]
        #endif

        isShareSheetPresented = true
    }

    #if os(iOS)
    @MainActor
    private func finishedTripShareImage(for completedTrip: CompletedTripRecord) -> UIImage? {
        let shareCardWidth: CGFloat = 405
        let shareCardHeight: CGFloat = 720

        let shareCard = FinishedTripShareCardView(
            brandLogo: brandLogo,
            routeTitle: completedTrip.displayRouteTitle,
            routeMeta: completedTrip.routeLabel,
            completedAtText: completedTrip.completedAt.formatted(date: .abbreviated, time: .shortened),
            overallResultTitle: completedTrip.hasRouteBaseline ? "Overall vs Apple ETA" : "Free Drive",
            overallResultValue: completedTrip.hasRouteBaseline ? Self.netString(completedTrip.netTimeGain) : "\(Self.milesString(completedTrip.distanceDrivenMiles)) mi",
            overallResultTint: completedTrip.hasRouteBaseline ? (completedTrip.netTimeGain >= 0 ? Palette.success : Palette.danger) : Palette.success,
            overallResultDetail: completedTrip.hasRouteBaseline ? liveDriveVerdict(for: completedTrip.netTimeGain) : "No Apple Maps ETA comparison for route-free logging.",
            metrics: [
                ShareCardMetric(title: "Time Above Speed Limit", value: Self.speedLimitMetricString(completedTrip.timeSavedBySpeeding, measuredMinutes: completedTrip.speedLimitMeasuredMinutes), tint: Palette.success),
                ShareCardMetric(title: "Time Below Speed Limit", value: Self.speedLimitMetricString(completedTrip.timeLostBelowTargetPace, measuredMinutes: completedTrip.speedLimitMeasuredMinutes), tint: Palette.danger),
                ShareCardMetric(title: "Distance driven", value: "\(Self.milesString(completedTrip.distanceDrivenMiles)) mi", tint: .white),
                ShareCardMetric(title: "Elapsed drive time", value: Self.durationString(completedTrip.elapsedDriveMinutes), tint: .white),
                ShareCardMetric(title: "Average trip speed", value: "\(Self.speedString(completedTrip.averageTripSpeed)) mph", tint: .white),
                ShareCardMetric(title: "Top speed", value: Self.topSpeedString(completedTrip.topSpeedMPH), tint: .white)
            ]
        )
        .frame(width: shareCardWidth, height: shareCardHeight)

        let renderer = ImageRenderer(content: shareCard)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: shareCardWidth, height: shareCardHeight)
        return renderer.uiImage
    }
    #endif

    private func openLiveDriveSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(settingsURL) else {
            return
        }

        UIApplication.shared.open(settingsURL)
    }

    private func handleFromAddressTextChanged(_ newValue: String) {
        guard routeOriginInputMode == .custom else { return }

        routeErrorMessage = nil

        if fromResolvedPlace?.displayText == newValue {
            return
        }

        fromResolvedPlace = nil
        resetCalculatedRouteState()

        if focusedRouteAddressField == .from {
            autocompleteController.updateQuery(newValue, for: .from)
        }
    }

    private func handleToAddressTextChanged(_ newValue: String) {
        routeErrorMessage = nil

        if toResolvedPlace?.displayText == newValue {
            return
        }

        toResolvedPlace = nil
        resetCalculatedRouteState()

        if focusedRouteAddressField == .to {
            autocompleteController.updateQuery(newValue, for: .to)
        }
    }

    private func clearDestinationField() {
        toAddressText = ""
        toResolvedPlace = nil
        focusedRouteAddressField = .to
        autocompleteController.clear(field: .to)
        resetCalculatedRouteState()
    }

    private func handleAddressFieldSubmit(_ field: RouteAddressField) {
        switch field {
        case .from:
            focusedRouteAddressField = .to
            autocompleteController.clear(field: .from)
        case .to:
            focusedRouteAddressField = nil
            autocompleteController.clear(field: .to)

            if !isCalculateRouteDisabled {
                calculateAppleMapsRoute()
            }
        }
    }

    private func selectAutocompleteSuggestion(
        _ suggestion: AppleMapsAutocompleteController.Suggestion,
        for field: RouteAddressField
    ) {
        Task {
            do {
                let resolvedPlace = try await autocompleteController.resolve(suggestion)

                await MainActor.run {
                    applyResolvedPlace(resolvedPlace, to: field)
                }
            } catch {
                await MainActor.run {
                    routeErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func applyResolvedPlace(_ place: ResolvedRoutePlace, to field: RouteAddressField) {
        routeErrorMessage = nil
        autocompleteController.clear()

        switch field {
        case .from:
            fromResolvedPlace = place
            fromAddressText = place.displayText
            focusedRouteAddressField = .to
        case .to:
            toResolvedPlace = place
            toAddressText = place.displayText
            focusedRouteAddressField = nil
        }

        if !isCalculateRouteDisabled {
            calculateAppleMapsRoute()
        }
    }

    private func resetCalculatedRouteState() {
        routeLookupGeneration += 1
        routeOptions = []
        selectedRouteID = nil
        hoveredRouteID = nil
        routeErrorMessage = nil
        isCalculatingRoute = false
        routeWeatherRouteID = nil
        routeWeatherEntries = []
        routeWeatherMessage = "Forecast unavailable"
        isRouteWeatherLoading = false
        spokenCameraAlertThresholds = [:]
    }

    private func calculateAppleMapsRoute() {
        routeErrorMessage = nil

        guard let sourceEndpoint = routeSourceEndpoint else {
            resetCalculatedRouteState()
            routeErrorMessage = routeOriginInputMode == .currentLocation
                ? RouteLookupError.currentLocationUnavailable.localizedDescription
                : RouteLookupError.blankAddress("starting").localizedDescription
            return
        }

        guard let destinationEndpoint = routeDestinationEndpoint else {
            resetCalculatedRouteState()
            routeErrorMessage = RouteLookupError.blankAddress("destination").localizedDescription
            return
        }

        let lookupGeneration = routeLookupGeneration + 1
        routeLookupGeneration = lookupGeneration
        isCalculatingRoute = true

        Task {
            do {
                let estimates = try await RouteLookupService.fetchRouteOptions(
                    source: sourceEndpoint,
                    destination: destinationEndpoint
                )

                await MainActor.run {
                    guard lookupGeneration == routeLookupGeneration else { return }
                    routeOptions = estimates
                    selectedRouteID = estimates.first?.id
                    hoveredRouteID = nil
                    routeErrorMessage = nil
                    isCalculatingRoute = false
                    if let firstRoute = estimates.first {
                        refreshRouteWeather(for: firstRoute)
                    }
                }
            } catch {
                await MainActor.run {
                    guard lookupGeneration == routeLookupGeneration else { return }
                    resetCalculatedRouteState()
                    routeErrorMessage = error.localizedDescription
                    isCalculatingRoute = false
                }
            }
        }
    }

    private func refreshRouteWeather(for route: RouteEstimate) {
        guard isRouteWeatherVisible else {
            routeWeatherRouteID = nil
            routeWeatherEntries = []
            routeWeatherMessage = "Forecast hidden"
            isRouteWeatherLoading = false
            return
        }

        routeWeatherRouteID = route.id
        routeWeatherEntries = []
        routeWeatherMessage = "Loading route forecast..."

        isRouteWeatherLoading = true
        let routeID = route.id
        let routeGeometry = route.routeCoordinates.map {
            GuidanceCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
        let routeDistanceMeters = route.distanceMiles * 1_609.344
        let expectedTravelSeconds = route.expectedTravelMinutes * 60
        let timeZone = route.destinationTimeZone ?? .autoupdatingCurrent
        let checkpointCount = WeatherRouteProvider.recommendedCheckpointCount(forDistanceMiles: route.distanceMiles)

        Task {
            do {
                let checkpoints = try weatherProvider.checkpoints(
                    for: routeGeometry,
                    routeDistanceMeters: routeDistanceMeters,
                    startDate: Date(),
                    expectedTravelTimeSeconds: expectedTravelSeconds,
                    maxCheckpointCount: checkpointCount
                )

                do {
                    let timeline = try await weatherProvider.timeline(for: checkpoints)
                    let displayEntries = Self.labeledWeatherEntries(
                        timeline.map { entry in
                            Self.routeWeatherDisplayEntry(from: entry, timeZone: timeZone)
                        },
                        sourceName: route.sourceName,
                        destinationName: route.destinationName
                    )

                    await MainActor.run {
                        guard routeWeatherRouteID == routeID else { return }
                        routeWeatherEntries = displayEntries
                        routeWeatherMessage = displayEntries.isEmpty ? "Forecast unavailable" : ""
                        isRouteWeatherLoading = false
                    }
                } catch {
                    let unavailableDetail = Self.routeWeatherUnavailableDetail(from: error)
                    let displayEntries = Self.labeledWeatherEntries(
                        checkpoints.map { checkpoint in
                            Self.routeWeatherUnavailableEntry(
                                from: checkpoint,
                                timeZone: timeZone,
                                detailText: unavailableDetail
                            )
                        },
                        sourceName: route.sourceName,
                        destinationName: route.destinationName
                    )

                    await MainActor.run {
                        guard routeWeatherRouteID == routeID else { return }
                        routeWeatherEntries = displayEntries
                        routeWeatherMessage = unavailableDetail
                        isRouteWeatherLoading = false
                    }
                }
            } catch {
                let unavailableDetail = Self.routeWeatherUnavailableDetail(from: error)
                await MainActor.run {
                    guard routeWeatherRouteID == routeID else { return }
                    routeWeatherEntries = []
                    routeWeatherMessage = unavailableDetail
                    isRouteWeatherLoading = false
                }
            }
        }
    }

    private func refreshCurrentWeatherIfNeeded(near coordinate: GuidanceCoordinate) {
        guard isRouteWeatherVisible, routeWeatherOptionsRoute == nil else { return }
        refreshCurrentWeather(near: coordinate, force: false)
    }

    private func refreshCurrentWeather(near coordinate: GuidanceCoordinate, force: Bool) {
        guard isRouteWeatherVisible, routeWeatherOptionsRoute == nil else { return }

        if !force,
           let lastLookupAt = lastCurrentWeatherLookupAt,
           Date().timeIntervalSince(lastLookupAt) < 900,
           let lastCoordinate = lastCurrentWeatherLookupCoordinate,
           lastCoordinate.location.distance(from: coordinate.location) < 1_609.344 {
            return
        }

        currentWeatherEntry = nil
        currentWeatherMessage = "Loading current weather..."
        isCurrentWeatherLoading = true
        lastCurrentWeatherLookupAt = Date()
        lastCurrentWeatherLookupCoordinate = coordinate

        let checkpoint = RouteWeatherCheckpoint(
            coordinate: coordinate,
            distanceFromStartMeters: 0,
            expectedArrivalDate: Date()
        )
        let lookupCoordinate = coordinate

        Task {
            do {
                let timeline = try await weatherProvider.timeline(for: [checkpoint])
                let entry = timeline.first.map {
                    Self.currentWeatherDisplayEntry(
                        from: Self.routeWeatherDisplayEntry(from: $0, timeZone: .autoupdatingCurrent)
                    )
                }

                await MainActor.run {
                    guard routeWeatherOptionsRoute == nil,
                          lastCurrentWeatherLookupCoordinate == lookupCoordinate else { return }
                    currentWeatherEntry = entry
                    currentWeatherMessage = entry == nil ? "Weather unavailable" : ""
                    isCurrentWeatherLoading = false
                }
            } catch {
                let unavailableDetail = Self.routeWeatherUnavailableDetail(from: error)
                let entry = Self.currentWeatherDisplayEntry(
                    from: Self.routeWeatherUnavailableEntry(
                        from: checkpoint,
                        timeZone: .autoupdatingCurrent,
                        detailText: unavailableDetail
                    )
                )

                await MainActor.run {
                    guard routeWeatherOptionsRoute == nil,
                          lastCurrentWeatherLookupCoordinate == lookupCoordinate else { return }
                    currentWeatherEntry = entry
                    currentWeatherMessage = unavailableDetail
                    isCurrentWeatherLoading = false
                }
            }
        }
    }

    private func toggleRouteWeatherFromOptions() {
        if isRouteWeatherVisible {
            isRouteWeatherVisible = false
            routeWeatherRouteID = nil
            routeWeatherEntries = []
            currentWeatherEntry = nil
            routeWeatherMessage = "Forecast hidden"
            currentWeatherMessage = "Weather hidden"
            isRouteWeatherLoading = false
            isCurrentWeatherLoading = false
            return
        }

        isRouteWeatherVisible = true
        if let route = routeWeatherOptionsRoute {
            refreshRouteWeather(for: route)
        } else if let coordinate = passiveMapCoordinate {
            refreshCurrentWeather(near: coordinate, force: true)
        } else {
            currentLocationResolver.requestCurrentLocationIfNeeded()
            currentWeatherMessage = "Waiting for current location."
        }
    }

    private func toggleVoiceGuidanceMute() {
        isVoiceGuidanceMuted.toggle()
        guidanceEngine.setMuted(isVoiceGuidanceMuted)
    }

    private func applyStoredVoiceSettings() {
        let resolvedIdentifier = resolvedStoredGuidanceVoiceIdentifier()

        guidanceEngine.applyVoiceSettings(
            VoiceGuidanceSettings(
                selectedVoiceIdentifier: resolvedIdentifier,
                speechRate: Float(storedGuidanceSpeechRate),
                volume: Float(storedGuidanceVolume),
                isMuted: isVoiceGuidanceMuted
            )
        )
    }

    private func resolvedStoredGuidanceVoiceIdentifier() -> String? {
        let voices = guidanceEngine.availableVoiceOptions
        let storedIdentifier = storedGuidanceVoiceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSavedVoicePreference = UserDefaults.standard.object(
            forKey: Self.guidanceVoiceIdentifierStorageKey
        ) != nil

        if !storedIdentifier.isEmpty,
           voices.contains(where: { $0.identifier == storedIdentifier }) {
            return storedIdentifier
        }

        if !hasSavedVoicePreference {
            return VoiceGuidanceVoiceCatalog.danielVoiceIdentifier(in: voices) ?? voices.first?.identifier
        }

        return nil
    }

    private func selectGuidanceVoice(_ identifier: String?) {
        storedGuidanceVoiceIdentifier = identifier ?? ""
        guidanceEngine.selectVoice(identifier: identifier)
    }

    private func setGuidanceSpeechRate(_ rate: Double) {
        storedGuidanceSpeechRate = min(max(rate, 0.38), 0.56)
        guidanceEngine.setSpeechRate(Float(storedGuidanceSpeechRate))
    }

    private func setGuidanceVolume(_ volume: Double) {
        storedGuidanceVolume = min(max(volume, 0), 1)
        guidanceEngine.applyVoiceSettings(
            VoiceGuidanceSettings(
                selectedVoiceIdentifier: guidanceEngine.voiceSettings.selectedVoiceIdentifier,
                speechRate: guidanceEngine.voiceSettings.speechRate,
                volume: Float(storedGuidanceVolume),
                isMuted: isVoiceGuidanceMuted
            )
        )
    }

    private func presentVoiceSelectionSheet() {
        if isMapOptionsPresented {
            isMapOptionsPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isVoiceSelectionPresented = true
            }
        } else {
            isVoiceSelectionPresented = true
        }
    }

    private func toggleAircraftLayer() {
        showsAircraftLayer.toggle()
        aircraftLayer = AircraftLayerState(
            isVisible: showsAircraftLayer,
            aircraft: showsAircraftLayer ? aircraftLayer.aircraft : [],
            lastUpdated: aircraftLayer.lastUpdated,
            isStale: !showsAircraftLayer ? false : aircraftLayer.isStale
        )
        aircraftStatusText = showsAircraftLayer ? "Checking" : "Off"

        if showsAircraftLayer, let coordinate = tracker.currentCoordinate {
            refreshAircraft(near: coordinate, force: true)
        } else if showsAircraftLayer, let coordinate = passiveMapCoordinate {
            refreshAircraft(near: coordinate, force: true)
        } else {
            spokenAircraftAlertHistory = [:]
        }
    }

    private func migrateNavigationProviderPreferenceIfNeeded() {
        guard NavigationProvider(rawValue: navigationProviderPreferenceRawValue) == .askEveryTime else { return }
        navigationProviderPreferenceRawValue = NavigationProvider.appleMaps.rawValue
    }

    private func prepareInactiveMapIfNeeded(forceRefresh: Bool) {
        guard liveDriveScreenState != .driving else { return }

        currentLocationResolver.requestCurrentLocationIfNeeded()
        refreshPassiveMapLayersIfPossible(force: forceRefresh)
    }

    private func refreshPassiveMapLayersIfPossible(force: Bool) {
        guard liveDriveScreenState != .driving, let coordinate = passiveMapCoordinate else { return }

        if showsAircraftLayer {
            refreshAircraft(near: coordinate, force: force)
        }

        if areEnforcementAlertsEnabled {
            refreshEnforcementAlerts(near: coordinate, force: force)
        }

        if isRouteWeatherVisible, routeWeatherOptionsRoute == nil {
            refreshCurrentWeather(near: coordinate, force: force)
        }
    }

    private func refreshSpeedLimitIfNeeded(near coordinate: GuidanceCoordinate) {
        let now = Date()
        if let lastSpeedLimitLookupAt, now.timeIntervalSince(lastSpeedLimitLookupAt) < 45 {
            return
        }
        lastSpeedLimitLookupAt = now

        Task {
            do {
                let result = try await speedLimitProvider.currentSpeedLimitResult(near: coordinate)
                await MainActor.run {
                    if let result {
                        speedLimitDisplayText = "\(result.currentSpeedLimitMPH) mph"
                        speedLimitDetailText = Self.speedLimitDetailText(from: result)
                        tracker.updateSpeedLimitEstimate(result.currentSpeedLimitMPH)
                    } else {
                        speedLimitDisplayText = "Unavailable"
                        speedLimitDetailText = "OpenStreetMap estimate"
                        tracker.updateSpeedLimitEstimate(nil)
                    }
                }
            } catch {
                await MainActor.run {
                    speedLimitDisplayText = "Unavailable"
                    speedLimitDetailText = "OpenStreetMap estimate"
                    tracker.updateSpeedLimitEstimate(nil)
                }
            }
        }
    }

    private func refreshAircraftIfNeeded(near coordinate: GuidanceCoordinate) {
        guard showsAircraftLayer else { return }
        let now = Date()
        pruneStaleAircraftIfNeeded(now: now)

        if let lastAircraftPollAt, now.timeIntervalSince(lastAircraftPollAt) < aircraftRefreshIntervalSeconds {
            return
        }
        refreshAircraft(near: coordinate, force: false)
    }

    private func refreshAircraft(near coordinate: GuidanceCoordinate, force: Bool) {
        let now = Date()
        pruneStaleAircraftIfNeeded(now: now)

        if !force, let lastAircraftPollAt, now.timeIntervalSince(lastAircraftPollAt) < aircraftRefreshIntervalSeconds {
            return
        }
        lastAircraftPollAt = now

        Task {
            do {
                let aircraft = try await aircraftProvider.nearbyAircraft(
                    in: AircraftSearchRegion(center: coordinate, radiusMiles: 10)
                )
                await MainActor.run {
                    aircraftProjectionDate = Date()
                    aircraftLayer = AircraftLayerState(
                        isVisible: showsAircraftLayer,
                        aircraft: showsAircraftLayer ? aircraft : [],
                        lastUpdated: Date(),
                        isStale: false
                    )
                    let freshCount = aircraft.filter { !$0.isStale }.count
                    let markerCount = showsAircraftLayer ? freshCount : 0
                    Self.logRouteIntelligence(
                        "Aircraft refresh raw=\(aircraft.count) freshHUD=\(freshCount) mapMarkers=\(markerCount)"
                    )
                    aircraftStatusText = aircraft.isEmpty ? "No fresh nearby aircraft" : "\(aircraft.count) nearby"
                    speakAircraftCueIfNeeded(now: Date())
                }
            } catch {
                Self.logRouteIntelligenceFailure("aircraft refresh", error: error)
                await MainActor.run {
                    pruneStaleAircraftIfNeeded(now: Date())
                    aircraftStatusText = aircraftLayer.aircraft.isEmpty ? "Aircraft data unavailable" : "Last update unavailable"
                }
            }
        }
    }

    private func handleAircraftRefreshTick() {
        guard showsAircraftLayer else {
            return
        }
        let now = Date()
        pruneStaleAircraftIfNeeded(now: now)

        guard let coordinate = passiveMapCoordinate else { return }
        refreshAircraft(near: coordinate, force: false)
    }

    private func handleAircraftProjectionTick() {
        guard showsAircraftLayer else {
            return
        }

        let now = Date()
        projectAircraftPositions(now: now)
        pruneStaleAircraftIfNeeded(now: now)
        speakAircraftCueIfNeeded(now: now)
    }

    private func projectAircraftPositions(now: Date) {
        guard showsAircraftLayer, !aircraftLayer.aircraft.isEmpty else { return }
        aircraftProjectionDate = now
        let projectedAircraft = AircraftPositionProjection.projectedAircraft(
            from: aircraftLayer.aircraft,
            reference: passiveMapCoordinate,
            now: now,
            staleTimeoutSeconds: aircraftStaleTimeoutSeconds
        )
        aircraftStatusText = projectedAircraft.isEmpty ? "No fresh nearby aircraft" : "\(projectedAircraft.count) nearby"
    }

    private func refreshEnforcementAlertsIfNeeded(near coordinate: GuidanceCoordinate) {
        guard areEnforcementAlertsEnabled else { return }
        let visibilityContext = enforcementAlertVisibilityContext(near: coordinate)
        guard shouldRefreshEnforcementAlerts(near: coordinate, context: visibilityContext, force: false) else {
            return
        }
        refreshEnforcementAlerts(near: coordinate, context: visibilityContext, force: false)
    }

    private func refreshEnforcementAlerts(near coordinate: GuidanceCoordinate, force: Bool) {
        guard areEnforcementAlertsEnabled else { return }
        let visibilityContext = enforcementAlertVisibilityContext(near: coordinate)
        guard shouldRefreshEnforcementAlerts(near: coordinate, context: visibilityContext, force: force) else {
            return
        }
        refreshEnforcementAlerts(near: coordinate, context: visibilityContext, force: force)
    }

    private func refreshEnforcementAlerts(
        near coordinate: GuidanceCoordinate,
        context visibilityContext: EnforcementAlertVisibilityContext,
        force: Bool
    ) {
        let now = Date()
        lastEnforcementAlertLookupAt = now
        lastEnforcementAlertLookupCoordinate = coordinate
        lastEnforcementAlertRouteContextID = enforcementAlertRouteContextID(for: visibilityContext)
        enforcementAlertStatusText = "Checking"
        let radiusMiles = visibilityContext.hasActiveRoute
            ? EnforcementAlertVisibilityPolicy.routeActiveDistanceCapMiles
            : EnforcementAlertVisibilityPolicy.noRouteDistanceCapMiles
        Self.logRouteIntelligence(
            "Enforcement refresh started center=\(Self.roundedCoordinateText(coordinate)) radiusMiles=\(radiusMiles)"
        )
        let redLightCameraAlertsEnabled = areRedLightCameraAlertsEnabled
        let enforcementReportAlertsEnabled = areEnforcementReportAlertsEnabled

        Task {
            do {
                let alerts = try await enforcementAlertService.alerts(near: coordinate, radiusMiles: radiusMiles)
                let filteredAlerts = EnforcementAlertVisibilityPolicy.filteredAlerts(
                    from: alerts,
                    redLightCameraAlertsEnabled: redLightCameraAlertsEnabled,
                    enforcementReportAlertsEnabled: enforcementReportAlertsEnabled
                )
                let visibleAlerts = EnforcementAlertVisibilityPolicy.visibleAlerts(
                    from: filteredAlerts,
                    context: visibilityContext
                )
                await MainActor.run {
                    enforcementAlerts = visibleAlerts
                    enforcementAlertsLastUpdatedAt = Date()
                    let markerCount = areEnforcementAlertsEnabled ? visibleAlerts.filter { !$0.isStale }.count : 0
                    Self.logRouteIntelligence(
                        "Enforcement refresh returned rawAlerts=\(alerts.count) filteredAlerts=\(filteredAlerts.count) visibleAlerts=\(visibleAlerts.count) mapMarkers=\(markerCount)"
                    )
                    enforcementAlertStatusText = EnforcementAlertVisibilityPolicy.statusText(
                        visibleAlertCount: visibleAlerts.count,
                        hasActiveRoute: visibilityContext.hasActiveRoute
                    )
                    trimCameraSpeechHistory(toVisibleAlerts: visibleAlerts)
                    speakCameraWarningIfNeeded()
                }
            } catch {
                Self.logRouteIntelligenceFailure("enforcement refresh", error: error)
                await MainActor.run {
                    enforcementAlerts = []
                    enforcementAlertStatusText = "Camera/enforcement source unavailable"
                }
            }
        }
    }

    private func handleEnforcementAlertRefreshTick() {
        guard areEnforcementAlertsEnabled,
              let coordinate = passiveMapCoordinate else {
            return
        }

        refreshEnforcementAlerts(near: coordinate, force: false)
    }

    private func shouldRefreshEnforcementAlerts(
        near coordinate: GuidanceCoordinate,
        context visibilityContext: EnforcementAlertVisibilityContext,
        force: Bool
    ) -> Bool {
        guard !force else { return true }

        let now = Date()
        let routeContextID = enforcementAlertRouteContextID(for: visibilityContext)
        if lastEnforcementAlertRouteContextID != routeContextID {
            return true
        }

        guard let lastLookupAt = lastEnforcementAlertLookupAt else { return true }
        let elapsed = now.timeIntervalSince(lastLookupAt)
        if elapsed >= enforcementAlertMaximumRefreshIntervalSeconds {
            return true
        }

        guard elapsed >= enforcementAlertRefreshIntervalSeconds else { return false }
        guard let lastCoordinate = lastEnforcementAlertLookupCoordinate else { return true }

        let movedMiles = coordinate.location.distance(from: lastCoordinate.location) / 1_609.344
        let movementThreshold = visibilityContext.hasActiveRoute
            ? routeActiveEnforcementRefreshMovementMiles
            : noRouteEnforcementRefreshMovementMiles
        return movedMiles >= movementThreshold
    }

    private func enforcementAlertRouteContextID(
        for context: EnforcementAlertVisibilityContext
    ) -> String {
        guard context.hasActiveRoute else { return "no-route" }
        return liveDriveHUDRoute.map { route in
            "\(route.id.uuidString):\(route.routeCoordinates.count):\(String(format: "%.1f", route.distanceMiles))"
        } ?? "route"
    }

    private func pruneStaleAircraftIfNeeded(now: Date, force: Bool = false) {
        guard showsAircraftLayer, let lastUpdated = aircraftLayer.lastUpdated else { return }
        guard force || now.timeIntervalSince(lastUpdated) > aircraftStaleTimeoutSeconds else { return }

        aircraftLayer = AircraftLayerState(
            isVisible: true,
            aircraft: [],
            lastUpdated: lastUpdated,
            isStale: true
        )
        spokenAircraftAlertHistory = [:]
        Self.logRouteIntelligence("Aircraft markers cleared as stale")
    }

    private func speakCameraWarningIfNeeded() {
        guard isCameraAlertAudioEnabled,
              !guidanceEngine.state.isMuted,
              let warning = activeCameraWarning else {
            return
        }

        var spokenThresholds = spokenCameraAlertThresholds[warning.alert.id, default: []]
        guard !spokenThresholds.contains(warning.threshold.rawValue) else { return }
        spokenThresholds.insert(warning.threshold.rawValue)
        spokenCameraAlertThresholds[warning.alert.id] = spokenThresholds
        guidanceEngine.speakSystemPrompt(cameraSpeechPrompt(for: warning))
    }

    private func trimCameraSpeechHistory(toVisibleAlerts visibleAlerts: [EnforcementAlert]) {
        let visibleIDs = Set(visibleAlerts.map(\.id))
        spokenCameraAlertThresholds = spokenCameraAlertThresholds.filter { visibleIDs.contains($0.key) }
    }

    private func cameraSpeechPrompt(for warning: ActiveCameraWarning) -> String {
        switch (warning.alert.type, warning.threshold) {
        case (.speedCamera, .fiveHundredFeet):
            return "Speed camera report ahead."
        case (.speedCamera, .oneHundredFiftyFeet):
            return "Speed camera report close."
        case (.speedCamera, .fiftyFeet):
            return "Speed camera report nearby."
        case (.redLightCamera, .fiveHundredFeet):
            return "Red-light camera report ahead."
        case (.redLightCamera, .oneHundredFiftyFeet):
            return "Red-light camera report close."
        case (.redLightCamera, .fiftyFeet):
            return "Red-light camera report nearby."
        case (_, .fiveHundredFeet):
            return "Camera report ahead."
        case (_, .oneHundredFiftyFeet):
            return "Camera report close."
        case (_, .fiftyFeet):
            return "Camera report nearby."
        }
    }

    private func speakAircraftCueIfNeeded(now: Date) {
        guard isAircraftAlertAudioEnabled,
              showsAircraftLayer,
              !guidanceEngine.state.isMuted,
              let aircraft = nearestMapAircraft,
              !aircraft.isStale,
              let band = aircraftSpeechBand(for: aircraft) else {
            return
        }

        let aircraftID = aircraft.id
        if let memory = spokenAircraftAlertHistory[aircraftID],
           memory.lastBand == band,
           now.timeIntervalSince(memory.lastSpokenAt) < 120 {
            return
        }

        if let memory = spokenAircraftAlertHistory[aircraftID],
           now.timeIntervalSince(memory.lastSpokenAt) < 60 {
            return
        }

        spokenAircraftAlertHistory[aircraftID] = AircraftSpeechMemory(lastSpokenAt: now, lastBand: band)
        guidanceEngine.speakSystemPrompt(aircraftSpeechPrompt(for: aircraft))
    }

    private func aircraftSpeechBand(for aircraft: Aircraft) -> Int? {
        guard aircraft.isLowNearbyAircraft,
              let distanceMiles = aircraft.distanceMiles,
              distanceMiles <= 3.0 else {
            return nil
        }

        return distanceMiles <= 1.0 ? 1 : 3
    }

    private func aircraftSpeechPrompt(for aircraft: Aircraft) -> String {
        AircraftSpeechCueFormatter.spokenCue(for: aircraft)
    }

    private static func logRouteIntelligence(_ message: String) {
        #if canImport(OSLog)
        routeIntelligenceLogger.debug("\(message, privacy: .public)")
        #endif
    }

    private static func logRouteIntelligenceFailure(_ context: String, error: Error) {
        #if canImport(OSLog)
        routeIntelligenceLogger.error(
            "Route intelligence \(context, privacy: .public) failed: \(diagnosticDescription(for: error), privacy: .public)"
        )
        #endif
    }

    private static func diagnosticDescription(for error: Error) -> String {
        let nsError = error as NSError
        var parts = [
            "description=\(error.localizedDescription)",
            "domain=\(nsError.domain)",
            "code=\(nsError.code)"
        ]

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlyingDomain=\(underlyingError.domain)")
            parts.append("underlyingCode=\(underlyingError.code)")
            parts.append("underlyingDescription=\(underlyingError.localizedDescription)")
        }

        return parts.joined(separator: " ")
    }

    private static func roundedCoordinateText(_ coordinate: GuidanceCoordinate) -> String {
        "\(String(format: "%.4f", coordinate.latitude)),\(String(format: "%.4f", coordinate.longitude))"
    }

    private func requestGuidanceRerouteIfNeeded(from coordinate: GuidanceCoordinate) {
        guard tracker.isTracking,
              guidanceEngine.state.isOffRoute,
              !isGuidanceRerouting,
              let route = liveDriveCapturedRoute else {
            return
        }

        let now = Date()
        if let lastGuidanceRerouteAt, now.timeIntervalSince(lastGuidanceRerouteAt) < 60 {
            return
        }
        lastGuidanceRerouteAt = now
        isGuidanceRerouting = true
        guidanceRerouteMessage = nil
        guidanceEngine.speakSystemPrompt("Rerouting.")

        let sourcePlace = ResolvedRoutePlace(
            title: "Current Location",
            subtitle: "Drive position",
            query: "Current Location",
            coordinate: RouteCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
            isCurrentLocation: true
        )
        let destinationPlace = ResolvedRoutePlace(
            title: route.destinationName,
            query: route.destinationName,
            coordinate: route.destinationCoordinate
        )
        let originalBaselineETA = liveDriveRouteContext?.baselineRouteETAMinutes ?? route.expectedTravelMinutes
        let originalBaselineDistance = liveDriveRouteContext?.baselineRouteDistanceMiles ?? route.distanceMiles

        Task {
            do {
                let reroutedRoutes = try await RouteLookupService.fetchRouteOptions(
                    source: .currentLocation(sourcePlace),
                    destination: .resolvedPlace(destinationPlace)
                )

                await MainActor.run {
                    guard let selectedRoute = reroutedRoutes.first else {
                        isGuidanceRerouting = false
                        guidanceRerouteMessage = "Reroute unavailable"
                        return
                    }

                    liveDriveRouteContext = LiveDriveRouteContext(
                        routes: reroutedRoutes,
                        selectedRouteID: selectedRoute.id,
                        routeLabel: "\(selectedRoute.routeName.isEmpty ? "Rerouted route" : selectedRoute.routeName) • \(Self.milesString(selectedRoute.distanceMiles)) mi • \(Self.durationString(selectedRoute.expectedTravelMinutes))",
                        baselineRouteETAMinutes: originalBaselineETA,
                        baselineRouteDistanceMiles: originalBaselineDistance
                    )
                    guidanceEngine.loadRoute(
                        steps: selectedRoute.maneuverSteps,
                        routeDistanceMeters: selectedRoute.distanceMiles * 1_609.344,
                        destination: GuidanceCoordinate(
                            latitude: selectedRoute.destinationCoordinate.latitude,
                            longitude: selectedRoute.destinationCoordinate.longitude
                        )
                    )
                    applyStoredVoiceSettings()
                    isGuidanceRerouting = false
                    guidanceRerouteMessage = "Reroute ready"
                    guidanceEngine.speakSystemPrompt("Reroute ready.")
                }
            } catch {
                await MainActor.run {
                    isGuidanceRerouting = false
                    guidanceRerouteMessage = "Reroute unavailable"
                }
            }
        }
    }

    private func timeComparisonRows(
        baselineTitle: String,
        baselineMinutes: Double,
        comparisonTitle: String,
        comparisonMinutes: Double,
        comparisonTint: Color,
        comparisonLabel: String,
        scaleMinutes: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Time comparison")
                .font(inputLabelFont)
                .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)

            ComparisonBarRow(
                title: baselineTitle,
                minutes: baselineMinutes,
                tint: usesDarkLiveDriveTheme ? Color.white.opacity(0.82) : Palette.ink,
                scaleMinutes: scaleMinutes,
                minutesLabel: Self.durationString(baselineMinutes),
                compact: isMobileLayout,
                titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa,
                valueColor: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink,
                trackColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.pill
            )
            ComparisonBarRow(
                title: comparisonTitle,
                minutes: comparisonMinutes,
                tint: comparisonTint,
                scaleMinutes: scaleMinutes,
                minutesLabel: comparisonLabel,
                compact: isMobileLayout,
                titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa,
                valueColor: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink,
                trackColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.pill
            )
        }
    }

    private static func number(from text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func normalizedAddress(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func durationString(_ minutes: Double) -> String {
        let roundedSeconds = Int((minutes * 60).rounded())
        let hours = roundedSeconds / 3600
        let remainingMinutes = (roundedSeconds % 3600) / 60
        let seconds = roundedSeconds % 60

        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }

        if remainingMinutes > 0 {
            return seconds == 0 ? "\(remainingMinutes)m" : "\(remainingMinutes)m \(seconds)s"
        }

        return "\(seconds)s"
    }

    private static func netString(_ minutes: Double) -> String {
        if abs(minutes) < 0.01 {
            return "Even"
        }

        return minutes > 0 ? "\(durationString(minutes)) saved" : "\(durationString(abs(minutes))) lost"
    }

    private static func speedLimitMetricString(_ minutes: Double, measuredMinutes: Double) -> String {
        measuredMinutes > 0 ? durationString(minutes) : "—"
    }

    private static func milesString(_ miles: Double) -> String {
        if abs(miles.rounded() - miles) < 0.01 {
            return String(Int(miles.rounded()))
        }

        return String(format: "%.1f", miles)
    }

    private static func guidanceDistanceString(_ meters: Double) -> String {
        let feet = meters * 3.28084

        if feet < 1_000 {
            return "\(max(Int(feet.rounded()), 0)) ft to next maneuver"
        }

        return "\(String(format: "%.1f", feet / 5_280)) mi to next maneuver"
    }

    private static func speedLimitDetailText(from result: OSMSpeedLimitResult) -> String {
        var parts = ["OpenStreetMap estimate"]

        if let roadName = result.roadName, !roadName.isEmpty {
            parts.append(roadName)
        }

        parts.append("Confidence \(Int((result.confidence * 100).rounded()))%")

        if let wayId = result.wayId {
            parts.append("Way \(wayId)")
        }

        return parts.joined(separator: " • ")
    }

    private static func routeWeatherDisplayEntry(
        from entry: RouteWeatherTimelineEntry,
        timeZone: TimeZone
    ) -> RouteWeatherDisplayEntry {
        let forecast = entry.forecast
        let temperatureText = forecast.temperatureCelsius.map { "\(Int(($0 * 9 / 5 + 32).rounded()))°" }
        let detailParts = [
            temperatureText.map { "\($0)F" },
            forecast.precipitationChance.map { "\(Int(($0 * 100).rounded()))% precip" },
            forecast.windDescription.map { "Wind \($0)" }
        ].compactMap { $0 }
        let advisory = forecast.advisories.first

        return RouteWeatherDisplayEntry(
            coordinate: entry.checkpoint.coordinate,
            isForecastAvailable: true,
            title: Self.checkpointTitle(for: entry.checkpoint),
            arrivalText: Self.timeString(entry.checkpoint.expectedArrivalDate, timeZone: timeZone),
            forecastText: forecast.summary,
            detailText: detailParts.isEmpty ? "Forecasts are matched to expected arrival times." : detailParts.joined(separator: " • "),
            temperatureText: temperatureText,
            aqiText: nil,
            alertText: forecast.alertStatus,
            advisorySummary: advisory?.summary,
            advisoryAffectedArea: advisory?.affectedArea,
            advisoryIssuedText: advisory?.issuedAt.map { Self.timeString($0, timeZone: timeZone) },
            advisorySource: advisory?.source,
            advisorySourceURL: advisory?.sourceURL
        )
    }

    private static func routeWeatherUnavailableEntry(
        from checkpoint: RouteWeatherCheckpoint,
        timeZone: TimeZone,
        detailText: String
    ) -> RouteWeatherDisplayEntry {
        RouteWeatherDisplayEntry(
            coordinate: checkpoint.coordinate,
            isForecastAvailable: false,
            title: Self.checkpointTitle(for: checkpoint),
            arrivalText: Self.timeString(checkpoint.expectedArrivalDate, timeZone: timeZone),
            forecastText: "Forecast unavailable",
            detailText: detailText,
            temperatureText: nil,
            aqiText: nil,
            alertText: nil,
            advisorySummary: nil,
            advisoryAffectedArea: nil,
            advisoryIssuedText: nil,
            advisorySource: nil,
            advisorySourceURL: nil
        )
    }

    private static func currentWeatherDisplayEntry(
        from entry: RouteWeatherDisplayEntry
    ) -> RouteWeatherDisplayEntry {
        var currentEntry = entry
        currentEntry.title = "Current Location"
        currentEntry.arrivalText = "Now"
        if currentEntry.isForecastAvailable,
           currentEntry.detailText == "Forecasts are matched to expected arrival times." {
            currentEntry.detailText = "Current-location WeatherKit forecast."
        }
        return currentEntry
    }

    private static func routeWeatherUnavailableDetail(from error: Error) -> String {
        if let weatherError = error as? WeatherRouteProviderError {
            switch weatherError {
            case .insufficientRouteGeometry:
                return "Route weather needs a route with enough geometry to sample checkpoints."
            case .weatherKitNotConfigured:
                return "WeatherKit is not configured for this build. Confirm the WeatherKit capability and signed entitlement before installing on a real device."
            case .forecastUnavailable:
                return "WeatherKit did not return forecast data for this route."
            case .weatherKitRequestFailed(let reason):
                return Self.cleanWeatherUnavailableMessage(reason)
            }
        }

        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            return "WeatherKit did not return forecast data for this route."
        }

        return Self.cleanWeatherUnavailableMessage(description)
    }

    private static func cleanWeatherUnavailableMessage(_ text: String) -> String {
        let normalized = text.lowercased()
        if normalized.contains("weatherdaemon") ||
            normalized.contains("wdsjwt") ||
            normalized.contains("authenticator") ||
            normalized.contains("jwt") ||
            normalized.contains("provisioning") ||
            normalized.contains("entitlement") ||
            normalized.contains("not authorized") ||
            normalized.contains("authorization") {
            return "WeatherKit is not available for this signed build. Check the WeatherKit capability and provisioning profile."
        }

        if normalized.contains("weatherkit") {
            return text
        }

        return "WeatherKit request failed. Check WeatherKit capability, provisioning profile, and network availability."
    }

    private static func labeledWeatherEntries(
        _ entries: [RouteWeatherDisplayEntry],
        sourceName: String,
        destinationName: String
    ) -> [RouteWeatherDisplayEntry] {
        entries.enumerated().map { index, entry in
            var labeledEntry = entry
            if index == 0 {
                labeledEntry.title = "Near \(sourceName)"
            } else if index == entries.count - 1 {
                labeledEntry.title = "Near \(destinationName)"
            }
            return labeledEntry
        }
    }

    private static func checkpointTitle(for checkpoint: RouteWeatherCheckpoint) -> String {
        let miles = checkpoint.distanceFromStartMeters / 1_609.344
        return "Checkpoint \(Self.milesString(miles)) mi"
    }

    private static func timeString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private static func speedString(_ speed: Double) -> String {
        if abs(speed.rounded() - speed) < 0.01 {
            return String(Int(speed.rounded()))
        }

        return String(format: "%.1f", speed)
    }

    private static func topSpeedString(_ speed: Double?) -> String {
        guard let speed, speed > 0 else { return "—" }
        return "\(Self.speedString(speed)) mph"
    }
}

#if os(iOS)
private struct ShareCardMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let tint: Color
}

private struct FinishedTripShareCardView: View {
    let brandLogo: Image?
    let routeTitle: String
    let routeMeta: String
    let completedAtText: String
    let overallResultTitle: String
    let overallResultValue: String
    let overallResultTint: Color
    let overallResultDetail: String
    let metrics: [ShareCardMetric]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.11),
                    Color(red: 0.10, green: 0.12, blue: 0.16),
                    Color(red: 0.07, green: 0.27, blue: 0.17)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 10) {
                    Group {
                        if let brandLogo {
                            brandLogo
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                        } else {
                            Image(systemName: "gauge.with.needle")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(width: 82, height: 50, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("TimeThrottle")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)

                        Text("How much time did speed really buy you?")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .lineLimit(2)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(routeTitle)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Text(routeMeta)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(2)

                    Text(completedAtText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(overallResultTitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))

                    Text(overallResultValue)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(overallResultTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(overallResultDetail)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.76))
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(metrics) { metric in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(metric.title)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.66))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(metric.value)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(metric.tint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                        .padding(14)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        }
                    }
                }

                Spacer(minLength: 0)

                Text("How much time did speed really buy you?")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

private struct VoiceSelectionSheet: View {
    let voiceState: LiveDriveHUDVoiceState
    let onSelectVoice: (String?) -> Void
    let onTestVoice: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.09, blue: 0.13),
                        Color(red: 0.03, green: 0.04, blue: 0.06)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 8) {
                        Button {
                            onSelectVoice(nil)
                            dismiss()
                        } label: {
                            voiceRow(
                                title: "System default",
                                subtitle: "Best available English voice",
                                isSelected: voiceState.selectedVoiceIdentifier == nil
                            )
                        }
                        .buttonStyle(.plain)

                        ForEach(voiceState.availableVoices) { voice in
                            Button {
                                onSelectVoice(voice.identifier)
                                dismiss()
                            } label: {
                                voiceRow(
                                    title: voice.name,
                                    subtitle: voice.language,
                                    isSelected: voice.identifier == voiceState.selectedVoiceIdentifier
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Test") {
                        onTestVoice()
                    }
                    .disabled(voiceState.isMuted)
                }
            }
        }
    }

    private func voiceRow(title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.success)
            }
        }
        .padding(14)
        .background(Color.white.opacity(isSelected ? 0.09 : 0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Palette.success.opacity(0.55) : Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
