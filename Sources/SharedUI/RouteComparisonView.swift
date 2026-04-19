import Foundation
import SwiftUI
#if canImport(TimeThrottleCore)
import TimeThrottleCore
#endif
#if os(iOS)
import UIKit
#endif

private enum LiveDriveScreenState: Equatable {
    case setup
    case driving
    case tripComplete
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

public struct RouteComparisonView: View {
    private let brandLogo: Image?
    private let mapPreview: ([RouteEstimate], UUID?) -> AnyView

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
    @State private var liveDriveTargetSpeedText = ""
    @State private var liveDriveRouteContext: LiveDriveRouteContext?
    @State private var liveDriveFinishedTrip: CompletedTripRecord?
    @State private var liveDriveNavigationProviderPending: NavigationProvider?
    @State private var liveDriveNavigationHandoffMessage: String?
    @State private var isLiveDriveHUDPresented = false
    @State private var liveDriveHUDWasDismissedForCurrentTrip = false
    @State private var isNavigationProviderChoicePresented = false
    @State private var isTripHistoryPresented = false
    @StateObject private var currentLocationResolver = CurrentLocationResolver()
    @StateObject private var autocompleteController = AppleMapsAutocompleteController()
    @StateObject private var tracker = LiveDriveTracker()
    @StateObject private var tripHistoryStore = TripHistoryStore()

