import Foundation
import Combine
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

private enum LiveDriveScreenState: Equatable {
    case setup
    case driving
    case tripComplete
}

private enum LiveDriveAppTab: String, CaseIterable, Identifiable {
    case drive
    case map
    case trips
    case scanner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drive: return "Drive"
        case .map: return "Map"
        case .trips: return "Trips"
        case .scanner: return "Scanner"
        }
    }

    var systemImage: String {
        switch self {
        case .drive: return "location.fill"
        case .map: return "map.fill"
        case .trips: return "clock.arrow.circlepath"
        case .scanner: return "radio.fill"
        }
    }
}

private enum LiveDriveMetricEmphasis {
    case standard
    case strong
    case hero
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
    var title: String
    var arrivalText: String
    var forecastText: String
    var detailText: String
    var temperatureText: String?
    var aqiText: String?
    var alertText: String?
}

private struct MapWeatherChipContent: Equatable {
    var systemImage: String
    var temperatureText: String
    var aqiText: String?
}

public struct RouteComparisonView: View {
    private let brandLogo: Image?
    private let resultBrandLogo: Image?
    private let mapPreview: ([RouteEstimate], UUID?) -> AnyView
    private let weatherProvider: WeatherRouteProvider
    private let speedLimitProvider = OSMSpeedLimitService()
    private let aircraftProvider = OpenSkyAircraftProvider()
    private let enforcementAlertService = EnforcementAlertService()
    private let aircraftRefreshPublisher = Timer.publish(every: 25, on: .main, in: .common).autoconnect()
    private let aircraftRefreshIntervalSeconds: TimeInterval = 25
    private let aircraftStaleTimeoutSeconds: TimeInterval = 90
    private let enforcementAlertRefreshIntervalSeconds: TimeInterval = 60

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
    @AppStorage("timethrottle.preferredNavigationProvider") private var navigationProviderPreferenceRawValue = NavigationProvider.askEveryTime.rawValue
    @State private var liveDriveRouteContext: LiveDriveRouteContext?
    @State private var liveDriveFinishedTrip: CompletedTripRecord?
    @State private var liveDriveNavigationProviderPending: NavigationProvider?
    @State private var liveDriveNavigationHandoffMessage: String?
    @State private var routeWeatherRouteID: UUID?
    @State private var routeWeatherEntries: [RouteWeatherDisplayEntry] = []
    @State private var routeWeatherMessage = "Forecast unavailable"
    @State private var isRouteWeatherLoading = false
    @State private var isRouteWeatherVisible = true
    @State private var speedLimitDisplayText = "Unavailable"
    @State private var speedLimitDetailText = "OpenStreetMap estimate"
    @State private var lastSpeedLimitLookupAt: Date?
    @AppStorage("timethrottle.voice.selectedVoiceIdentifier") private var storedGuidanceVoiceIdentifier = ""
    @AppStorage("timethrottle.voice.speechRate") private var storedGuidanceSpeechRate = Double(VoiceGuidanceSettings.defaultSpeechRate)
    @AppStorage("timethrottle.voice.isMuted") private var isVoiceGuidanceMuted = false
    @AppStorage("timethrottle.mapMode") private var mapModeRawValue = LiveDriveMapMode.standard.rawValue
    @AppStorage("timethrottle.enforcementAlertsEnabled") private var areEnforcementAlertsEnabled = false
    @State private var isGuidanceRerouting = false
    @State private var guidanceRerouteMessage: String?
    @State private var lastGuidanceRerouteAt: Date?
    @AppStorage("timethrottle.aircraftLayerEnabled") private var showsAircraftLayer = true
    @State private var aircraftLayer = AircraftLayerState(isVisible: true)
    @State private var aircraftStatusText = "Checking"
    @State private var lastAircraftPollAt: Date?
    @State private var enforcementAlerts: [EnforcementAlert] = []
    @State private var enforcementAlertStatusText = "Off"
    @State private var lastEnforcementAlertLookupAt: Date?
    @State private var enforcementAlertsLastUpdatedAt: Date?
    @State private var isMapOptionsPresented = false
    @State private var isVoiceSelectionPresented = false
    @State private var selectedAppTab: LiveDriveAppTab = .drive
    @State private var isNavigationProviderChoicePresented = false
    @State private var isTripHistoryPresented = false
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
            return liveDriveScreenState == .setup ? 118 : 160
        }

        return 260
    }

    private var heroLogoHeight: CGFloat {
        isMobileLayout ? 80 : 84
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
        liveDriveRouteContext?.routeLabel ?? liveDriveCurrentRouteLabel
    }

    private var liveDriveHUDRoute: RouteEstimate? {
        liveDriveCapturedRoute ?? liveDriveSetupRoute
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
        guard isRouteWeatherVisible else { return "Hidden" }
        if isRouteWeatherLoading { return "Loading route forecast..." }
        if let alert = routeWeatherEntries.compactMap(\.alertText).first { return alert }
        return routeWeatherEntries.isEmpty ? "Forecast unavailable" : "\(routeWeatherEntries.count) planned checkpoints"
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

        return "\(enforcementAlerts.count) alerts nearby"
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
                aircraft: showsAircraftLayer ? aircraftLayer.aircraft : [],
                enforcementAlerts: areEnforcementAlertsEnabled ? enforcementAlerts : [],
                mapMode: selectedMapMode
            )
        )
        #else
        return AnyView(mapPreview(routes, selectedRoute.id))
        #endif
    }

    private var fullRouteMapRoute: RouteEstimate? {
        liveDriveHUDRoute
    }

    private var fullRouteMapRoutes: [RouteEstimate] {
        if let liveDriveRouteContext {
            return liveDriveRouteContext.routes
        }

        return liveDriveSetupRouteOptions
    }

    private var preferredNavigationProvider: NavigationProvider {
        NavigationProvider(rawValue: navigationProviderPreferenceRawValue) ?? .askEveryTime
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
        if let liveDriveRouteContext, liveDriveRouteContext.baselineRouteETAMinutes > 0 {
            return liveDriveRouteContext.baselineRouteETAMinutes
        }

        if tracker.configuration.baselineRouteETAMinutes > 0 {
            return tracker.configuration.baselineRouteETAMinutes
        }

        return liveDriveSetupRoute?.expectedTravelMinutes ?? 0
    }

    private var liveDriveBaselineDistanceMiles: Double {
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
            return "Turn on Location Access in Settings to use Live Drive."
        case .restricted:
            return "This device restricts Location Access, so Live Drive cannot measure speed or distance."
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
            return "Allow Always Location to keep Live Drive active while another navigation app is open."
        case .notDetermined:
            guard preferredNavigationProvider != .askEveryTime else { return nil }
            return "External navigation needs Always Location so Live Drive can keep tracking in the background."
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
        preferredNavigationProvider == .askEveryTime
            ? "You’ll choose a navigation app when the trip starts."
            : "\(preferredNavigationProvider.rawValue) handoff ready."
    }

    private var liveDriveOverallResultTitle: String {
        "Overall vs Apple ETA"
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
            return "Capture the route baseline and start Live Drive."
        case .driving:
            return tracker.isPaused
                ? "Resume the same trip or end it without losing the finished result."
                : "Pause the trip or end it when you are finished driving."
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
        PlatformLayout {
            appTabRoot
        }
        .task {
            applyStoredVoiceSettings()

            if routeOriginInputMode == .currentLocation {
                currentLocationResolver.requestCurrentLocationIfNeeded()
            }

            guard shouldRunCaptureBootstrap, !didRunCaptureBootstrap else { return }
            didRunCaptureBootstrap = true
            calculateAppleMapsRoute()
        }
        .onChange(of: routeOriginInputMode) { _, newMode in
            focusedRouteAddressField = nil
            autocompleteController.clear()
            resetCalculatedRouteState()

            if newMode == .currentLocation {
                currentLocationResolver.requestCurrentLocationIfNeeded()
            }
        }
        .onChange(of: fromAddressText) { _, newValue in
            handleFromAddressTextChanged(newValue)
        }
        .onChange(of: toAddressText) { _, newValue in
            handleToAddressTextChanged(newValue)
        }
        .onChange(of: focusedRouteAddressField) { _, newField in
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
        .onChange(of: tracker.isTracking) { _, isTracking in
            if isTracking {
                processLiveDriveNavigationHandoffIfNeeded()
            }
        }
        .onChange(of: tracker.distanceTraveled) { _, newDistance in
            guidanceEngine.update(progressDistanceMeters: newDistance * 1_609.344)

            if let currentCoordinate = tracker.currentCoordinate {
                guidanceEngine.update(currentLocation: currentCoordinate)
            }
        }
        .onChange(of: tracker.currentCoordinate) { _, newCoordinate in
            guard let newCoordinate else { return }
            guidanceEngine.update(currentLocation: newCoordinate)
            refreshSpeedLimitIfNeeded(near: newCoordinate)
            refreshAircraftIfNeeded(near: newCoordinate)
            refreshEnforcementAlertsIfNeeded(near: newCoordinate)
            requestGuidanceRerouteIfNeeded(from: newCoordinate)
        }
        .onReceive(aircraftRefreshPublisher) { _ in
            handleAircraftRefreshTick()
            handleEnforcementAlertRefreshTick()
        }
        .onChange(of: areEnforcementAlertsEnabled) { _, isEnabled in
            if isEnabled, let coordinate = tracker.currentCoordinate {
                refreshEnforcementAlerts(near: coordinate, force: true)
            } else if !isEnabled {
                enforcementAlerts = []
                enforcementAlertStatusText = "Off"
                enforcementAlertsLastUpdatedAt = nil
            }
        }
        .onChange(of: liveDriveScreenState) { _, newState in
            switch newState {
            case .driving:
                selectedAppTab = .map
            case .setup, .tripComplete:
                if selectedAppTab == .map, newState == .tripComplete {
                    selectedAppTab = .drive
                }
            }
        }
        .onChange(of: tracker.permissionState) { _, newState in
            if newState == .denied || newState == .restricted {
                liveDriveNavigationProviderPending = nil
                isNavigationProviderChoicePresented = false
            } else if newState == .authorizedAlways, tracker.isTracking {
                processLiveDriveNavigationHandoffIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            tracker.refreshAuthorizationState()
            currentLocationResolver.refreshAuthorizationState()

            if routeOriginInputMode == .currentLocation {
                currentLocationResolver.requestCurrentLocationIfNeeded()
            }

            if tracker.isTracking {
                processLiveDriveNavigationHandoffIfNeeded()
            }
        }
        #if os(iOS)
        .sheet(isPresented: $isShareSheetPresented) {
            ShareSheet(activityItems: shareSheetItems)
        }
        .sheet(isPresented: $isMapOptionsPresented) {
            mapOptionsSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
                selectedAppTab = .drive
            } else if liveDriveScreenState == .driving {
                selectedAppTab = .map
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
        #endif
    }

    private var appTabRoot: some View {
        TabView(selection: $selectedAppTab) {
            mobileScreen
                .tabItem {
                    Label(LiveDriveAppTab.drive.title, systemImage: LiveDriveAppTab.drive.systemImage)
                }
                .tag(LiveDriveAppTab.drive)

            fullRouteMapTab
                .tabItem {
                    Label(LiveDriveAppTab.map.title, systemImage: LiveDriveAppTab.map.systemImage)
                }
                .tag(LiveDriveAppTab.map)

            TripHistoryScreen(
                store: tripHistoryStore,
                brandLogo: brandLogo,
                resultBrandLogo: resultBrandLogo,
                showsCloseButton: false
            )
            .tabItem {
                Label(LiveDriveAppTab.trips.title, systemImage: LiveDriveAppTab.trips.systemImage)
            }
            .tag(LiveDriveAppTab.trips)

            ScannerTabView(viewModel: scannerViewModel)
                .tabItem {
                    Label(LiveDriveAppTab.scanner.title, systemImage: LiveDriveAppTab.scanner.systemImage)
                }
                .tag(LiveDriveAppTab.scanner)
        }
        .tint(Palette.success)
    }

    private var fullRouteMapTab: some View {
        ZStack {
            if let route = fullRouteMapRoute {
                fullRouteMapContent(route: route)
            } else {
                tabEmptyState(
                    title: "Route Map",
                    message: "Start a Live Drive to see your route map.",
                    systemImage: "map.fill"
                )
            }
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

                Spacer(minLength: 0)

                fullRouteMapBottomOverlay(route: route)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
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
            aircraft: showsAircraftLayer ? aircraftLayer.aircraft : [],
            enforcementAlerts: areEnforcementAlertsEnabled ? enforcementAlerts : [],
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
        guard isRouteWeatherVisible, !isRouteWeatherLoading else { return nil }
        guard let entry = routeWeatherEntries.first(where: { $0.temperatureText?.isEmpty == false }) else { return nil }
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
                    Label("Options", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(setupPrimaryText)
                        .labelStyle(.iconOnly)
                        .frame(width: 38, height: 38)
                        .background(setupSurfaceMuted, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(setupPanelBorder, lineWidth: 1)
                        }
                        .accessibilityLabel("Map options")
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
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Map Options")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(setupPrimaryText)

                            Text("Route intelligence details stay here so the map stays clean.")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(setupSecondaryText)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 12)
                    }

                    mapOptionsSection(title: "Weather", systemImage: "cloud.sun.fill") {
                        Text("Route Forecast")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(setupPrimaryText)

                        Text(isRouteWeatherLoading ? "Loading route forecast..." : "Forecasts are matched to expected arrival times.")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(setupSecondaryText)

                        if routeWeatherEntries.isEmpty {
                            Text(routeWeatherMessage.isEmpty ? "Forecast unavailable" : routeWeatherMessage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(setupSecondaryText)
                                .padding(.top, 2)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(routeWeatherEntries.prefix(4)) { entry in
                                    mapOptionsDetailRow(
                                        title: entry.title,
                                        value: entry.forecastText,
                                        detail: "\(entry.arrivalText) • \(entry.detailText)"
                                    )
                                }
                            }
                        }
                    }

                    mapOptionsSection(title: "Aircraft", systemImage: "airplane") {
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

                    mapOptionsSection(title: "Enforcement Alerts", systemImage: "camera.viewfinder") {
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
                                .tint(Palette.success)
                        }

                        Text("Coverage varies by region. Reports are not guaranteed and are not a legal enforcement guarantee.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(setupTertiaryText)

                        if !enforcementAlerts.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(enforcementAlerts.prefix(5)) { alert in
                                    mapOptionsDetailRow(
                                        title: alert.title,
                                        value: alert.distanceMiles.map { "\(String(format: "%.1f", $0)) mi away" } ?? "Reported nearby",
                                        detail: enforcementAlertDetailText(for: alert)
                                    )
                                }
                            }
                        }
                    }

                    mapOptionsSection(title: "Voice Guidance", systemImage: liveDriveHUDVoiceState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
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

                    mapOptionsSection(title: "Speed Limit", systemImage: "speedometer") {
                        mapOptionsDetailRow(
                            title: "Speed Limit",
                            value: speedLimitDisplayText,
                            detail: speedLimitDetailText
                        )
                    }

                    mapOptionsSection(title: "Map Mode", systemImage: "map") {
                        Picker("Map Mode", selection: selectedMapModeBinding) {
                            ForEach(LiveDriveMapMode.allCases) { mode in
                                Text(mode.rawValue)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Standard is the default driving map. Satellite changes the map imagery only.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(setupTertiaryText)
                    }

                    mapOptionsSection(title: "Pace", systemImage: "timer") {
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
    }

    private func mapOptionsSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.bold))
                .foregroundStyle(setupPrimaryText)

            content()
        }
        .padding(14)
        .background(setupSurface.opacity(0.98), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(setupPanelBorder, lineWidth: 1)
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

            HStack(spacing: 12) {
                tripHistoryShortcutButton
                platformBadge
            }
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
        VStack(spacing: liveDriveScreenState == .setup ? 6 : 12) {
            logoLockup
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 2) {
                Text("Live Drive")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
            }
            .frame(maxWidth: .infinity)
            .opacity(liveDriveScreenState == .setup ? 1 : 0)
            .frame(height: liveDriveScreenState == .setup ? nil : 0)

            if liveDriveScreenState != .setup {
                liveDriveHeaderStatus
            }
        }
        .padding(.horizontal, Layout.screenPadding)
        .padding(.top, liveDriveScreenState == .setup ? 28 : 38)
        .padding(.bottom, liveDriveScreenState == .setup ? 10 : 18)
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
        VStack(alignment: .leading, spacing: isPolishedLiveDriveSetup ? 8 : 12) {
            Text("From")
                .font(inputLabelFont)
                .foregroundStyle(isPolishedLiveDriveSetup ? setupSecondaryText : Palette.cocoa)

            currentLocationOriginField

            Text("To")
                .font(inputLabelFont)
                .foregroundStyle(isPolishedLiveDriveSetup ? setupSecondaryText : Palette.cocoa)

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
        Group {
            if isPolishedLiveDriveSetup {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(setupSelectionFill.opacity(0.95))
                            .frame(width: 34, height: 34)

                        Image(systemName: "location.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Palette.success)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentLocationFieldLabel)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(setupPrimaryText)

                        Text(currentLocationDetailText)
                            .font(panelDescriptionFont)
                            .foregroundStyle(currentLocationResolver.errorMessage == nil ? setupSecondaryText : Palette.danger)
                    }

                    Spacer(minLength: 12)

                    if currentLocationResolver.isResolving {
                        ProgressView()
                            .tint(Palette.success)
                    } else if currentLocationResolver.authorizationStatus == .denied {
                        Button("Settings") {
                            openLiveDriveSettings()
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.success)
                    } else {
                        Button("Refresh") {
                            currentLocationResolver.requestCurrentLocation()
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.success)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(setupFieldFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(setupFieldBorder, lineWidth: 1)
                }
                .shadow(color: setupShadowColor.opacity(0.45), radius: 16, y: 7)
            } else {
                InsetPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "location.fill")
                                .font(.headline)
                                .foregroundStyle(Palette.success)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentLocationFieldLabel)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(Palette.ink)

                                Text(currentLocationDetailText)
                                    .font(panelDescriptionFont)
                                    .foregroundStyle(currentLocationResolver.errorMessage == nil ? Palette.cocoa : Palette.danger)
                            }

                            Spacer(minLength: 12)

                            if currentLocationResolver.isResolving {
                                ProgressView()
                                    .tint(Palette.success)
                            } else if currentLocationResolver.authorizationStatus == .denied {
                                Button("Settings") {
                                    openLiveDriveSettings()
                                }
                                .buttonStyle(.borderless)
                                .font(.subheadline.weight(.semibold))
                            } else {
                                Button("Refresh") {
                                    currentLocationResolver.requestCurrentLocation()
                                }
                                .buttonStyle(.borderless)
                                .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }
            }
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
            background: isPolishedLiveDriveSetup ? setupSurface : Palette.panel,
            border: isPolishedLiveDriveSetup ? setupPanelBorder : Palette.surfaceBorder,
            shadowColor: isPolishedLiveDriveSetup ? setupShadowColor : .black.opacity(0.05),
            shadowRadius: isPolishedLiveDriveSetup ? 28 : 18,
            shadowYOffset: isPolishedLiveDriveSetup ? 12 : 8
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    mobileSectionHeader(
                        title: "Live drive setup",
                        subtitle: "Capture the route baseline and start tracking with route intelligence."
                    )

                    Spacer(minLength: 12)

                    tripHistoryShortcutButton
                }

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
                                title: "Live Drive needs location access",
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
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                liveDriveRouteContextSection
                liveDriveComparisonSection
                liveDriveSafetySection
            }
        } else if liveDriveScreenState == .tripComplete {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                liveDriveComparisonSection
                liveDriveRouteContextSection
                liveDriveTripSummarySection
                liveDriveSafetySection
            }
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

                if liveDriveProjectedTravelMinutes <= 0 {
                    mobileHelperCard("Drive a bit farther to estimate your live trip pace against the captured Apple Maps ETA.")
                } else {
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
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .center, spacing: 14) {
                                finishedTripBrandLogo
                                    .frame(width: 82, height: 54, alignment: .center)

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
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(liveDriveOverallResultTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)

                                Text(Self.netString(completedTrip.netTimeGain))
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .foregroundStyle(completedTrip.netTimeGain >= 0 ? Palette.success : Palette.danger)

                                Text(liveDriveVerdict(for: completedTrip.netTimeGain))
                                    .font(panelDescriptionFont)
                                    .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)
                            }

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)
                                ],
                                spacing: 12
                            ) {
                                SummaryCard(title: "Time Above Speed Limit", value: Self.speedLimitMetricString(completedTrip.timeSavedBySpeeding, measuredMinutes: completedTrip.speedLimitMeasuredMinutes), tint: Palette.success, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
                                SummaryCard(title: "Time Below Speed Limit", value: Self.speedLimitMetricString(completedTrip.timeLostBelowTargetPace, measuredMinutes: completedTrip.speedLimitMeasuredMinutes), tint: Palette.danger, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
                                SummaryCard(title: "Distance driven", value: "\(Self.milesString(completedTrip.distanceDrivenMiles)) mi", tint: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
                                SummaryCard(title: "Elapsed drive time", value: Self.durationString(completedTrip.elapsedDriveMinutes), tint: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
                                SummaryCard(title: "Average trip speed", value: "\(Self.speedString(completedTrip.averageTripSpeed)) mph", tint: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
                                SummaryCard(title: "Top speed", value: Self.topSpeedString(completedTrip.topSpeedMPH), tint: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
                                SummaryCard(title: "Speed-limit coverage", value: Self.speedLimitCoverageString(for: completedTrip), tint: usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink, compact: true, titleColor: usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa, backgroundColor: usesDarkLiveDriveTheme ? setupSurfaceMuted : Palette.panel, borderColor: usesDarkLiveDriveTheme ? setupPanelBorder : nil, shadowColor: usesDarkLiveDriveTheme ? setupShadowColor.opacity(0.65) : .black.opacity(0.05))
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
                            selectedAppTab = .map
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
                            selectedAppTab = .trips
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
            Text(subtitle)
                .font(panelDescriptionFont)
                .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)
        }
    }

    private var liveDriveNavigationProviderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Navigation App")
                .font(inputLabelFont)
                .foregroundStyle(isPolishedLiveDriveSetup ? setupSecondaryText : Palette.cocoa)

            Menu {
                ForEach(NavigationProvider.allCases) { provider in
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

    private var tripHistoryShortcutButton: some View {
        Button {
            selectedAppTab = .trips
        } label: {
            Label("Trips", systemImage: "clock.arrow.circlepath")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isPolishedLiveDriveSetup ? setupPrimaryText : Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background((isPolishedLiveDriveSetup ? setupSurfaceMuted : Palette.successBackground), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(isPolishedLiveDriveSetup ? setupPanelBorder : .clear, lineWidth: isPolishedLiveDriveSetup ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
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
                VStack(alignment: .leading, spacing: 8) {
                    routeOptionsPanel(routes: routes, selectedRoute: selectedRoute)
                    routeMapPanel(routes: routes, selectedRoute: selectedRoute)
                    routeWeatherPanel(for: selectedRoute)
                }
            } else {
                HStack(alignment: .top, spacing: Layout.innerSpacing) {
                    routeOptionsPanel(routes: routes, selectedRoute: selectedRoute)
                        .frame(width: Layout.sidePanelWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 10) {
                        routeMapPanel(routes: routes, selectedRoute: selectedRoute)
                        routeWeatherPanel(for: selectedRoute)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(isMobileLayout ? 10 : 14)
        .background((usesDarkLiveDriveTheme ? setupSurfaceRaised : Palette.panel), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(usesDarkLiveDriveTheme ? setupPanelBorder : Palette.surfaceBorder, lineWidth: 1)
        }
        .shadow(color: usesDarkLiveDriveTheme ? setupShadowColor : .black.opacity(0.08), radius: 25, y: 10)
    }

    private func routeOptionsPanel(routes: [RouteEstimate], selectedRoute: RouteEstimate) -> some View {
        VStack(alignment: .leading, spacing: isMobileLayout ? 8 : 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Route options")
                    .font(panelHeaderFont)
                    .foregroundStyle(usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink)
                Text("Pick the Apple Maps route to use as the baseline.")
                    .font(panelDescriptionFont)
                    .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)
            }

            VStack(spacing: isMobileLayout ? 6 : 8) {
                ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                    routeOptionCard(route: route, index: index, isSelected: route.id == selectedRoute.id)
                }
            }
        }
    }

    private func routeMapPanel(routes: [RouteEstimate], selectedRoute: RouteEstimate) -> some View {
        VStack(alignment: .leading, spacing: isMobileLayout ? 8 : 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Route preview")
                    .font(panelHeaderFont)
                    .foregroundStyle(usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink)
                Text(selectedRoute.routeName.isEmpty ? "\(selectedRoute.sourceName) to \(selectedRoute.destinationName)" : selectedRoute.routeName)
                    .font(panelDescriptionFont)
                    .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)
            }

            mapPreview(routes, selectedRoute.id)
                .frame(minHeight: isMobileLayout ? 210 : 280, maxHeight: isMobileLayout ? 232 : 348)
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

    private func routeWeatherPanel(for route: RouteEstimate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Route Forecast")
                        .font(panelHeaderFont)
                        .foregroundStyle(usesDarkLiveDriveTheme ? setupPrimaryText : Palette.ink)

                    Text("Forecasts are matched to expected arrival times.")
                        .font(panelDescriptionFont)
                        .foregroundStyle(usesDarkLiveDriveTheme ? setupSecondaryText : Palette.cocoa)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button {
                    isRouteWeatherVisible.toggle()
                    if isRouteWeatherVisible, routeWeatherRouteID != route.id {
                        refreshRouteWeather(for: route)
                    }
                } label: {
                    Text(isRouteWeatherVisible ? "Hide" : "Show")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isRouteWeatherVisible ? setupPrimaryText : setupSecondaryText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(setupSurfaceMuted, in: Capsule())
                        .overlay {
                            Capsule().stroke(setupPanelBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }

            if isRouteWeatherVisible {
                if isRouteWeatherLoading && routeWeatherRouteID == route.id {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(setupSecondaryText)
                        Text("Loading route forecast...")
                            .font(panelDescriptionFont)
                            .foregroundStyle(setupSecondaryText)
                    }
                } else if routeWeatherRouteID == route.id, !routeWeatherEntries.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(routeWeatherEntries.prefix(4)) { entry in
                            routeWeatherRow(entry)
                        }
                    }
                } else {
                    Text(routeWeatherMessage)
                        .font(panelDescriptionFont)
                        .foregroundStyle(setupSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(setupSurfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(10)
        .background(setupSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(setupPanelBorder, lineWidth: 1)
        }
    }

    private func routeWeatherRow(_ entry: RouteWeatherDisplayEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.alertText == nil ? "cloud.sun.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(entry.alertText == nil ? setupSecondaryText : Palette.danger)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(setupPrimaryText)
                        .lineLimit(1)

                    Text(entry.arrivalText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(setupTertiaryText)
                        .lineLimit(1)
                }

                Text(entry.forecastText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(setupSecondaryText)
                    .lineLimit(2)

                Text(entry.detailText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(setupTertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
        }
        .padding(9)
        .background(setupSurfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        """
        TimeThrottle trip result
        \(completedTrip.displayRouteTitle)
        Completed: \(completedTrip.completedAt.formatted(date: .abbreviated, time: .shortened))
        Apple ETA baseline: \(Self.durationString(completedTrip.baselineRouteETAMinutes))
        Overall vs Apple ETA: \(Self.netString(completedTrip.netTimeGain))
        Time Above Speed Limit: \(Self.speedLimitMetricString(completedTrip.timeSavedBySpeeding, measuredMinutes: completedTrip.speedLimitMeasuredMinutes))
        Time Below Speed Limit: \(Self.speedLimitMetricString(completedTrip.timeLostBelowTargetPace, measuredMinutes: completedTrip.speedLimitMeasuredMinutes))
        Speed-limit coverage: \(Self.speedLimitCoverageString(for: completedTrip))
        Distance driven: \(Self.milesString(completedTrip.distanceDrivenMiles)) mi
        Elapsed drive time: \(Self.durationString(completedTrip.elapsedDriveMinutes))
        Average trip speed: \(Self.speedString(completedTrip.averageTripSpeed)) mph
        Top speed: \(Self.topSpeedString(completedTrip.topSpeedMPH))
        """
    }

    private func finishedTripMetricExplanation(for completedTrip: CompletedTripRecord) -> String {
        let baselineETA = Self.durationString(completedTrip.baselineRouteETAMinutes)
        return "Overall vs Apple ETA compares the whole trip to Apple Maps' baseline ETA of \(baselineETA). Time Above Speed Limit and Time Below Speed Limit are measured against available OpenStreetMap speed-limit estimates. Speed-limit analysis only includes route segments where an estimate was available."
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
        guidanceRerouteMessage = nil
        aircraftStatusText = showsAircraftLayer ? "Checking" : "Off"
        enforcementAlerts = []
        enforcementAlertsLastUpdatedAt = nil
        enforcementAlertStatusText = areEnforcementAlertsEnabled ? "Checking" : "Off"
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
            tracker.startTrip(requiresBackgroundContinuation: preferredNavigationProvider != .askEveryTime)
            selectedAppTab = .map
        }

        if tracker.isTracking {
            processLiveDriveNavigationHandoffIfNeeded()
            if areEnforcementAlertsEnabled, let coordinate = tracker.currentCoordinate {
                refreshEnforcementAlerts(near: coordinate, force: true)
            }
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
            liveDriveNavigationProviderPending = nil
            liveDriveNavigationHandoffMessage = nil
            isNavigationProviderChoicePresented = false
            tracker.endTrip()
            finalizeCompletedTrip()
            selectedAppTab = .drive
        }
    }

    private func startNewLiveDrive() {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            liveDriveRouteContext = nil
            liveDriveNavigationProviderPending = nil
            liveDriveNavigationHandoffMessage = nil
            liveDriveFinishedTrip = nil
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
            selectedAppTab = .drive
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
            isNavigationProviderChoicePresented = true
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
            overallResultTitle: liveDriveOverallResultTitle,
            overallResultValue: Self.netString(completedTrip.netTimeGain),
            overallResultTint: completedTrip.netTimeGain >= 0 ? Palette.success : Palette.danger,
            overallResultDetail: liveDriveVerdict(for: completedTrip.netTimeGain),
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
        routeWeatherRouteID = route.id
        routeWeatherEntries = []
        routeWeatherMessage = "Loading route forecast..."
        guard isRouteWeatherVisible else { return }

        isRouteWeatherLoading = true
        let routeID = route.id
        let routeGeometry = route.routeCoordinates.map {
            GuidanceCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
        let routeDistanceMeters = route.distanceMiles * 1_609.344
        let expectedTravelSeconds = route.expectedTravelMinutes * 60
        let timeZone = route.destinationTimeZone ?? .autoupdatingCurrent

        Task {
            do {
                let checkpoints = try weatherProvider.checkpoints(
                    for: routeGeometry,
                    routeDistanceMeters: routeDistanceMeters,
                    startDate: Date(),
                    expectedTravelTimeSeconds: expectedTravelSeconds,
                    maxCheckpointCount: 4
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
                    let displayEntries = Self.labeledWeatherEntries(
                        checkpoints.map { checkpoint in
                            Self.routeWeatherUnavailableEntry(from: checkpoint, timeZone: timeZone)
                        },
                        sourceName: route.sourceName,
                        destinationName: route.destinationName
                    )

                    await MainActor.run {
                        guard routeWeatherRouteID == routeID else { return }
                        routeWeatherEntries = displayEntries
                        routeWeatherMessage = "Forecast unavailable"
                        isRouteWeatherLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    guard routeWeatherRouteID == routeID else { return }
                    routeWeatherEntries = []
                    routeWeatherMessage = "Forecast unavailable"
                    isRouteWeatherLoading = false
                }
            }
        }
    }

    private func toggleVoiceGuidanceMute() {
        isVoiceGuidanceMuted.toggle()
        guidanceEngine.setMuted(isVoiceGuidanceMuted)
    }

    private func applyStoredVoiceSettings() {
        let resolvedIdentifier = resolvedStoredGuidanceVoiceIdentifier()
        if storedGuidanceVoiceIdentifier != (resolvedIdentifier ?? "") {
            storedGuidanceVoiceIdentifier = resolvedIdentifier ?? ""
        }

        guidanceEngine.applyVoiceSettings(
            VoiceGuidanceSettings(
                selectedVoiceIdentifier: resolvedIdentifier,
                speechRate: Float(storedGuidanceSpeechRate),
                volume: 0.92,
                isMuted: isVoiceGuidanceMuted
            )
        )
    }

    private func resolvedStoredGuidanceVoiceIdentifier() -> String? {
        let voices = guidanceEngine.availableVoiceOptions
        let storedIdentifier = storedGuidanceVoiceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

        if !storedIdentifier.isEmpty,
           voices.contains(where: { $0.identifier == storedIdentifier }) {
            return storedIdentifier
        }

        return voices.first?.identifier
    }

    private func selectGuidanceVoice(_ identifier: String?) {
        storedGuidanceVoiceIdentifier = identifier ?? ""
        guidanceEngine.selectVoice(identifier: identifier)
    }

    private func setGuidanceSpeechRate(_ rate: Double) {
        storedGuidanceSpeechRate = min(max(rate, 0.38), 0.56)
        guidanceEngine.setSpeechRate(Float(storedGuidanceSpeechRate))
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
                    aircraftLayer = AircraftLayerState(
                        isVisible: showsAircraftLayer,
                        aircraft: showsAircraftLayer ? aircraft : [],
                        lastUpdated: Date(),
                        isStale: false
                    )
                    aircraftStatusText = aircraft.isEmpty ? "No fresh nearby aircraft" : "\(aircraft.count) nearby"
                }
            } catch {
                await MainActor.run {
                    pruneStaleAircraftIfNeeded(now: Date())
                    aircraftStatusText = aircraftLayer.aircraft.isEmpty ? "Aircraft data unavailable" : "Last update unavailable"
                }
            }
        }
    }

    private func handleAircraftRefreshTick() {
        guard liveDriveScreenState == .driving, showsAircraftLayer else { return }
        let now = Date()
        pruneStaleAircraftIfNeeded(now: now)

        guard let coordinate = tracker.currentCoordinate else { return }
        refreshAircraft(near: coordinate, force: false)
    }

    private func refreshEnforcementAlertsIfNeeded(near coordinate: GuidanceCoordinate) {
        guard areEnforcementAlertsEnabled else { return }
        let now = Date()
        if let lastEnforcementAlertLookupAt,
           now.timeIntervalSince(lastEnforcementAlertLookupAt) < enforcementAlertRefreshIntervalSeconds {
            return
        }
        refreshEnforcementAlerts(near: coordinate, force: false)
    }

    private func refreshEnforcementAlerts(near coordinate: GuidanceCoordinate, force: Bool) {
        guard areEnforcementAlertsEnabled else { return }
        let now = Date()
        if !force,
           let lastEnforcementAlertLookupAt,
           now.timeIntervalSince(lastEnforcementAlertLookupAt) < enforcementAlertRefreshIntervalSeconds {
            return
        }
        lastEnforcementAlertLookupAt = now
        enforcementAlertStatusText = "Checking"

        Task {
            do {
                let alerts = try await enforcementAlertService.alerts(near: coordinate, radiusMiles: 5)
                await MainActor.run {
                    enforcementAlerts = alerts
                    enforcementAlertsLastUpdatedAt = Date()
                    enforcementAlertStatusText = alerts.isEmpty ? "No alerts nearby" : "\(alerts.count) alerts nearby"
                }
            } catch {
                await MainActor.run {
                    enforcementAlerts = []
                    enforcementAlertStatusText = "Alert data unavailable"
                }
            }
        }
    }

    private func handleEnforcementAlertRefreshTick() {
        guard liveDriveScreenState == .driving,
              areEnforcementAlertsEnabled,
              let coordinate = tracker.currentCoordinate else {
            return
        }

        refreshEnforcementAlerts(near: coordinate, force: false)
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
            subtitle: "Live Drive position",
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

    private static func speedLimitCoverageString(for trip: CompletedTripRecord) -> String {
        guard let ratio = trip.speedLimitCoverageRatio else { return "—" }
        return "\(Int((ratio * 100).rounded()))% measured"
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

        return RouteWeatherDisplayEntry(
            title: Self.checkpointTitle(for: entry.checkpoint),
            arrivalText: Self.timeString(entry.checkpoint.expectedArrivalDate, timeZone: timeZone),
            forecastText: forecast.summary,
            detailText: detailParts.isEmpty ? "Forecasts are matched to expected arrival times." : detailParts.joined(separator: " • "),
            temperatureText: temperatureText,
            aqiText: nil,
            alertText: forecast.alertStatus
        )
    }

    private static func routeWeatherUnavailableEntry(
        from checkpoint: RouteWeatherCheckpoint,
        timeZone: TimeZone
    ) -> RouteWeatherDisplayEntry {
        RouteWeatherDisplayEntry(
            title: Self.checkpointTitle(for: checkpoint),
            arrivalText: Self.timeString(checkpoint.expectedArrivalDate, timeZone: timeZone),
            forecastText: "Forecast unavailable",
            detailText: "WeatherKit data not available for this build or route.",
            temperatureText: nil,
            aqiText: nil,
            alertText: nil
        )
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
