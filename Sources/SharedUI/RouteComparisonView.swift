import Foundation
import SwiftUI
#if canImport(TimeThrottleCore)
import TimeThrottleCore
#endif
#if os(iOS)
import UIKit
#endif

private struct EditableSegment: Identifiable {
    let id: UUID
    var label: String
    var speedText: String
    var minutesText: String

    init(
        id: UUID = UUID(),
        label: String,
        speedText: String,
        minutesText: String
    ) {
        self.id = id
        self.label = label
        self.speedText = speedText
        self.minutesText = minutesText
    }
}

private enum LiveDriveScreenState {
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
    @State private var selectedMode: Mode
    @State private var speedLimitText = "70"
    @State private var mode: CalculationMode = .simple
    @State private var segments: [EditableSegment] = [
        EditableSegment(label: "Open road", speedText: "80", minutesText: "18"),
        EditableSegment(label: "Rush hour", speedText: "45", minutesText: "25"),
        EditableSegment(label: "Cruising", speedText: "72", minutesText: "14")
    ]

    @State private var tripCompareDistanceSource: TripCompareDistanceSource = .appleMapsRoute
    @State private var milesDrivenText = "42"
    @State private var tripCompareEntryStyle: TripCompareEntryStyle = .averageSpeed
    @State private var comparisonAverageSpeedText = "80"
    @State private var comparisonTripMinutesText = "30"
    @State private var ratedMPGText = "28"
    @State private var observedMPGText = "22"
    @State private var fuelPriceText = "3.79"

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
    @State private var captureScrollTarget: String?
    @State private var shareSheetItems: [Any] = []
    @State private var isShareSheetPresented = false
    @AppStorage("timethrottle.preferredNavigationProvider") private var navigationProviderPreferenceRawValue = NavigationProvider.askEveryTime.rawValue
    @State private var liveDriveTargetSpeedText = "78"
    @State private var liveDriveMPGText = "24"
    @State private var liveDriveFuelPriceText = "3.79"
    @State private var liveDriveRouteContext: LiveDriveRouteContext?
    @State private var liveDriveFinishedTrip: CompletedTripRecord?
    @State private var liveDrivePostTripObservedMPGText = ""
    @State private var liveDriveNavigationProviderPending: NavigationProvider?
    @State private var liveDriveNavigationHandoffMessage: String?
    @State private var isNavigationProviderChoicePresented = false
    @State private var isTripHistoryPresented = false
    @StateObject private var currentLocationResolver = CurrentLocationResolver()
    @StateObject private var autocompleteController = AppleMapsAutocompleteController()
    @StateObject private var tracker = LiveDriveTracker()
    @StateObject private var tripHistoryStore = TripHistoryStore()

    private static let routePreviewCaptureID = "routePreviewCaptureSection"

    public init<MapPreview: View>(
        configuration: RouteComparisonConfiguration = RouteComparisonConfiguration(),
        brandLogo: Image? = nil,
        @ViewBuilder mapPreview: @escaping ([RouteEstimate], UUID?) -> MapPreview
    ) {
        self.brandLogo = brandLogo
        self.mapPreview = { routes, selectedRouteID in
            AnyView(mapPreview(routes, selectedRouteID))
        }
        _selectedMode = State(initialValue: configuration.initialMode)
        _tripCompareDistanceSource = State(
            initialValue: configuration.initialMode.tripCompareDistanceSource ?? .appleMapsRoute
        )
    }

    private var isMobileLayout: Bool {
        true
    }

    private var heroHeight: CGFloat {
        isMobileLayout ? 160 : 260
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
        isMobileLayout && selectedMode == .liveDrive && liveDriveScreenState == .setup
    }

    private var captureSectionName: String? {
        ProcessInfo.processInfo.environment["TIMETHROTTLE_CAPTURE_SECTION"]
    }

    private var speedLimit: Double? {
        Self.number(from: speedLimitText)
    }

    private var validSegments: [DriveSegment] {
        segments.compactMap { parsedSegment(for: $0) }
    }

    private var segmentSummary: CalculationSummary {
        guard let speedLimit else { return CalculationSummary() }
        return TimeThrottleCalculator.summarize(speedLimit: speedLimit, segments: validSegments, mode: mode)
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

    private var tripDistanceMiles: Double? {
        switch tripCompareDistanceSource {
        case .manualMiles:
            return Self.number(from: milesDrivenText)
        case .appleMapsRoute:
            return activeRouteEstimate?.distanceMiles
        }
    }

    private var comparisonBaselineSpeed: Double? {
        switch tripCompareDistanceSource {
        case .manualMiles:
            return speedLimit
        case .appleMapsRoute:
            guard
                let route = activeRouteEstimate,
                route.distanceMiles > 0,
                route.expectedTravelMinutes > 0
            else {
                return nil
            }

            return route.distanceMiles / (route.expectedTravelMinutes / 60)
        }
    }

    private var tripComparisonInput: TripComparisonInput? {
        switch tripCompareEntryStyle {
        case .averageSpeed:
            guard let averageSpeed = Self.number(from: comparisonAverageSpeedText), averageSpeed > 0 else {
                return nil
            }
            return .averageSpeed(averageSpeed)
        case .tripDuration:
            guard let tripDurationMinutes = Self.number(from: comparisonTripMinutesText), tripDurationMinutes > 0 else {
                return nil
            }
            return .tripDurationMinutes(tripDurationMinutes)
        }
    }

    private var tripComparisonSummary: TripComparisonSummary {
        guard
            let baselineSpeed = comparisonBaselineSpeed,
            let distanceMiles = tripDistanceMiles,
            let input = tripComparisonInput
        else {
            return TripComparisonSummary()
        }

        return TimeThrottleCalculator.compareTrip(
            distanceMiles: distanceMiles,
            speedLimit: baselineSpeed,
            input: input
        )
    }

    private var liveDriveTargetSpeed: Double? {
        Self.number(from: liveDriveTargetSpeedText)
    }

    private var liveDriveMPG: Double? {
        Self.number(from: liveDriveMPGText)
    }

    private var liveDriveFuelPrice: Double? {
        Self.number(from: liveDriveFuelPriceText)
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
            if routeNeedsRefresh {
                return "Route inputs changed. Recalculate the Apple Maps route before starting."
            }

            return "Calculate the Apple Maps route to capture your baseline ETA and distance."
        }

        let routeName = route.routeName.isEmpty ? "\(route.sourceName) to \(route.destinationName)" : route.routeName
        return "\(routeName) • \(Self.milesString(route.distanceMiles)) mi • \(Self.durationString(route.expectedTravelMinutes))"
    }