    public init<MapPreview: View>(
        configuration: RouteComparisonConfiguration = RouteComparisonConfiguration(),
        brandLogo: Image? = nil,
        @ViewBuilder mapPreview: @escaping ([RouteEstimate], UUID?) -> MapPreview
    ) {
        _ = configuration
        self.brandLogo = brandLogo
        self.mapPreview = { routes, selectedRouteID in
            AnyView(mapPreview(routes, selectedRouteID))
        }
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

    private var liveDriveTargetSpeed: Double? {
        Self.number(from: liveDriveTargetSpeedText)
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

        return "TimeThrottle tracks the trip. Your map app handles navigation."
    }

    private var showsLiveDriveHUDReopenButton: Bool {
        liveDriveScreenState == .driving && liveDriveHUDWasDismissedForCurrentTrip
    }

    private var liveDriveHUDMapContent: AnyView? {
        guard let selectedRoute = liveDriveHUDRoute else { return nil }
        let routes = liveDriveRouteContext?.routes ?? liveDriveSetupRouteOptions
        #if os(iOS)
        return AnyView(LiveDriveHUDMapView(routes: routes, selectedRouteID: selectedRoute.id))
        #else
        return AnyView(mapPreview(routes, selectedRoute.id))
        #endif
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

        return max(55, (liveDriveTargetSpeed ?? 72) - 12)
    }

    private var liveDriveDisplayedTimeSaved: Double {
        liveDriveFinishedTrip?.timeSavedBySpeeding ?? tracker.tripSummary.timeSavedBySpeeding
    }

    private var liveDriveDisplayedTimeLost: Double {
        liveDriveFinishedTrip?.timeLostBelowTargetPace ?? tracker.tripSummary.timeLostBelowTargetPace
    }

    private var liveDriveDisplayedNetTimeGain: Double {
        liveDriveFinishedTrip?.netTimeGain ?? tracker.tripSummary.netTimeGain
    }

    private var liveDriveConfigurationForStart: LiveDriveConfiguration? {
        guard
            let route = activeRouteEstimate,
            !routeNeedsRefresh,
            let targetSpeed = liveDriveTargetSpeed,
            targetSpeed > 0
        else {
            return nil
        }

        return LiveDriveConfiguration(
            baselineRouteETAMinutes: route.expectedTravelMinutes,
            baselineRouteDistanceMiles: route.distanceMiles,
            targetSpeed: targetSpeed
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
            : "TimeThrottle tracks the trip. Your map app handles navigation."
    }

    private var liveDriveOverallResultTitle: String {
        "Overall vs Apple ETA"
    }

    private var liveDriveGainSummaryText: String {
        "\(Self.durationString(liveDriveDisplayedTimeSaved)) gained while driving above your target pace"
    }

    private var liveDriveBelowTargetSummaryText: String {
        "\(Self.durationString(liveDriveDisplayedTimeLost)) lost while below your target pace"
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
            return "Capture the route, choose your desired speed, and start a trip."
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
            mobileScreen
        }
        .task {
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
        .onChange(of: liveDriveScreenState) { _, newState in
            switch newState {
            case .driving:
                presentLiveDriveHUDIfNeeded()
            case .setup, .tripComplete:
                isLiveDriveHUDPresented = false
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
        .sheet(isPresented: $isTripHistoryPresented) {
            TripHistoryScreen(store: tripHistoryStore, brandLogo: brandLogo)
        }
        .fullScreenCover(isPresented: $isLiveDriveHUDPresented) {
            liveDriveHUDView
                .interactiveDismissDisabled()
        }
        .onChange(of: isNavigationProviderChoicePresented) { _, isPresented in
            if isPresented {
                isLiveDriveHUDPresented = false
            } else {
                presentLiveDriveHUDIfNeeded()
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

    #if os(iOS)
    private var liveDriveHUDView: some View {
        LiveDriveHUDView(
            statusTitle: liveDriveHeaderStatusTitle,
            milesDrivenValue: "\(Self.milesString(tracker.distanceTraveled)) mi",
            routeTitle: liveDriveHUDRouteTitle,
            routeMeta: liveDriveHUDRouteMetaText,
            currentSpeedValue: Self.speedString(tracker.currentSpeed),
            averageSpeedValue: liveDriveHUDAverageSpeedValue,
            appleETAValue: liveDriveHUDAppleETAValue,
            liveETAValue: liveDriveHUDLiveETAValue,
            liveETADetail: liveDriveHUDLiveETADetail,
            aboveTargetValue: Self.durationString(liveDriveDisplayedTimeSaved),
            belowTargetValue: Self.durationString(liveDriveDisplayedTimeLost),
            navigationLabel: liveDriveHUDNavigationLabel,
            mapContent: liveDriveHUDMapContent,
            isPaused: tracker.isPaused,
            onPauseResume: {
                if tracker.isPaused {
                    resumeLiveDrive()
                } else {
                    pauseLiveDrive()
                }
            },
            onEndTrip: {
                endLiveDrive()
            },
            onClose: {
                dismissLiveDriveHUD()
            }
        )
    }
    #endif

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
        #if os(iOS)
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()
        #else
        Palette.workspace
            .ignoresSafeArea()
        #endif
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
            .fill(Color.white.opacity(0.985))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 28, y: 14)
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
                .background(isPolishedLiveDriveSetup ? Color.clear : Palette.workspace)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isPolishedLiveDriveSetup ? Color.white : Palette.workspace)
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
        .padding(.top, liveDriveScreenState == .setup ? 18 : 30)
        .padding(.bottom, liveDriveScreenState == .setup ? 8 : 16)
        .safeAreaPadding(.top, 26)
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
        .background(Color.white.opacity(0.18), in: Capsule())
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
                Text("How much did speeding really buy you?")
                    .font(isMobileLayout ? .title2.weight(.bold) : .system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
            }
        }
    }

    @ViewBuilder
    private var platformBadge: some View {
        EmptyView()
    }

    private var glassDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.34))
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
                .foregroundStyle(Palette.cocoa)

            routeOriginModePicker

            if routeOriginInputMode == .currentLocation {
                currentLocationOriginField
            } else {
                routeAddressInputField(
                    text: $fromAddressText,
                    placeholder: "Enter a custom start",
                    field: .from
                )

                routeAutocompleteList(suggestions: fromSuggestions, field: .from)
            }

            Text("To")
                .font(inputLabelFont)
                .foregroundStyle(Palette.cocoa)

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
                                ? (isPolishedLiveDriveSetup ? Palette.ink : Color.white)
                                : Palette.cocoa
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
        isPolishedLiveDriveSetup ? Color(red: 0.94, green: 0.97, blue: 0.95) : .clear
    }

    private func routeOriginModeBackground(for mode: RouteOriginInputMode) -> Color {
        guard routeOriginInputMode == mode else {
            return isPolishedLiveDriveSetup ? Color.clear : Palette.panelAlt
        }

        return isPolishedLiveDriveSetup ? Color.white.opacity(0.95) : Palette.success
    }

    private func routeOriginModeBorder(for mode: RouteOriginInputMode) -> Color {
        if routeOriginInputMode == mode {
            return isPolishedLiveDriveSetup ? Color.black.opacity(0.05) : Palette.success
        }

        return isPolishedLiveDriveSetup ? Color.clear : Palette.surfaceBorder
    }

    private var routeInputBackground: Color {
        if isPolishedLiveDriveSetup {
            return Color.white.opacity(0.97)
        }

        return Palette.panelAlt
    }

    private func routeInputBorder(for field: RouteAddressField) -> Color {
        if focusedRouteAddressField == field {
            return Palette.success.opacity(isPolishedLiveDriveSetup ? 0.35 : 0.45)
        }

        return isPolishedLiveDriveSetup ? Color.black.opacity(0.05) : Palette.surfaceBorder
    }

    private var currentLocationOriginField: some View {
        Group {
            if isPolishedLiveDriveSetup {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Palette.successBackground)
                            .frame(width: 34, height: 34)

                        Image(systemName: "location.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Palette.success)
                    }

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
                .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.04), radius: 16, y: 7)
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
                        .fill((field == .from ? Palette.successBackground : Palette.dangerBackground).opacity(0.9))
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