    private var liveDriveRouteLabel: String {
        liveDriveRouteContext?.routeLabel ?? liveDriveCurrentRouteLabel
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

    private var liveDriveEstimatedObservedMPG: Double? {
        guard let ratedMPG = liveDriveMPG, ratedMPG > 0 else { return nil }
        let speedDelta = max(0, (liveDriveTargetSpeed ?? 0) - liveDriveBaselineSpeed)
        return max(1, ratedMPG - speedDelta * 0.22)
    }

    private var liveDriveDisplayedTimeSaved: Double {
        liveDriveFinishedTrip?.timeSavedBySpeeding ?? tracker.tripSummary.timeSavedBySpeeding
    }

    private var liveDriveDisplayedTimeLost: Double {
        liveDriveFinishedTrip?.timeLostBelowTargetPace ?? tracker.tripSummary.timeLostBelowTargetPace
    }

    private var liveDriveDisplayedFuelPenalty: Double {
        liveDriveFinishedTrip?.fuelPenalty ?? tracker.tripSummary.fuelPenalty
    }

    private var liveDriveDisplayedNetTimeGain: Double {
        liveDriveFinishedTrip?.netTimeGain ?? tracker.tripSummary.netTimeGain
    }

    private var liveDriveObservedMPGEntry: Double? {
        let trimmed = liveDrivePostTripObservedMPGText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Self.number(from: trimmed)
    }

    private var liveDriveConfigurationForStart: LiveDriveConfiguration? {
        guard
            let route = activeRouteEstimate,
            !routeNeedsRefresh,
            let targetSpeed = liveDriveTargetSpeed,
            let ratedMPG = liveDriveMPG,
            let observedMPG = liveDriveEstimatedObservedMPG,
            let fuelPrice = liveDriveFuelPrice,
            targetSpeed > 0,
            ratedMPG > 0,
            observedMPG > 0,
            fuelPrice >= 0
        else {
            return nil
        }

        return LiveDriveConfiguration(
            baselineRouteETAMinutes: route.expectedTravelMinutes,
            baselineRouteDistanceMiles: route.distanceMiles,
            targetSpeed: targetSpeed,
            fuelModel: TripFuelModel(
                ratedMPG: ratedMPG,
                observedMPG: observedMPG,
                fuelPricePerGallon: fuelPrice
            )
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

    private var liveDriveBelowTargetMetricTitle: String {
        "Time Under Target Pace"
    }

    private var liveDriveGainSummaryText: String {
        "\(Self.durationString(liveDriveDisplayedTimeSaved)) by driving above your target pace"
    }

    private var liveDriveBelowTargetSummaryText: String {
        "\(Self.durationString(liveDriveDisplayedTimeLost)) below your target pace"
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

    private var liveDriveControlsSubtitle: String {
        switch liveDriveScreenState {
        case .setup:
            return "Capture the route, choose your pace, and start a trip."
        case .driving:
            return tracker.isPaused
                ? "Resume the same trip or end it without losing the finished result."
                : "Pause the trip or end it when you are finished driving."
        case .tripComplete:
            return "Your finished trip stays here until you start a new one."
        }
    }

    private var hasTripComparisonResult: Bool {
        tripComparisonSummary.distanceMiles > 0 &&
        tripComparisonSummary.speedLimit > 0 &&
        tripComparisonSummary.comparisonTravelMinutes > 0 &&
        tripComparisonSummary.comparisonAverageSpeed > 0
    }

    private var speedCostInput: SpeedCostInput? {
        guard
            hasTripComparisonResult,
            let ratedMPG = Self.number(from: ratedMPGText),
            let observedMPG = Self.number(from: observedMPGText),
            let fuelPrice = Self.number(from: fuelPriceText),
            ratedMPG > 0,
            observedMPG > 0,
            fuelPrice >= 0
        else {
            return nil
        }

        return SpeedCostInput(
            distanceMiles: tripComparisonSummary.distanceMiles,
            speedLimit: tripComparisonSummary.speedLimit,
            averageTripSpeed: tripComparisonSummary.comparisonAverageSpeed,
            baselineTravelMinutes: tripComparisonSummary.legalTravelMinutes,
            actualTravelMinutes: tripComparisonSummary.comparisonTravelMinutes,
            ratedMPG: ratedMPG,
            observedMPG: observedMPG,
            fuelPricePerGallon: fuelPrice
        )
    }

    private var speedCostSummary: SpeedCostSummary {
        guard let speedCostInput else { return SpeedCostSummary() }
        return SpeedCostCalculator.summarize(input: speedCostInput)
    }

    private var hasSpeedCostSummary: Bool {
        speedCostInput != nil
    }

    private var heroSubtitle: String {
        switch selectedMode {
        case .liveDrive:
            switch liveDriveScreenState {
            case .setup:
                return "Set up a live trip with GPS tracking, Apple Maps routing, and cost analysis."
            case .driving:
                return "A minimal dashboard focused on live speed, below-target pace loss, and net trip balance."
            case .tripComplete:
                return "Review the trip summary, then end the trip when you are done."
            }
        case .route:
            return "Compare your trip against an Apple Maps route baseline and estimate the cost of speeding."
        case .manual:
            return "Compare your trip against a manual distance and target speed, then estimate the cost of speeding."
        }
    }

    private var timeComparisonScaleMinutes: Double {
        max(1, max(tripComparisonSummary.legalTravelMinutes, tripComparisonSummary.comparisonTravelMinutes))
    }

    private var baselineSummaryTitle: String {
        if selectedMode == .manual {
            return "Speed A time"
        }

        switch tripCompareDistanceSource {
        case .manualMiles:
            return "At limit"
        case .appleMapsRoute:
            return "Apple Maps ETA"
        }
    }

    private var paceStatTitle: String {
        if selectedMode == .manual {
            return "Speed B vs A"
        }

        switch tripCompareDistanceSource {
        case .manualMiles:
            return "Over/under limit"
        case .appleMapsRoute:
            return "Over/under route pace"
        }
    }

    private var baselineDetailSubtitle: String {
        if selectedMode == .manual {
            return "\(Self.milesString(tripComparisonSummary.distanceMiles)) miles at \(Self.speedString(tripComparisonSummary.speedLimit)) mph"
        }

        switch tripCompareDistanceSource {
        case .manualMiles:
            return "\(Self.milesString(tripComparisonSummary.distanceMiles)) miles at \(Self.speedString(tripComparisonSummary.speedLimit)) mph"
        case .appleMapsRoute:
            guard let route = activeRouteEstimate else {
                return "Calculate an Apple Maps route"
            }

            if route.routeName.isEmpty {
                return "\(route.sourceName) to \(route.destinationName)"
            }

            return "\(route.routeName) from \(route.sourceName) to \(route.destinationName)"
        }
    }

    private var comparisonDetailsIntro: String {
        if selectedMode == .manual {
            return "This mode compares Speed A against Speed B across the same hand-entered route distance, then estimates time under target pace, fuel burn, and ticket risk."
        }

        switch tripCompareDistanceSource {
        case .manualMiles:
            return "This mode compares the same route distance against driving exactly at the posted speed limit, then estimates time under target pace, fuel burn, and ticket risk."
        case .appleMapsRoute:
            return "This mode compares your trip against Apple Maps route distance and estimated travel time for the same route inputs, then estimates time under target pace, fuel burn, and ticket risk."
        }
    }

    private var differenceDetailSubtitle: String {
        if selectedMode == .manual {
            return "Speed A time minus Speed B time"
        }

        switch tripCompareDistanceSource {
        case .manualMiles:
            return "At-limit travel time minus your trip time"
        case .appleMapsRoute:
            return "Apple Maps ETA minus your trip time"
        }
    }

    private var comparisonDifferenceTint: Color {
        guard hasTripComparisonResult else { return Palette.cocoa }
        if abs(tripComparisonSummary.timeDeltaMinutes) < 0.01 {
            return Palette.ink
        }
        return tripComparisonSummary.timeDeltaMinutes > 0 ? Palette.success : Palette.danger
    }

    private var comparisonTripTint: Color {
        guard hasTripComparisonResult else { return Palette.ink }
        if abs(tripComparisonSummary.timeDeltaMinutes) < 0.01 {
            return Palette.ink
        }
        return tripComparisonSummary.timeDeltaMinutes > 0 ? Palette.success : Palette.danger
    }

    private var comparisonSpeedDelta: Double {
        tripComparisonSummary.comparisonAverageSpeed - tripComparisonSummary.speedLimit
    }

    private var comparisonSpeedPillForeground: Color {
        guard hasTripComparisonResult else { return Palette.ink }
        if abs(comparisonSpeedDelta) < 0.01 {
            return Palette.ink
        }
        return comparisonSpeedDelta > 0 ? Palette.success : Palette.danger
    }

    private var comparisonSpeedPillBackground: Color {
        guard hasTripComparisonResult else { return Palette.pill }
        if abs(comparisonSpeedDelta) < 0.01 {
            return Palette.pill
        }
        return comparisonSpeedDelta > 0 ? Palette.successBackground : Palette.dangerBackground
    }

    private var comparisonAverageSpeedTint: Color {
        guard hasTripComparisonResult else { return Palette.ink }
        if abs(comparisonSpeedDelta) < 0.01 {
            return Palette.ink
        }
        return comparisonSpeedDelta > 0 ? Palette.success : Palette.danger
    }

    private var ticketRiskTint: Color {
        switch speedCostSummary.ticketRisk {
        case .low:
            return Palette.success
        case .moderate:
            return Palette.ferrariRed
        case .high:
            return Palette.danger
        }
    }

    private var timeUnderTargetPaceTint: Color {
        speedCostSummary.timeUnderTargetPaceMinutes > 0 ? Palette.danger : Palette.ink
    }

    private var fuelPenaltyTint: Color {
        speedCostSummary.fuelCostPenalty > 0 ? Palette.danger : Palette.ink
    }

    private var netBenefitTint: Color {
        if abs(speedCostSummary.netBenefitMinutes) < 0.01 {
            return Palette.ink
        }

        return speedCostSummary.netBenefitMinutes > 0 ? Palette.success : Palette.danger
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

        if routeNeedsRefresh {
            return "Route inputs changed. Recalculate the route."
        }

        if let routeErrorMessage {
            return routeErrorMessage
        }

        return "Choose a route start, enter a destination, and calculate the route."
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

    private var summaryPlaceholderValue: String {
        "────────"
    }

    private var summaryPlaceholderTint: Color {
        .secondary
    }

    private var baselineSummaryValue: String {
        hasTripComparisonResult ? Self.durationString(tripComparisonSummary.legalTravelMinutes) : summaryPlaceholderValue
    }

    private var baselineSummaryTint: Color {
        hasTripComparisonResult ? Palette.ink : summaryPlaceholderTint
    }

    private var comparisonTripSummaryValue: String {
        hasTripComparisonResult ? Self.durationString(tripComparisonSummary.comparisonTravelMinutes) : summaryPlaceholderValue
    }

    private var comparisonTripSummaryTint: Color {
        hasTripComparisonResult ? comparisonTripTint : summaryPlaceholderTint
    }

    private var comparisonDifferenceSummaryValue: String {
        hasTripComparisonResult ? Self.netString(tripComparisonSummary.timeDeltaMinutes) : summaryPlaceholderValue
    }

    private var comparisonDifferenceSummaryTint: Color {
        hasTripComparisonResult ? comparisonDifferenceTint : summaryPlaceholderTint
    }

    private var comparisonMilesStatValue: String {
        hasTripComparisonResult ? "\(Self.milesString(tripComparisonSummary.distanceMiles)) mi" : summaryPlaceholderValue
    }

    private var comparisonMilesStatForeground: Color {
        hasTripComparisonResult ? Palette.ink : summaryPlaceholderTint
    }

    private var comparisonAverageSpeedStatValue: String {
        hasTripComparisonResult ? "\(Self.speedString(tripComparisonSummary.comparisonAverageSpeed)) mph" : summaryPlaceholderValue
    }

    private var comparisonAverageSpeedStatForeground: Color {
        hasTripComparisonResult ? comparisonAverageSpeedTint : summaryPlaceholderTint
    }

    private var comparisonPaceStatValue: String {
        hasTripComparisonResult ? overUnderPaceText : summaryPlaceholderValue
    }

    private var comparisonPaceStatForeground: Color {
        hasTripComparisonResult ? comparisonSpeedPillForeground : summaryPlaceholderTint
    }

    private var worthItVerdict: String {
        if speedCostSummary.timeSavedMinutes > 90 {
            return "Probably."
        }

        if speedCostSummary.timeSavedMinutes >= 30 {
            return "Maybe."
        }

        if speedCostSummary.fuelCostPenalty > 20 {
            return "Probably not."
        }

        return "Maybe."
    }

    private var worthItVerdictTint: Color {
        switch worthItVerdict {
        case "Probably.":
            return Palette.success
        case "Probably not.":
            return Palette.danger
        default:
            return Palette.ferrariRed
        }
    }

    private var worthItLabelFont: Font {
        isMobileLayout ? .subheadline.weight(.semibold) : .system(size: 12, weight: .semibold, design: .rounded)
    }

    private var worthItShareText: String {
        "I drove \(Self.speedString(tripComparisonSummary.comparisonAverageSpeed)) mph for \(Self.milesString(tripComparisonSummary.distanceMiles)) miles and only saved \(Self.durationString(speedCostSummary.timeSavedMinutes)). Was it worth it? \(worthItVerdict)"
    }

    private var isCalculateRouteDisabled: Bool {
        isCalculatingRoute || routeSourceEndpoint == nil || routeDestinationEndpoint == nil
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
        .onChange(of: selectedMode) { _, newMode in
            syncTripCompareDistanceSource(with: newMode)

            if newMode != .manual, routeOriginInputMode == .currentLocation {
                currentLocationResolver.requestCurrentLocationIfNeeded()
            }
        }
        .onChange(of: liveDrivePostTripObservedMPGText) { _, _ in
            guard liveDriveFinishedTrip != nil else { return }
            updateFinishedTripObservedMPG()
        }
        #if os(iOS)
        .sheet(isPresented: $isShareSheetPresented) {
            ShareSheet(activityItems: shareSheetItems)
        }
        .sheet(isPresented: $isTripHistoryPresented) {
            TripHistoryScreen(store: tripHistoryStore, brandLogo: brandLogo)
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
        ScrollViewReader { proxy in
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
            .onChange(of: captureScrollTarget) { _, target in
                guard let target else { return }
                withAnimation(nil) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
            .background(Palette.workspace.ignoresSafeArea())
        }
    }

    private var mobileBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    mobileHeaderSection
                    glassDivider

                    VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                        switch selectedMode {
                        case .liveDrive:
                            mobileLiveDriveFlow
                        case .route, .manual:
                            mobileTripCompareFlow
                        }
                    }
                    .padding(.horizontal, mobileContentHorizontalPadding)
                    .padding(.top, Layout.sectionSpacing)
                    .padding(.bottom, Layout.screenPadding)
                    .background(isPolishedLiveDriveSetup ? Color.clear : Palette.workspace)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(isPolishedLiveDriveSetup ? Color.white : Palette.workspace)
            .onChange(of: captureScrollTarget) { _, target in
                guard let target else { return }
                withAnimation(nil) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    private var mobileTripCompareFlow: some View {
        Group {
            switch selectedMode {
            case .route:
                mobileRouteModeFlow
            case .manual:
                mobileManualModeFlow
            case .liveDrive:
                EmptyView()
            }
        }
    }

    private var mobileLiveDriveFlow: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            switch liveDriveScreenState {
            case .setup:
                liveDriveSetupSection
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .driving:
                liveDriveRouteContextSection
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                liveDriveComparisonSection
                    .transition(.opacity)
                liveDriveDashboardSection
                    .transition(.opacity)
                liveDriveSafetySection
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .tripComplete:
                liveDriveFinishedResultSection
                    .transition(.opacity)
                liveDriveRouteContextSection
                    .transition(.opacity)
                liveDriveCompletionSection
                    .transition(.opacity)
                liveDriveSafetySection
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28, extraBounce: 0), value: liveDriveScreenState)
    }

    private var mobileRouteModeFlow: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            mobileRouteInputSection
            mobileRouteComparisonInputSection
            mobileTripComparisonResultSection

            if let route = activeRouteEstimate {
                mobileMapPreviewSection(route: route)
            }

            if hasTripComparisonResult {
                mobileComparisonBarsSection
                mobileComparisonBreakdownSection
            } else {
                mobileComparisonPromptSection
            }
        }
    }

    private var mobileManualModeFlow: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            mobileManualCalculatorSection
            mobileTripComparisonResultSection

            if hasTripComparisonResult {
                mobileComparisonBarsSection
                mobileComparisonBreakdownSection
            } else {
                mobileComparisonPromptSection
            }
        }
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
            VStack(spacing: 8) {
                logoLockup

                Text(heroSubtitle)
                    .font(heroSubtitleFont)
                    .foregroundStyle(Color.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            HStack(spacing: 12) {
                modePicker
                    .frame(width: 250)

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
        VStack(spacing: 12) {
            logoLockup
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 6) {
                Text(selectedMode.rawValue)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.82))

                Text(heroSubtitle)
                    .font(heroSubtitleFont)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity)

            if selectedMode == .liveDrive, liveDriveScreenState != .setup {
                liveDriveHeaderStatus
            } else {
                modePicker
            }
        }
        .padding(.horizontal, Layout.screenPadding)
        .padding(.top, 30)
        .padding(.bottom, 16)
        .safeAreaPadding(.top, 26)
        .frame(maxWidth: .infinity, minHeight: heroHeight, alignment: .bottom)
        .background {
            headerBackground
                .ignoresSafeArea(.container, edges: .top)
        }
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mode")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.82))

            Picker("Mode", selection: $selectedMode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(Palette.success)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        switch selectedMode {
        case .liveDrive:
            liveDriveSetupSection
        case .route, .manual:
            tripCompareControls
        }
    }

    private var segmentControls: some View {
        SectionCard {
            Group {
                if isMobileLayout {
                    VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                        segmentSpeedLimitPanel
                        segmentModePanel
                    }
                } else {
                    HStack(alignment: .top, spacing: Layout.innerSpacing) {
                        segmentSpeedLimitPanel
                            .frame(maxWidth: .infinity, alignment: .leading)
                        segmentModePanel
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var segmentSpeedLimitPanel: some View {
        InsetPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Posted speed limit")
                    .font(inputLabelFont)
                    .foregroundStyle(Palette.cocoa)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    BrandedTextField(
                        text: $speedLimitText,
                        placeholder: "70",
                        width: 110,
                        fontSize: 26,
                        fontWeight: .bold,
                        compact: isMobileLayout
                    )

                    Text("mph")
                        .font(unitFont)
                        .foregroundStyle(Palette.cocoa)
                }
            }
        }
    }

    private var segmentModePanel: some View {
        InsetPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Calculation mode")
                    .font(inputLabelFont)
                    .foregroundStyle(Palette.cocoa)

                Picker("Calculation mode", selection: $mode) {
                    ForEach(CalculationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .tint(Palette.success)

                Text(mode.footnote)
                    .font(panelDescriptionFont)
                    .foregroundStyle(Palette.cocoa)
            }
        }
    }

    private var tripCompareControls: some View {
        SectionCard {
            Group {
                if isMobileLayout {
                    VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                        distanceBasisPanel
                        inputStylePanel
                        InsetPanel {
                            if tripCompareDistanceSource == .manualMiles {
                                manualTripCompareInputs
                            } else {
                                appleMapsRouteInputs
                            }
                        }
                        InsetPanel {
                            comparisonValueInputs
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                        HStack(alignment: .top, spacing: Layout.innerSpacing) {
                            distanceBasisPanel
                            inputStylePanel
                                .frame(width: Layout.sidePanelWidth, alignment: .leading)
                        }

                        HStack(alignment: .top, spacing: Layout.innerSpacing) {
                            InsetPanel {
                                if tripCompareDistanceSource == .manualMiles {
                                    manualTripCompareInputs
                                } else {
                                    appleMapsRouteInputs
                                }
                            }

                            InsetPanel {
                                comparisonValueInputs
                            }
                            .frame(width: Layout.sidePanelWidth, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private var mobileRouteInputSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                mobileSectionHeader(
                    title: "Route input",
                    subtitle: "Choose start and destination, then capture the Apple Maps baseline."
                )

                InsetPanel {
                    appleMapsRouteInputs
                }
            }
        }
    }

    private var mobileManualCalculatorSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                mobileSectionHeader(
                    title: "Manual calculator",
                    subtitle: "Enter the same distance and compare Speed A with Speed B."
                )

                InsetPanel {
                    manualModePrimaryInputs
                }

                InsetPanel {
                    manualModeFuelInputs
                }
            }
        }
    }

    private var mobileRouteComparisonInputSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                mobileSectionHeader(
                    title: "Trip pace",
                    subtitle: "Choose your trip pace and fuel assumptions."
                )
                inputStylePanel
                InsetPanel {
                    comparisonValueInputs
                }
            }
        }
    }

    private var distanceBasisPanel: some View {
        InsetPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Distance basis")
                    .font(inputLabelFont)
                    .foregroundStyle(Palette.cocoa)

                Picker("Distance basis", selection: $tripCompareDistanceSource) {
                    ForEach(TripCompareDistanceSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .tint(Palette.success)

                Text(tripCompareDistanceSource.description)
                    .font(panelDescriptionFont)
                    .foregroundStyle(Palette.cocoa)
            }
        }
    }

    private var inputStylePanel: some View {
        InsetPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Input style")
                    .font(inputLabelFont)
                    .foregroundStyle(Palette.cocoa)

                Picker("Input style", selection: $tripCompareEntryStyle) {
                    ForEach(TripCompareEntryStyle.allCases) { entryStyle in
                        Text(entryStyle.rawValue).tag(entryStyle)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .tint(Palette.success)

                Text(tripCompareEntryStyle.description)
                    .font(panelDescriptionFont)
                    .foregroundStyle(Palette.cocoa)
            }
        }
    }

    private var manualTripCompareInputs: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Posted speed limit")
                .font(inputLabelFont)
                .foregroundStyle(Palette.cocoa)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                BrandedTextField(
                    text: $speedLimitText,
                    placeholder: "70",
                    width: 110,
                    fontSize: 26,
                    fontWeight: .bold,
                    compact: isMobileLayout
                )

                Text("mph")
                    .font(unitFont)
                    .foregroundStyle(Palette.cocoa)
            }

            Text("Miles driven")
                .font(inputLabelFont)
                .foregroundStyle(Palette.cocoa)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                BrandedTextField(
                    text: $milesDrivenText,
                    placeholder: "42",
                    width: 130,
                    fontSize: 24,
                    fontWeight: .bold,
                    compact: isMobileLayout
                )

                Text("miles")
                    .font(unitFont)
                    .foregroundStyle(Palette.cocoa)
            }
        }
    }

    private var manualModePrimaryInputs: some View {
        Group {
            if isMobileLayout {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        compactMetricField(title: "Distance", text: $milesDrivenText, placeholder: "42", unit: "mi")
                        compactMetricField(title: "Speed A", text: $speedLimitText, placeholder: "65", unit: "mph")
                    }

                    compactMetricField(title: "Speed B", text: $comparisonAverageSpeedText, placeholder: "78", unit: "mph")
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Distance")
                        .font(inputLabelFont)
                        .foregroundStyle(Palette.cocoa)

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        BrandedTextField(
                            text: $milesDrivenText,
                            placeholder: "42",
                            width: 130,
                            fontSize: 24,
                            fontWeight: .bold,
                            compact: isMobileLayout
                        )

                        Text("miles")
                            .font(unitFont)
                            .foregroundStyle(Palette.cocoa)
                    }

                    Text("Speed A")
                        .font(inputLabelFont)
                        .foregroundStyle(Palette.cocoa)

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        BrandedTextField(
                            text: $speedLimitText,
                            placeholder: "65",
                            width: 110,
                            fontSize: 24,
                            fontWeight: .bold,
                            compact: isMobileLayout
                        )

                        Text("mph")
                            .font(unitFont)
                            .foregroundStyle(Palette.cocoa)
                    }

                    Text("Speed B")
                        .font(inputLabelFont)
                        .foregroundStyle(Palette.cocoa)

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        BrandedTextField(
                            text: $comparisonAverageSpeedText,
                            placeholder: "78",
                            width: 110,
                            fontSize: 24,
                            fontWeight: .bold,
                            compact: isMobileLayout
                        )

                        Text("mph")
                            .font(unitFont)
                            .foregroundStyle(Palette.cocoa)
                    }
                }
            }
        }
    }

    private var appleMapsRouteInputs: some View {
        VStack(alignment: .leading, spacing: isPolishedLiveDriveSetup ? 10 : 12) {
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

            HStack {
                Spacer()
                calculateRouteButton
            }

            routeStatusView
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
                        .padding(.vertical, isPolishedLiveDriveSetup ? 9 : 10)
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
                .padding(.vertical, 13)
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
        .padding(.horizontal, isPolishedLiveDriveSetup ? 16 : 14)
        .frame(minHeight: isPolishedLiveDriveSetup ? 56 : 50, alignment: .leading)
        .background(routeInputBackground, in: RoundedRectangle(cornerRadius: isPolishedLiveDriveSetup ? 18 : 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isPolishedLiveDriveSetup ? 18 : 14, style: .continuous)
                .stroke(routeInputBorder(for: field), lineWidth: 1)
        }
        .shadow(color: isPolishedLiveDriveSetup ? .black.opacity(0.04) : .clear, radius: 14, y: 6)
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

    private var calculateRouteButton: some View {
        Button {
            focusedRouteAddressField = nil
            autocompleteController.clear()
            calculateAppleMapsRoute()
        } label: {
            Label(isCalculatingRoute ? "Calculating route" : "Calculate route", systemImage: "map")
                .font(.headline)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Palette.success, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Palette.success.opacity(0.25), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
        .opacity(isCalculateRouteDisabled ? 0.55 : 1)
        .disabled(isCalculateRouteDisabled)
        .accessibilityIdentifier("calculate-route-button")
    }

    private var comparisonValueInputs: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tripCompareEntryStyle == .averageSpeed {
                compactMetricField(title: "Your average speed", text: $comparisonAverageSpeedText, placeholder: "80", unit: "mph")
            } else {
                compactMetricField(title: "Your trip time", text: $comparisonTripMinutesText, placeholder: "30", unit: "min")
            }

            fuelModelInputs

            Text(tripCompareDistanceSource == .manualMiles ? "Compared against the same distance at the posted speed. Average trip speed comes from the speed field or derived duration." : "Compared against the Apple Maps route distance and ETA. Average trip speed comes from the speed field or derived duration.")
                .font(panelDescriptionFont)
                .foregroundStyle(Palette.cocoa)
        }
    }

    private var fuelModelInputs: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isMobileLayout {
                HStack(alignment: .top, spacing: 12) {
                    compactMetricField(title: "Rated MPG", text: $ratedMPGText, placeholder: "28", unit: "mpg")
                    compactMetricField(title: "Observed MPG", text: $observedMPGText, placeholder: "22", unit: "mpg")
                }

                compactMetricField(title: "Fuel price", text: $fuelPriceText, placeholder: "3.79", unit: "/ gal")
            } else {
                Text("Vehicle rated MPG")
                    .font(inputLabelFont)
                    .foregroundStyle(Palette.cocoa)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    BrandedTextField(
                        text: $ratedMPGText,
                        placeholder: "28",
                        width: 130,
                        fontSize: 24,
                        fontWeight: .bold,
                        compact: isMobileLayout
                    )

                    Text("mpg")
                        .font(unitFont)
                        .foregroundStyle(Palette.cocoa)
                }

                Text("Observed MPG at your pace")
                    .font(inputLabelFont)
                    .foregroundStyle(Palette.cocoa)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    BrandedTextField(
                        text: $observedMPGText,
                        placeholder: "22",
                        width: 130,
                        fontSize: 24,
                        fontWeight: .bold,
                        compact: isMobileLayout
                    )

                    Text("mpg")
                        .font(unitFont)
                        .foregroundStyle(Palette.cocoa)
                }

                Text("Fuel price")
                    .font(inputLabelFont)
                    .foregroundStyle(Palette.cocoa)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    BrandedTextField(
                        text: $fuelPriceText,
                        placeholder: "3.79",
                        width: 130,
                        fontSize: 24,
                        fontWeight: .bold,
                        compact: isMobileLayout
                    )

                    Text("/ gallon")
                        .font(unitFont)
                        .foregroundStyle(Palette.cocoa)
                }
            }

            Text("Fuel penalty compares rated efficiency to what you actually see at the faster pace.")
                .font(panelDescriptionFont)
                .foregroundStyle(Palette.cocoa)
        }
    }

    private var manualModeFuelInputs: some View {
        VStack(alignment: .leading, spacing: 10) {
            fuelModelInputs
        }
    }

    private func compactMetricField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
        .padding(.vertical, isMobileLayout ? 9 : 10)
        .background(routeStatusBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var summarySection: some View {
        switch selectedMode {
        case .liveDrive:
            liveDriveSummarySection
        case .route, .manual:
            tripComparisonSummarySection
        }
    }

    private var liveDriveSetupSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    mobileSectionHeader(
                        title: "Live drive setup",
                        subtitle: "Capture the route baseline, choose your pace, and start tracking."
                    )

                    Spacer(minLength: 12)

                    tripHistoryShortcutButton
                }

                InsetPanel {
                    VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                        appleMapsRouteInputs
                    }
                }

                if let route = liveDriveSetupRoute {
                    routePreviewSection(routes: liveDriveSetupRouteOptions, selectedRoute: route)
                } else {
                    mobileHelperCard(liveDriveCurrentRouteLabel)
                }

                InsetPanel {
                    VStack(alignment: .leading, spacing: 12) {
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
                                .padding(.vertical, 14)
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
                liveDriveDashboardSection
                liveDriveSafetySection
            }
        } else if liveDriveScreenState == .tripComplete {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                liveDriveComparisonSection
                liveDriveRouteContextSection
                liveDriveTripSummarySection
                liveDriveCompletionSection
                liveDriveSafetySection
            }
        }
    }

    private var liveDriveDashboardSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                mobileSectionHeader(
                    title: "Live dashboard",
                    subtitle: "Current speed stays front and center while the trip is active."
                )

                VStack(spacing: 12) {
                    liveDriveMetricCard(
                        title: "Current speed",
                        value: "\(Self.speedString(tracker.currentSpeed)) mph",
                        tint: Palette.ink,
                        emphasis: .hero
                    )

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        liveDriveMetricCard(
                            title: "Distance driven",
                            value: "\(Self.milesString(tracker.distanceTraveled)) mi",
                            tint: Palette.ink
                        )

                        liveDriveMetricCard(
                            title: liveDriveBelowTargetMetricTitle,
                            value: Self.durationString(liveDriveDisplayedTimeLost),
                            tint: Palette.danger
                        )

                        liveDriveMetricCard(
                            title: "Trip balance",
                            value: Self.netString(liveDriveDisplayedNetTimeGain),
                            tint: liveDriveDisplayedNetTimeGain >= 0 ? Palette.success : Palette.danger,
                            emphasis: .strong
                        )
                        .gridCellColumns(2)
                    }
                }
            }
        }
    }

    private var liveDriveComparisonSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                mobileSectionHeader(
                    title: "Live comparison",
                    subtitle: "Compare the captured Apple Maps ETA to your live projected trip time."
                )

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
                        title: "Net result",
                        value: liveDriveVerdict,
                        tint: liveDriveVerdictTint,
                        isNarrative: true
                    )

                    liveDriveSummaryBlock(
                        title: "Extra fuel burned",
                        value: Self.currencyString(liveDriveDisplayedFuelPenalty),
                        tint: liveDriveDisplayedFuelPenalty > 0 ? Palette.danger : Palette.ink
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
                        subtitle: "Review the finished result, share it, or refine the fuel estimate."
                    )

                    InsetPanel {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .center, spacing: 14) {
                                worthItBrandLogoMobile
                                    .frame(width: 82, height: 54, alignment: .center)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(completedTrip.displayRouteTitle)
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(Palette.ink)

                                    Text(completedTrip.routeLabel)
                                        .font(panelDescriptionFont)
                                        .foregroundStyle(Palette.cocoa)
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Net result")
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
                                SummaryCard(title: "Time saved", value: Self.durationString(completedTrip.timeSavedBySpeeding), tint: Palette.success, compact: true)
                                SummaryCard(title: "Below target pace", value: Self.durationString(completedTrip.timeLostBelowTargetPace), tint: Palette.danger, compact: true)
                                SummaryCard(title: "Net result", value: Self.netString(completedTrip.netTimeGain), tint: completedTrip.netTimeGain >= 0 ? Palette.success : Palette.danger, isProminent: true, compact: true)
                                SummaryCard(title: "Fuel penalty", value: Self.currencyString(completedTrip.fuelPenalty), tint: completedTrip.fuelPenalty > 0 ? Palette.danger : Palette.ink, compact: true)
                            }

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

                            Rectangle()
                                .fill(Color.black.opacity(0.06))
                                .frame(height: 1)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Refine fuel result")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(Palette.ink)

                                Text("Observed MPG (optional)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.cocoa)

                                HStack(alignment: .center, spacing: 10) {
                                    BrandedTextField(
                                        text: $liveDrivePostTripObservedMPGText,
                                        placeholder: completedTrip.estimatedObservedMPG.map { Self.speedString($0) } ?? "24",
                                        fontSize: 24,
                                        fontWeight: .bold,
                                        compact: true
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Text("mpg")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Palette.cocoa)

                                    if !liveDrivePostTripObservedMPGText.isEmpty {
                                        Button("Clear") {
                                            liveDrivePostTripObservedMPGText = ""
                                        }
                                        .buttonStyle(.plain)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Palette.success)
                                    }
                                }

                                Text(liveDriveObservedMPGHelperText(for: completedTrip))
                                    .font(panelDescriptionFont)
                                    .foregroundStyle(Palette.cocoa)
                            }
                        }
                    }
                }
            }
        }
    }

    private var liveDriveCompletionSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                mobileSectionHeader(
                    title: "Drive details",
                    subtitle: "Keep the finished summary, elapsed time, and distance available until you start a new trip."
                )

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    liveDriveMetricCard(
                        title: "Distance driven",
                        value: "\(Self.milesString(liveDriveFinishedTrip?.distanceDrivenMiles ?? tracker.distanceTraveled)) mi",
                        tint: Palette.ink
                    )

                    liveDriveMetricCard(
                        title: "Elapsed drive time",
                        value: Self.durationString(liveDriveFinishedTrip?.elapsedDriveMinutes ?? tracker.tripDuration),
                        tint: Palette.ink
                    )

                    liveDriveMetricCard(
                        title: "Time above target",
                        value: Self.durationString(tracker.timeAboveTargetSpeed),
                        tint: Palette.ferrariRed
                    )

                    liveDriveMetricCard(
                        title: liveDriveBelowTargetMetricTitle,
                        value: Self.durationString(liveDriveDisplayedTimeLost),
                        tint: Palette.danger
                    )

                    liveDriveMetricCard(
                        title: "Trip balance",
                        value: Self.netString(liveDriveDisplayedNetTimeGain),
                        tint: liveDriveDisplayedNetTimeGain >= 0 ? Palette.success : Palette.danger,
                        emphasis: .strong
                    )
                    .gridCellColumns(2)
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

    private var segmentSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trip balance")
                .font(sectionHeaderFont)
                .foregroundStyle(Palette.ink)

            if isMobileLayout {
                VStack(spacing: 12) {
                    SummaryCard(
                        title: "Time saved",
                        value: Self.durationString(segmentSummary.savedMinutes),
                        tint: Palette.success,
                        compact: true
                    )
                    SummaryCard(
                        title: "Lost vs Target Pace",
                        value: Self.durationString(segmentSummary.lostMinutes),
                        tint: Palette.danger,
                        compact: true
                    )
                    SummaryCard(
                        title: "Trip balance",
                        value: Self.netString(segmentSummary.netMinutes),
                        tint: segmentSummary.netMinutes >= 0 ? Palette.success : Palette.danger,
                        compact: true
                    )
                }

                mobilePillGrid(
                    items: [
                        StatPill(title: "Minutes above limit", value: Self.durationString(segmentSummary.speedingMinutes), compact: true),
                        StatPill(title: "Minutes under target pace", value: Self.durationString(segmentSummary.timeUnderTargetPaceMinutes), compact: true),
                        StatPill(title: "Valid segments", value: "\(validSegments.count)", compact: true)
                    ]
                )
            } else {
                HStack(spacing: 12) {
                    SummaryCard(
                        title: "Time saved",
                        value: Self.durationString(segmentSummary.savedMinutes),
                        tint: Palette.success
                    )
                    SummaryCard(
                        title: "Lost vs Target Pace",
                        value: Self.durationString(segmentSummary.lostMinutes),
                        tint: Palette.danger
                    )
                    SummaryCard(
                        title: "Trip balance",
                        value: Self.netString(segmentSummary.netMinutes),
                        tint: segmentSummary.netMinutes >= 0 ? Palette.success : Palette.danger
                    )
                }

                HStack(spacing: 10) {
                    StatPill(title: "Minutes above limit", value: Self.durationString(segmentSummary.speedingMinutes))
                    StatPill(title: "Minutes under target pace", value: Self.durationString(segmentSummary.timeUnderTargetPaceMinutes))
                    StatPill(title: "Valid segments", value: "\(validSegments.count)")
                }
            }
        }
    }

    private var tripComparisonSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            brandedSectionHeader(
                title: selectedMode == .manual ? "Manual comparison" : "Route comparison",
                subtitle: selectedMode == .manual
                    ? "Compare Speed A and Speed B across the same distance."
                    : "Compare your trip against the selected baseline."
            )

            if isMobileLayout {
                VStack(spacing: 12) {
                    SummaryCard(
                        title: baselineSummaryTitle,
                        value: baselineSummaryValue,
                        tint: baselineSummaryTint,
                        compact: true
                    )
                    SummaryCard(
                        title: "Your trip",
                        value: comparisonTripSummaryValue,
                        tint: comparisonTripSummaryTint,
                        compact: true
                    )
                    SummaryCard(
                        title: "Difference",
                        value: comparisonDifferenceSummaryValue,
                        tint: comparisonDifferenceSummaryTint,
                        isProminent: true,
                        compact: true
                    )
                }

                comparisonMetricGrid(compact: true)
            } else {
                HStack(spacing: 12) {
                    SummaryCard(
                        title: baselineSummaryTitle,
                        value: baselineSummaryValue,
                        tint: baselineSummaryTint
                    )
                    SummaryCard(
                        title: "Your trip",
                        value: comparisonTripSummaryValue,
                        tint: comparisonTripSummaryTint
                    )
                    SummaryCard(
                        title: "Difference",
                        value: comparisonDifferenceSummaryValue,
                        tint: comparisonDifferenceSummaryTint,
                        isProminent: true
                    )
                }

                comparisonMetricGrid(compact: false)
            }

            if hasSpeedCostSummary {
                speedCostSummaryPanel
                worthItSummaryCard
            }

            if hasTripComparisonResult, !isMobileLayout {
                timeComparisonCard
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

    private func comparisonMetricGrid(compact: Bool) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            HStack {
                StatPill(
                    title: "Miles",
                    value: comparisonMilesStatValue,
                    foreground: comparisonMilesStatForeground,
                    compact: compact
                )
                Spacer(minLength: 0)
            }

            HStack {
                StatPill(
                    title: "Avg speed",
                    value: comparisonAverageSpeedStatValue,
                    foreground: comparisonAverageSpeedStatForeground,
                    compact: compact
                )
                Spacer(minLength: 0)
            }

            HStack {
                StatPill(
                    title: paceStatTitle,
                    value: comparisonPaceStatValue,
                    foreground: comparisonPaceStatForeground,
                    background: comparisonSpeedPillBackground,
                    compact: compact
                )
                Spacer(minLength: 0)
            }
            .gridCellColumns(2)
        }
    }

    private func brandedSectionHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            sectionLogoBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(sectionHeaderFont)
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(descriptionFont)
                    .foregroundStyle(Palette.cocoa)
            }
        }
    }

    private func brandedPanelHeader(title: String, subtitle: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            sectionLogoBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(panelHeaderFont)
                    .foregroundStyle(Palette.ink)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(panelDescriptionFont)
                        .foregroundStyle(Palette.cocoa)
                }
            }
        }
    }

    @ViewBuilder
    private var sectionLogoBadge: some View {
        if let brandLogo {
            brandLogo
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundStyle(Palette.cocoa.opacity(0.85))
        } else {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Palette.cocoa.opacity(0.85))
                .frame(width: 32, height: 32)
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        switch selectedMode {
        case .liveDrive:
            liveDriveContentSection
        case .route, .manual:
            comparisonDetailsSection
        }
    }

    private var segmentsSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                if isMobileLayout {
                    VStack(alignment: .leading, spacing: 10) {
                        segmentSectionIntro
                        addSegmentButton
                    }
                } else {
                    HStack {
                        segmentSectionIntro

                        Spacer()

                        addSegmentButton
                    }
                }

                VStack(spacing: 12) {
                    ForEach($segments) { $segment in
                        segmentRow(segment: $segment)
                    }
                }
            }
        }
    }

    private var segmentSectionIntro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Drive segments")
                .font(sectionHeaderFont)
                .foregroundStyle(Palette.ink)
            Text("Each row is a chunk of the drive at a roughly steady speed.")
                .font(descriptionFont)
                .foregroundStyle(Palette.cocoa)
        }
    }

    private var addSegmentButton: some View {
        Button {
            addSegment()
        } label: {
            Label("Add segment", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.ink)
    }

    private var comparisonDetailsSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Comparison details")
                        .font(sectionHeaderFont)
                        .foregroundStyle(Palette.ink)
                    Text(comparisonDetailsIntro)
                        .font(descriptionFont)
                        .foregroundStyle(Palette.cocoa)
                }

                if tripCompareDistanceSource == .appleMapsRoute, let route = activeRouteEstimate {
                    routePreviewSection(routes: activeRouteOptions, selectedRoute: route)
                        .id(Self.routePreviewCaptureID)
                }

                if hasTripComparisonResult {
                    if isMobileLayout {
                        VStack(spacing: 10) {
                            comparisonDetailCards
                        }
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(minimum: 220), spacing: 10),
                                GridItem(.flexible(minimum: 220), spacing: 10)
                            ],
                            spacing: 10
                        ) {
                            comparisonDetailCards
                        }
                    }
                } else {
                    Text(emptyComparisonPrompt)
                        .font(descriptionFont)
                        .foregroundStyle(Palette.cocoa)
                        .padding(isMobileLayout ? 14 : 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.panelAlt, in: RoundedRectangle(cornerRadius: Layout.innerCorner, style: .continuous))
                }
            }
        }
    }

    private var mobileTripComparisonResultSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                brandedPanelHeader(
                    title: selectedMode == .manual ? "Manual comparison" : "Route comparison",
                    subtitle: selectedMode == .manual
                        ? "See how Speed B compares to Speed A across the same trip."
                        : "See how your pace compares to the selected baseline."
                )

                VStack(spacing: 12) {
                    SummaryCard(
                        title: baselineSummaryTitle,
                        value: baselineSummaryValue,
                        tint: baselineSummaryTint,
                        compact: true
                    )
                    SummaryCard(
                        title: "Your trip",
                        value: comparisonTripSummaryValue,
                        tint: comparisonTripSummaryTint,
                        compact: true
                    )
                    SummaryCard(
                        title: "Difference",
                        value: comparisonDifferenceSummaryValue,
                        tint: comparisonDifferenceSummaryTint,
                        isProminent: true,
                        compact: true
                    )
                }

                comparisonMetricGrid(compact: true)

                if hasSpeedCostSummary {
                    speedCostSummaryPanel
                    worthItSummaryCard
                }
            }
        }
    }

    private func mobileMapPreviewSection(route: RouteEstimate) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                mobileSectionHeader(
                    title: "Map preview",
                    subtitle: route.routeName.isEmpty ? "\(route.sourceName) to \(route.destinationName)" : route.routeName
                )
                routePreviewSection(routes: activeRouteOptions, selectedRoute: route)
            }
        }
        .id(Self.routePreviewCaptureID)
    }

    private var mobileComparisonBarsSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                mobileSectionHeader(
                    title: "Comparison bars",
                    subtitle: "Visualize the baseline time against your actual trip."
                )
                timeComparisonCard
            }
        }
    }

    private var mobileComparisonBreakdownSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                mobileSectionHeader(
                    title: "Comparison breakdown",
                    subtitle: comparisonDetailsIntro
                )
                VStack(spacing: 10) {
                    comparisonDetailCards
                }
            }
        }
    }

    private var mobileComparisonPromptSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                mobileSectionHeader(
                    title: "Comparison bars",
                    subtitle: "Calculate the route or enter valid numbers to populate the full comparison."
                )
                mobileHelperCard(emptyComparisonPrompt)
            }
        }
    }

    private var speedCostSummaryPanel: some View {
        InsetPanel {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                brandedPanelHeader(
                    title: "Speed cost summary",
                    subtitle: tripCompareDistanceSource == .manualMiles
                        ? "Estimate time saved, time under target pace, fuel burn, and ticket exposure using the posted limit as the risk baseline."
                        : "Estimate time saved, time under target pace, fuel burn, and ticket exposure using the selected route pace as the risk baseline."
                )

                LazyVGrid(
                    columns: isMobileLayout
                        ? [
                            GridItem(.flexible(minimum: 130), spacing: 10),
                            GridItem(.flexible(minimum: 130), spacing: 10)
                        ]
                        : [
                            GridItem(.flexible(minimum: 170), spacing: 10),
                            GridItem(.flexible(minimum: 170), spacing: 10),
                            GridItem(.flexible(minimum: 170), spacing: 10)
                        ],
                    spacing: 10
                ) {
                    SummaryCard(
                        title: "Time saved",
                        value: Self.durationString(speedCostSummary.timeSavedMinutes),
                        tint: Palette.success,
                        compact: isMobileLayout
                    )
                    SummaryCard(
                        title: "Time Under Target Pace",
                        value: Self.lossString(speedCostSummary.timeUnderTargetPaceMinutes),
                        tint: timeUnderTargetPaceTint,
                        compact: isMobileLayout
                    )
                    SummaryCard(
                        title: "Fuel penalty",
                        value: Self.currencyPenaltyString(speedCostSummary.fuelCostPenalty),
                        tint: fuelPenaltyTint,
                        compact: isMobileLayout
                    )
                    SummaryCard(
                        title: "Ticket risk",
                        value: speedCostSummary.ticketRisk.rawValue,
                        tint: ticketRiskTint,
                        compact: isMobileLayout
                    )
                    SummaryCard(
                        title: "Net benefit",
                        value: Self.netString(speedCostSummary.netBenefitMinutes),
                        tint: netBenefitTint,
                        isProminent: true,
                        compact: isMobileLayout
                    )
                }
            }
        }
    }

    private var worthItSummaryCard: some View {
        InsetPanel {
            Group {
                if isMobileLayout {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(spacing: 16) {
                            worthItBrandLogoMobile
                                .frame(maxWidth: .infinity, alignment: .center)

                            Text("Was it worth it?")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }

                        worthItDetailsBlock
                        worthItVerdictBlock
                        shareResultButton
                    }
                } else {
                    HStack(alignment: .center, spacing: 24) {
                        worthItBrandLogoDesktop

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Was it worth it?")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.ink)

                            worthItDetailsBlock
                            worthItVerdictBlock
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var worthItBrandLogoMobile: some View {
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

    @ViewBuilder
    private var worthItBrandLogoDesktop: some View {
        if let brandLogo {
            brandLogo
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 90)
        } else {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(Palette.success)
                .frame(width: 90)
        }
    }

    private var worthItDetailsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            worthItLine(title: "Trip speed", value: "\(Self.speedString(tripComparisonSummary.comparisonAverageSpeed)) mph")
            worthItLine(title: "Distance", value: "\(Self.milesString(tripComparisonSummary.distanceMiles)) miles")
            worthItLine(title: "Time saved", value: Self.durationString(speedCostSummary.timeSavedMinutes))
            worthItLine(title: "Fuel cost", value: Self.currencyString(speedCostSummary.fuelCostPenalty))
            worthItLine(title: "Ticket risk", value: speedCostSummary.ticketRisk.rawValue.uppercased())
        }
    }

    private var worthItVerdictBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Verdict")
                .font(worthItLabelFont)
                .foregroundStyle(Palette.cocoa)

            Text(worthItVerdict)
                .font(isMobileLayout ? .headline.weight(.bold) : .system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(worthItVerdictTint)
        }
        .padding(.top, 4)
    }

    private func worthItLine(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(title):")
                .font(inputLabelFont)
                .foregroundStyle(Palette.cocoa)

            Text(value)
                .font(isMobileLayout ? .subheadline.weight(.semibold) : .system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink)
        }
    }

    private var shareResultButton: some View {
        Button {
            shareResult()
        } label: {
            Label("Share Result", systemImage: "square.and.arrow.up")
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Palette.success, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Palette.success.opacity(0.25), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var comparisonDetailCards: some View {
        Group {
            DetailRow(
                title: baselineSummaryTitle,
                subtitle: baselineDetailSubtitle,
                value: Self.durationString(tripComparisonSummary.legalTravelMinutes),
                tint: Palette.ink,
                compact: isMobileLayout
            )
            DetailRow(
                title: "Your trip",
                subtitle: comparisonTravelSubtitle,
                value: Self.durationString(tripComparisonSummary.comparisonTravelMinutes),
                tint: comparisonTripTint,
                compact: isMobileLayout
            )
            DetailRow(
                title: tripCompareEntryStyle == .tripDuration ? "Derived average speed" : "Average speed entered",
                subtitle: tripCompareDistanceSource == .manualMiles ? "Whole-trip average for the same route distance" : "Whole-trip average based on the Apple Maps route distance",
                value: "\(Self.speedString(tripComparisonSummary.comparisonAverageSpeed)) mph",
                tint: comparisonAverageSpeedTint,
                compact: isMobileLayout
            )
            DetailRow(
                title: "Difference",
                subtitle: differenceDetailSubtitle,
                value: Self.netString(tripComparisonSummary.timeDeltaMinutes),
                tint: comparisonDifferenceTint,
                compact: isMobileLayout
            )
        }
    }

    private func mobileSectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(panelHeaderFont)
                .foregroundStyle(Palette.ink)
            Text(subtitle)
                .font(panelDescriptionFont)
                .foregroundStyle(Palette.cocoa)
        }
    }

    private var liveDriveNavigationProviderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Navigation App", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)

            VStack(spacing: 8) {
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
                        .padding(.vertical, 12)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Trip assumptions")
                .font(inputLabelFont)
                .foregroundStyle(Palette.cocoa)

            HStack(alignment: .top, spacing: 12) {
                compactMetricField(title: "Target speed", text: $liveDriveTargetSpeedText, placeholder: "78", unit: "mph")
                compactMetricField(title: "MPG", text: $liveDriveMPGText, placeholder: "24", unit: "mpg")
            }

            compactMetricField(title: "Fuel price", text: $liveDriveFuelPriceText, placeholder: "3.79", unit: "/ gal")
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
                VStack(alignment: .leading, spacing: Layout.innerSpacing) {
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
        .padding(isMobileLayout ? 12 : 14)
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

    private var comparisonTravelSubtitle: String {
        if selectedMode == .manual {
            return "\(Self.milesString(tripComparisonSummary.distanceMiles)) miles at \(Self.speedString(tripComparisonSummary.comparisonAverageSpeed)) mph"
        }

        switch tripCompareEntryStyle {
        case .averageSpeed:
            return "\(Self.milesString(tripComparisonSummary.distanceMiles)) miles at \(Self.speedString(tripComparisonSummary.comparisonAverageSpeed)) mph average"
        case .tripDuration:
            return "\(Self.durationString(tripComparisonSummary.comparisonTravelMinutes)) across \(Self.milesString(tripComparisonSummary.distanceMiles)) miles"
        }
    }

    private var emptyComparisonPrompt: String {
        if selectedMode == .manual {
            return "Enter a distance plus Speed A and Speed B to compare the trip."
        }

        switch tripCompareDistanceSource {
        case .manualMiles:
            switch tripCompareEntryStyle {
            case .averageSpeed:
                return "Enter a positive speed limit, miles driven, and your average speed to compare the route."
            case .tripDuration:
                return "Enter a positive speed limit, miles driven, and your total trip time to derive the average speed and compare the route."
            }
        case .appleMapsRoute:
            if normalizedFromAddress.isEmpty || normalizedToAddress.isEmpty {
                return "Choose a route start, enter a destination, calculate the Apple Maps route, and then enter your trip speed or time."
            }

            if routeNeedsRefresh {
                return "The route inputs changed after the last lookup. Recalculate the Apple Maps route before comparing."
            }

            return "Calculate the Apple Maps route, then enter your trip speed or duration to compare against the selected route."
        }
    }

    private var overUnderPaceText: String {
        guard hasTripComparisonResult else { return summaryPlaceholderValue }

        if abs(comparisonSpeedDelta) < 0.01 {
            return selectedMode == .manual ? "Matched" : "At pace"
        }

        if comparisonSpeedDelta > 0 {
            return "\(Self.speedString(comparisonSpeedDelta)) over"
        }

        return "\(Self.speedString(abs(comparisonSpeedDelta))) under"
    }

    private func shareResult() {
        shareSheetItems = [worthItShareText]
        isShareSheetPresented = true
    }

    private func makeCompletedTripRecord() -> CompletedTripRecord? {
        guard let routeContext = liveDriveRouteContext else { return nil }

        let selectedRoute = routeContext.selectedRoute
        let sourceName = selectedRoute?.sourceName ?? routeContext.routeLabel
        let destinationName = selectedRoute?.destinationName ?? "Destination"
        let averageTripSpeed = tracker.tripDuration > 0
            ? tracker.distanceTraveled / (tracker.tripDuration / 60)
            : tracker.analysisResult.averageTripSpeed
        let estimatedObservedMPG = liveDriveEstimatedObservedMPG

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
            ratedMPG: liveDriveMPG ?? tracker.configuration.fuelModel?.ratedMPG ?? 0,
            estimatedObservedMPG: estimatedObservedMPG,
            enteredObservedMPG: liveDriveObservedMPGEntry,
            fuelPricePerGallon: liveDriveFuelPrice ?? tracker.configuration.fuelModel?.fuelPricePerGallon ?? 0,
            timeSavedBySpeeding: tracker.tripSummary.timeSavedBySpeeding,
            timeLostBelowTargetPace: tracker.tripSummary.timeLostBelowTargetPace,
            netTimeGain: tracker.tripSummary.netTimeGain,
            fuelPenalty: CompletedTripRecord.fuelPenalty(
                distanceMiles: tracker.distanceTraveled > 0 ? tracker.distanceTraveled : routeContext.baselineRouteDistanceMiles,
                ratedMPG: liveDriveMPG ?? tracker.configuration.fuelModel?.ratedMPG ?? 0,
                observedMPG: liveDriveObservedMPGEntry ?? estimatedObservedMPG,
                fuelPricePerGallon: liveDriveFuelPrice ?? tracker.configuration.fuelModel?.fuelPricePerGallon ?? 0
            )
        )
    }

    private func liveDriveObservedMPGHelperText(for completedTrip: CompletedTripRecord) -> String {
        if completedTrip.enteredObservedMPG != nil {
            return "Fuel penalty is using your observed MPG."
        }

        if let estimatedObservedMPG = completedTrip.estimatedObservedMPG {
            return "Leave this blank to keep the live estimate of \(Self.speedString(estimatedObservedMPG)) mpg."
        }

        return "Enter observed MPG if you want to recalculate true fuel burn after the drive."
    }

    private func finishedTripShareText(for completedTrip: CompletedTripRecord) -> String {
        """
        TimeThrottle trip result
        \(completedTrip.displayRouteTitle)
        Time saved: \(Self.durationString(completedTrip.timeSavedBySpeeding))
        Time under target pace: \(Self.durationString(completedTrip.timeLostBelowTargetPace))
        Net result: \(Self.netString(completedTrip.netTimeGain))
        Fuel penalty: \(Self.currencyString(completedTrip.fuelPenalty))
        """
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

        return arrival.formatted(date: .omitted, time: .shortened)
    }

    private func liveDriveVerdict(for netTimeGain: Double) -> String {
        if netTimeGain > 10 {
            return "You are still ahead after the time lost below target pace."
        }

        if netTimeGain > 0 {
            return "You only gained a little after the time lost below target pace."
        }

        return "Time lost below target pace erased the gain."
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
        liveDrivePostTripObservedMPGText = ""
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
            liveDriveNavigationProviderPending = nil
            liveDriveNavigationHandoffMessage = nil
            isNavigationProviderChoicePresented = false
            tracker.endTrip()
            finalizeCompletedTrip()
        }
    }

    private func startNewLiveDrive() {
        withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
            liveDriveRouteContext = nil
            liveDriveNavigationProviderPending = nil
            liveDriveNavigationHandoffMessage = nil
            liveDriveFinishedTrip = nil
            liveDrivePostTripObservedMPGText = ""
            isNavigationProviderChoicePresented = false
            tracker.resetTrip()
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
        liveDrivePostTripObservedMPGText = completedTrip.enteredObservedMPG.map { Self.speedString($0) } ?? ""
        tripHistoryStore.save(completedTrip)
    }

    private func updateFinishedTripObservedMPG() {
        guard let completedTrip = liveDriveFinishedTrip else { return }
        let updatedTrip = completedTrip.updatingObservedMPG(liveDriveObservedMPGEntry)
        liveDriveFinishedTrip = updatedTrip
        tripHistoryStore.save(updatedTrip)
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
        captureScrollTarget = nil
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
                    if captureSectionName == "routePreview" {
                        captureScrollTarget = Self.routePreviewCaptureID
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

    private func segmentRow(segment: Binding<EditableSegment>) -> some View {
        let parsed = parsedSegment(for: segment.wrappedValue)
        let delta = parsed.flatMap { item in
            speedLimit.map { limit in
                switch mode {
                case .simple:
                    if item.speed > limit { return item.minutes }
                    if item.speed < limit { return -item.minutes }
                    return 0
                case .speedAdjusted:
                    return TimeThrottleCalculator.timeDeltaComparedToLimit(speedLimit: limit, segment: item)
                }
            }
        }

        return Group {
            if isMobileLayout {
                VStack(alignment: .leading, spacing: 12) {
                    BrandedTextField(
                        text: segment.label,
                        placeholder: "Segment label",
                        fontSize: 17,
                        fontWeight: .semibold,
                        compact: true
                    )

                    HStack(spacing: 12) {
                        segmentMetricField(
                            title: "Speed",
                            text: segment.speedText,
                            placeholder: "75"
                        )

                        segmentMetricField(
                            title: "Minutes",
                            text: segment.minutesText,
                            placeholder: "15"
                        )
                    }

                    HStack(spacing: 12) {
                        ResultChip(delta: delta, formatter: Self.durationString)
                        Spacer()
                        deleteSegmentButton(id: segment.wrappedValue.id)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    BrandedTextField(
                        text: segment.label,
                        placeholder: "Segment label",
                        fontSize: 17,
                        fontWeight: .semibold,
                        compact: false
                    )
                    .frame(minWidth: 160)

                    segmentMetricField(
                        title: "Speed",
                        text: segment.speedText,
                        placeholder: "75"
                    )

                    segmentMetricField(
                        title: "Minutes",
                        text: segment.minutesText,
                        placeholder: "15"
                    )

                    Spacer()

                    ResultChip(delta: delta, formatter: Self.durationString)

                    deleteSegmentButton(id: segment.wrappedValue.id)
                }
            }
        }
        .padding(isMobileLayout ? 12 : 14)
        .background(Palette.panelAlt, in: RoundedRectangle(cornerRadius: Layout.innerCorner, style: .continuous))
    }

    private func segmentMetricField(
        title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(isMobileLayout ? .caption.weight(.semibold) : .system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.cocoa)

            BrandedTextField(
                text: text,
                placeholder: placeholder,
                width: 92,
                fontSize: 17,
                fontWeight: .bold,
                compact: isMobileLayout
            )
        }
    }

    private func deleteSegmentButton(id: UUID) -> some View {
        Button(role: .destructive) {
            removeSegment(id: id)
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.bordered)
        .tint(Palette.danger)
        .disabled(segments.count == 1)
    }

    private var timeComparisonCard: some View {
        timeComparisonRows(
            baselineTitle: baselineSummaryTitle,
            baselineMinutes: tripComparisonSummary.legalTravelMinutes,
            comparisonTitle: "Your trip",
            comparisonMinutes: tripComparisonSummary.comparisonTravelMinutes,
            comparisonTint: comparisonTripTint,
            comparisonLabel: Self.durationString(tripComparisonSummary.comparisonTravelMinutes),
            scaleMinutes: timeComparisonScaleMinutes
        )
        .padding(isMobileLayout ? 14 : 16)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.surfaceBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 25, y: 10)
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

    private func addSegment() {
        segments.append(
            EditableSegment(
                label: "Segment \(segments.count + 1)",
                speedText: speedLimitText.isEmpty ? "70" : speedLimitText,
                minutesText: "10"
            )
        )
    }

    private func removeSegment(id: UUID) {
        segments.removeAll { $0.id == id }
    }

    private func syncTripCompareDistanceSource(with modeSelection: Mode) {
        guard let source = modeSelection.tripCompareDistanceSource else { return }
        tripCompareDistanceSource = source

        if modeSelection == .manual {
            tripCompareEntryStyle = .averageSpeed
        }
    }

    private func parsedSegment(for editable: EditableSegment) -> DriveSegment? {
        guard
            let speed = Self.number(from: editable.speedText),
            let minutes = Self.number(from: editable.minutesText),
            speed > 0,
            minutes > 0
        else {
            return nil
        }

        return DriveSegment(id: editable.id, speed: speed, minutes: minutes)
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

    private static func lossString(_ minutes: Double) -> String {
        guard minutes > 0.01 else { return "0m" }
        return "-\(durationString(minutes))"
    }

    private static func currencyPenaltyString(_ amount: Double) -> String {
        if abs(amount) < 0.005 {
            return "$0.00"
        }

        return amount > 0 ? "+\(currencyString(amount))" : "-\(currencyString(abs(amount)))"
    }

    private static func currencyString(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
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