            TextField(placeholder, text: text)
                .focused($focusedRouteAddressField, equals: field)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.ink)
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
                        .foregroundStyle(Palette.cocoa.opacity(0.75))
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
                                .foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Palette.cocoa)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < suggestions.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color.white.opacity(isPolishedLiveDriveSetup ? 0.98 : 1), in: RoundedRectangle(cornerRadius: isPolishedLiveDriveSetup ? 18 : 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: isPolishedLiveDriveSetup ? 18 : 14, style: .continuous)
                    .stroke(Palette.surfaceBorder.opacity(isPolishedLiveDriveSetup ? 0.7 : 1), lineWidth: 1)
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
                .foregroundStyle(Palette.cocoa)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                BrandedTextField(
                    text: text,
                    placeholder: placeholder,
                    fontSize: 24,
                    fontWeight: .bold,
                    compact: true
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(unit)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.cocoa)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var routeStatusView: some View {
        HStack(spacing: 12) {
            if isCalculatingRoute {
                ProgressView()
                    .tint(Palette.cocoa)
            }

            Text(routeStatusText)
                .font(routeStatusFont)
                .foregroundStyle(routeStatusForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, isMobileLayout ? 12 : 13)
        .padding(.vertical, isMobileLayout ? 7 : 10)
        .background(routeStatusBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var summarySection: some View {
        liveDriveSummarySection
    }

    private var liveDriveSetupSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    mobileSectionHeader(
                        title: "Live drive setup",
                        subtitle: "Capture the route baseline, choose your desired speed, and start tracking."
                    )

                    Spacer(minLength: 12)

                    tripHistoryShortcutButton
                }

                InsetPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        appleMapsRouteInputs
                    }
                }

                if let route = liveDriveSetupRoute {
                    routePreviewSection(routes: liveDriveSetupRouteOptions, selectedRoute: route)
                }

                InsetPanel {
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

                        Rectangle()
                            .fill(Color.black.opacity(0.06))
                            .frame(height: 1)

                        liveDriveAssumptionsSection

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
                                .shadow(color: Palette.success.opacity(0.20), radius: 3, y: 2)
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
        SectionCard {
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
            SectionCard {
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
        SectionCard {
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
            SectionCard {
                VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                    mobileSectionHeader(
                        title: "Trip result",
                        subtitle: "Review the finished result or share it."
                    )

                    InsetPanel {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .center, spacing: 14) {
                                finishedTripBrandLogo
                                    .frame(width: 82, height: 54, alignment: .center)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(completedTrip.displayRouteTitle)
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(Palette.ink)

                                    Text(completedTrip.routeLabel)
                                        .font(panelDescriptionFont)
                                        .foregroundStyle(Palette.cocoa)

                                    Text(completedTrip.completedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(Palette.cocoa)
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(liveDriveOverallResultTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.cocoa)

                                Text(Self.netString(completedTrip.netTimeGain))
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .foregroundStyle(completedTrip.netTimeGain >= 0 ? Palette.success : Palette.danger)

                                Text(liveDriveVerdict(for: completedTrip.netTimeGain))
                                    .font(panelDescriptionFont)
                                    .foregroundStyle(Palette.cocoa)
                            }

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)
                                ],
                                spacing: 12
                            ) {
                                SummaryCard(title: "Time Above Set Speed", value: Self.durationString(completedTrip.timeSavedBySpeeding), tint: Palette.success, compact: true)
                                SummaryCard(title: "Time Below Set Speed", value: Self.durationString(completedTrip.timeLostBelowTargetPace), tint: Palette.danger, compact: true)
                                SummaryCard(title: "Distance driven", value: "\(Self.milesString(completedTrip.distanceDrivenMiles)) mi", tint: Palette.ink, compact: true)
                                SummaryCard(title: "Elapsed drive time", value: Self.durationString(completedTrip.elapsedDriveMinutes), tint: Palette.ink, compact: true)
                                SummaryCard(title: "Average trip speed", value: "\(Self.speedString(completedTrip.averageTripSpeed)) mph", tint: Palette.ink, compact: true)
                                SummaryCard(title: "Target speed", value: "\(Self.speedString(completedTrip.targetSpeed)) mph", tint: Palette.ink, compact: true)
                            }

                            Text(finishedTripMetricExplanation(for: completedTrip))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Palette.cocoa)

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
        SectionCard {
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

                        if showsLiveDriveHUDReopenButton {
                            Button {
                                reopenLiveDriveHUD()
                            } label: {
                                Label("Open Drive HUD", systemImage: "gauge.with.dots.needle.67percent")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Palette.panelAlt, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Palette.surfaceBorder, lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if liveDriveScreenState == .tripComplete {
                        Button {
                            isTripHistoryPresented = true
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
                                .background(Palette.dangerBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Palette.danger.opacity(0.18), lineWidth: 1)
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
        if let brandLogo {
            brandLogo
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 70)
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
                .foregroundStyle(Palette.ink)
            Text(subtitle)
                .font(panelDescriptionFont)
                .foregroundStyle(Palette.cocoa)
        }
    }

    private var liveDriveNavigationProviderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Navigation App", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)

            VStack(spacing: 6) {
                ForEach(NavigationProvider.allCases) { provider in
                    let isSelected = preferredNavigationProvider == provider

                    Button {
                        preferredNavigationProviderBinding.wrappedValue = provider
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: navigationProviderIconName(for: provider))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isSelected ? Palette.success : Palette.cocoa)
                                .frame(width: 18)

                            Text(provider.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)

                            Spacer(minLength: 12)

                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isSelected ? Palette.success : Palette.cocoa.opacity(0.5))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            isSelected ? Palette.successBackground : Palette.panel,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? Palette.success.opacity(0.24) : Palette.surfaceBorder, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(liveDriveNavigationProviderHelperText)
                .font(panelDescriptionFont)
                .foregroundStyle(Palette.cocoa)
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
            isTripHistoryPresented = true
        } label: {
            Label("Trips", systemImage: "clock.arrow.circlepath")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Palette.successBackground, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var liveDriveLegalityNote: some View {
        Text("Always obey traffic laws and road conditions.")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Palette.cocoa)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var liveDriveAssumptionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            compactMetricField(title: "Desired Speed", text: $liveDriveTargetSpeedText, placeholder: "Enter desired speed...", unit: "mph")
        }
    }

    private func mobileHelperCard(_ text: String) -> some View {
        Text(text)
            .font(panelDescriptionFont)
            .foregroundStyle(Palette.cocoa)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panelAlt, in: RoundedRectangle(cornerRadius: Layout.innerCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Layout.innerCorner, style: .continuous)
                    .stroke(Palette.surfaceBorder.opacity(0.8), lineWidth: 1)
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
                    .foregroundStyle(Palette.cocoa)

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
        .background(Palette.panelAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
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
                .foregroundStyle(Palette.ink)

            Text(message)
                .font(panelDescriptionFont)
                .foregroundStyle(Palette.cocoa)

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
        .background(Palette.dangerBackground.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.danger.opacity(0.18), lineWidth: 1)
        }
    }

    private func routePreviewSection(routes: [RouteEstimate], selectedRoute: RouteEstimate) -> some View {
        Group {
            if isMobileLayout {
                VStack(alignment: .leading, spacing: 8) {
                    routeOptionsPanel(routes: routes, selectedRoute: selectedRoute)
                    routeMapPanel(routes: routes, selectedRoute: selectedRoute)
                }
            } else {
                HStack(alignment: .top, spacing: Layout.innerSpacing) {
                    routeOptionsPanel(routes: routes, selectedRoute: selectedRoute)
                        .frame(width: Layout.sidePanelWidth, alignment: .leading)
                    routeMapPanel(routes: routes, selectedRoute: selectedRoute)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(isMobileLayout ? 10 : 14)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.surfaceBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 25, y: 10)
    }

    private func routeOptionsPanel(routes: [RouteEstimate], selectedRoute: RouteEstimate) -> some View {
        VStack(alignment: .leading, spacing: isMobileLayout ? 8 : 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Route options")
                    .font(panelHeaderFont)
                    .foregroundStyle(Palette.ink)
                Text("Pick the Apple Maps route to use as the baseline.")
                    .font(panelDescriptionFont)
                    .foregroundStyle(Palette.cocoa)
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
                    .foregroundStyle(Palette.ink)
                Text(selectedRoute.routeName.isEmpty ? "\(selectedRoute.sourceName) to \(selectedRoute.destinationName)" : selectedRoute.routeName)
                    .font(panelDescriptionFont)
                    .foregroundStyle(Palette.cocoa)
            }

            mapPreview(routes, selectedRoute.id)
                .frame(minHeight: isMobileLayout ? 210 : 280, maxHeight: isMobileLayout ? 232 : 348)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Palette.surfaceBorder, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.10), radius: 30, y: 12)

            if isMobileLayout {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        StatPill(title: "Selected route", value: "\(Self.milesString(selectedRoute.distanceMiles)) mi", compact: true)
                        StatPill(title: "Apple ETA", value: Self.durationString(selectedRoute.expectedTravelMinutes), compact: true)
                        StatPill(title: "Options", value: "\(routes.count)", compact: true)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    StatPill(title: "Selected route", value: "\(Self.milesString(selectedRoute.distanceMiles)) mi")
                    StatPill(title: "Apple ETA", value: Self.durationString(selectedRoute.expectedTravelMinutes))
                    StatPill(title: "Options", value: "\(routes.count)")
                }
            }
        }
    }

    private func routeOptionCard(route: RouteEstimate, index: Int, isSelected: Bool) -> some View {
        let isHovered = hoveredRouteID == route.id
        let row = Button {
            selectedRouteID = route.id
        } label: {
            RouteOptionRow(
                title: index == 0 ? "Fastest" : "Option \(index + 1)",
                duration: Self.durationString(route.expectedTravelMinutes),
                distance: "\(Self.milesString(route.distanceMiles)) mi",
                isSelected: isSelected,
                isHovered: isHovered,
                compact: isMobileLayout
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
            targetSpeed: liveDriveTargetSpeed ?? tracker.configuration.targetSpeed,
            timeSavedBySpeeding: tracker.tripSummary.timeSavedBySpeeding,
            timeLostBelowTargetPace: tracker.tripSummary.timeLostBelowTargetPace,
            netTimeGain: tracker.tripSummary.netTimeGain
        )
    }

    private func finishedTripShareText(for completedTrip: CompletedTripRecord) -> String {
        """
        TimeThrottle trip result
        \(completedTrip.displayRouteTitle)
        Completed: \(completedTrip.completedAt.formatted(date: .abbreviated, time: .shortened))
        Apple ETA baseline: \(Self.durationString(completedTrip.baselineRouteETAMinutes))
        Overall vs Apple ETA: \(Self.netString(completedTrip.netTimeGain))
        Time Above Set Speed: \(Self.durationString(completedTrip.timeSavedBySpeeding))
        Time Below Set Speed: \(Self.durationString(completedTrip.timeLostBelowTargetPace))
        Distance driven: \(Self.milesString(completedTrip.distanceDrivenMiles)) mi
        Elapsed drive time: \(Self.durationString(completedTrip.elapsedDriveMinutes))
        Average trip speed: \(Self.speedString(completedTrip.averageTripSpeed)) mph
        Target speed: \(Self.speedString(completedTrip.targetSpeed)) mph
        """
    }

    private func finishedTripMetricExplanation(for completedTrip: CompletedTripRecord) -> String {
        let baselineETA = Self.durationString(completedTrip.baselineRouteETAMinutes)
        return "Overall vs Apple ETA compares the whole trip to Apple Maps' baseline ETA of \(baselineETA). Time Above Set Speed and Time Below Set Speed are measured against your chosen target speed."
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
                .foregroundStyle(Palette.cocoa)

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
        liveDriveHUDWasDismissedForCurrentTrip = false
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
        withAnimation(.snappy(duration: 0.28, extraBounce: 0)) {
            tracker.startTrip(requiresBackgroundContinuation: preferredNavigationProvider != .askEveryTime)
        }

        if tracker.isTracking {
            processLiveDriveNavigationHandoffIfNeeded()
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
            isLiveDriveHUDPresented = false
            liveDriveHUDWasDismissedForCurrentTrip = false
            liveDriveNavigationProviderPending = nil
            liveDriveNavigationHandoffMessage = nil
            isNavigationProviderChoicePresented = false
            tracker.endTrip()
            finalizeCompletedTrip()
        }
    }

    private func startNewLiveDrive() {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            isLiveDriveHUDPresented = false
            liveDriveHUDWasDismissedForCurrentTrip = false
            liveDriveRouteContext = nil
            liveDriveNavigationProviderPending = nil
            liveDriveNavigationHandoffMessage = nil
            liveDriveFinishedTrip = nil
            isNavigationProviderChoicePresented = false
            tracker.resetTrip()
        }
    }

    private func presentLiveDriveHUDIfNeeded() {
        guard liveDriveScreenState == .driving else { return }
        guard !liveDriveHUDWasDismissedForCurrentTrip else { return }
        guard !isNavigationProviderChoicePresented else { return }
        isLiveDriveHUDPresented = true
    }

    private func dismissLiveDriveHUD() {
        liveDriveHUDWasDismissedForCurrentTrip = true
        isLiveDriveHUDPresented = false
    }

    private func reopenLiveDriveHUD() {
        liveDriveHUDWasDismissedForCurrentTrip = false
        presentLiveDriveHUDIfNeeded()
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
        shareSheetItems = [finishedTripShareText(for: completedTrip)]
        isShareSheetPresented = true
    }

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
                .foregroundStyle(Palette.cocoa)

            ComparisonBarRow(
                title: baselineTitle,
                minutes: baselineMinutes,
                tint: Palette.ink,
                scaleMinutes: scaleMinutes,
                minutesLabel: Self.durationString(baselineMinutes),
                compact: isMobileLayout
            )
            ComparisonBarRow(
                title: comparisonTitle,
                minutes: comparisonMinutes,
                tint: comparisonTint,
                scaleMinutes: scaleMinutes,
                minutesLabel: comparisonLabel,
                compact: isMobileLayout
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

    private static func milesString(_ miles: Double) -> String {
        if abs(miles.rounded() - miles) < 0.01 {
            return String(Int(miles.rounded()))
        }

        return String(format: "%.1f", miles)
    }

    private static func speedString(_ speed: Double) -> String {
        if abs(speed.rounded() - speed) < 0.01 {
            return String(Int(speed.rounded()))
        }

        return String(format: "%.1f", speed)
    }
}

#if os(iOS)
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
