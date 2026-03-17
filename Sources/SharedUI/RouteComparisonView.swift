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

public struct RouteComparisonView: View {
    public enum PlatformStyle {
        case macOS
        case iOS
    }

    private let platformStyle: PlatformStyle
    private let platformBadgeText: String?
    private let brandLogo: Image?
    private let mapPreview: ([RouteEstimate], UUID?) -> AnyView

    @State private var workflow: Workflow = .tripCompare
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

    @State private var fromAddressText = "Red Ball Garage, 142 E 31st St, New York, NY"
    @State private var toAddressText = "Portofino Hotel & Marina, 260 Portofino Way, Redondo Beach, CA"
    @State private var routeOptions: [RouteEstimate] = []
    @State private var selectedRouteID: UUID?
    @State private var hoveredRouteID: UUID?
    @State private var routeErrorMessage: String?
    @State private var isCalculatingRoute = false
    @State private var didRunCaptureBootstrap = false
    @State private var captureScrollTarget: String?
    @State private var isShareSheetPresented = false

    private static let routePreviewCaptureID = "routePreviewCaptureSection"

    public init<MapPreview: View>(
        platformStyle: PlatformStyle,
        platformBadgeText: String? = nil,
        brandLogo: Image? = nil,
        @ViewBuilder mapPreview: @escaping ([RouteEstimate], UUID?) -> MapPreview
    ) {
        self.platformStyle = platformStyle
        self.platformBadgeText = platformBadgeText
        self.brandLogo = brandLogo
        self.mapPreview = { routes, selectedRouteID in
            AnyView(mapPreview(routes, selectedRouteID))
        }
    }

    private var isMobileLayout: Bool {
        platformStyle == .iOS
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
        Color(red: 0.06, green: 0.62, blue: 0.35)
    }

    private var headerGradientEnd: Color {
        Color(red: 0.18, green: 0.80, blue: 0.44)
    }

    private var mobileContentHorizontalPadding: CGFloat {
        isMobileLayout ? 0 : Layout.screenPadding
    }

    private var shouldRunCaptureBootstrap: Bool {
        ProcessInfo.processInfo.environment["TIMETHROTTLE_AUTOCAPTURE"] == "1"
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

    private var normalizedFromAddress: String {
        Self.normalizedAddress(fromAddressText)
    }

    private var normalizedToAddress: String {
        Self.normalizedAddress(toAddressText)
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
        switch workflow {
        case .segments:
            return "Measure time saved and time lost across a drive."
        case .tripCompare:
            return "Compare your trip against the route baseline and estimate the cost of speeding."
        }
    }

    private var timeComparisonScaleMinutes: Double {
        max(1, max(tripComparisonSummary.legalTravelMinutes, tripComparisonSummary.comparisonTravelMinutes))
    }

    private var baselineSummaryTitle: String {
        switch tripCompareDistanceSource {
        case .manualMiles:
            return "At limit"
        case .appleMapsRoute:
            return "Apple Maps ETA"
        }
    }

    private var paceStatTitle: String {
        switch tripCompareDistanceSource {
        case .manualMiles:
            return "Over/under limit"
        case .appleMapsRoute:
            return "Over/under route pace"
        }
    }

    private var baselineDetailSubtitle: String {
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
        switch tripCompareDistanceSource {
        case .manualMiles:
            return "This mode compares the same route distance against driving exactly at the posted speed limit, then estimates traffic loss, fuel burn, and ticket risk."
        case .appleMapsRoute:
            return "This mode compares your trip against Apple Maps route distance and estimated travel time for the same addresses, then estimates traffic loss, fuel burn, and ticket risk."
        }
    }

    private var differenceDetailSubtitle: String {
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

    private var trafficDelayTint: Color {
        speedCostSummary.trafficDelayMinutes > 0 ? Palette.danger : Palette.ink
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

        if let route = activeRouteEstimate {
            let optionsLabel = activeRouteOptions.count == 1 ? "1 route ready" : "\(activeRouteOptions.count) routes ready"
            return "\(optionsLabel) • Selected: \(Self.milesString(route.distanceMiles)) mi • \(Self.durationString(route.expectedTravelMinutes))"
        }

        if routeNeedsRefresh {
            return "Addresses changed. Recalculate the route."
        }

        if let routeErrorMessage {
            return routeErrorMessage
        }

        return "Enter two addresses and calculate the route."
    }

    private var routeStatusForeground: Color {
        if isCalculatingRoute {
            return Palette.cocoa
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
        isCalculatingRoute || normalizedFromAddress.isEmpty || normalizedToAddress.isEmpty
    }

    public var body: some View {
        PlatformLayout {
            mainContent
        }
        .task {
            guard shouldRunCaptureBootstrap, !didRunCaptureBootstrap else { return }
            didRunCaptureBootstrap = true
            calculateAppleMapsRoute()
        }
        #if os(iOS)
        .sheet(isPresented: $isShareSheetPresented) {
            ShareSheet(activityItems: [worthItShareText])
        }
        #endif
    }

    @ViewBuilder
    private var mainContent: some View {
        if isMobileLayout {
            mobileScreen
        } else {
            desktopBody
        }
    }

    private var mobileScreen: some View {
        ZStack(alignment: .top) {
            mobileScreenBackground
            mobileHeaderBackdrop

            mobileBody
        }
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
            .frame(height: heroHeight + 72, alignment: .top)
            .ignoresSafeArea(edges: .top)
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
                        if workflow == .tripCompare {
                            mobileTripCompareFlow
                        } else {
                            controls
                            summarySection
                            contentSection
                        }
                    }
                    .padding(.horizontal, mobileContentHorizontalPadding)
                    .padding(.top, Layout.sectionSpacing)
                    .padding(.bottom, Layout.screenPadding)
                    .background(Palette.workspace)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: captureScrollTarget) { _, target in
                guard let target else { return }
                withAnimation(nil) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    private var mobileTripCompareFlow: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            mobileRouteInputSection
            mobileManualMilesSection
            mobileComparisonInputSection
            mobileTripComparisonResultSection

            if tripCompareDistanceSource == .appleMapsRoute, let route = activeRouteEstimate {
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

    private var headerBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    headerGradientStart,
                    headerGradientEnd,
                    headerGradientEnd.opacity(0.80),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.10),
                    .clear
                ],
                center: .top,
                startRadius: 10,
                endRadius: 240
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
                workflowPicker
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
                Text("Route comparison")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.82))

                Text(heroSubtitle)
                    .font(heroSubtitleFont)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity)

            workflowPicker
        }
        .padding(.horizontal, Layout.screenPadding)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .safeAreaPadding(.top, 8)
        .frame(maxWidth: .infinity, minHeight: heroHeight, alignment: .bottom)
        .background {
            headerBackground
                .ignoresSafeArea(edges: .top)
        }
    }

    private var workflowPicker: some View {
        Picker("Workflow", selection: $workflow) {
            ForEach(Workflow.allCases) { workflow in
                Text(workflow.rawValue).tag(workflow)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
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
        if let platformBadgeText {
            Text(platformBadgeText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.16), in: Capsule())
        }
    }

    private var glassDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(height: 1)
            .padding(.horizontal, isMobileLayout ? 0 : Layout.screenPadding)
    }

    @ViewBuilder
    private var controls: some View {
        switch workflow {
        case .segments:
            segmentControls
        case .tripCompare:
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
                .tint(Palette.ferrariRed)

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
                    subtitle: "Choose the route source and calculate the Apple Maps route when needed."
                )
                distanceBasisPanel

                if tripCompareDistanceSource == .appleMapsRoute {
                    InsetPanel {
                        appleMapsRouteInputs
                    }
                }
            }
        }
    }

    private var mobileManualMilesSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                mobileSectionHeader(
                    title: "Manual miles entry",
                    subtitle: "Enter the posted limit and trip distance when you want a manual baseline."
                )

                if tripCompareDistanceSource == .manualMiles {
                    InsetPanel {
                        manualTripCompareInputs
                    }
                } else {
                    mobileHelperCard("Switch Distance basis to Manual miles to compare against a hand-entered route.")
                }
            }
        }
    }

    private var mobileComparisonInputSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Layout.innerSpacing) {
                mobileSectionHeader(
                    title: "Average speed selector",
                    subtitle: "Choose your trip pace input, then enter MPG and fuel price for the speed-cost model."
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
                .tint(Palette.ferrariRed)

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
                .tint(Palette.ferrariRed)

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

    private var appleMapsRouteInputs: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("From")
                .font(inputLabelFont)
                .foregroundStyle(Palette.cocoa)

            BrandedTextField(
                text: $fromAddressText,
                placeholder: "Starting address",
                fontSize: 17,
                fontWeight: .medium,
                compact: isMobileLayout
            )

            Text("To")
                .font(inputLabelFont)
                .foregroundStyle(Palette.cocoa)

            BrandedTextField(
                text: $toAddressText,
                placeholder: "Destination address",
                fontSize: 17,
                fontWeight: .medium,
                compact: isMobileLayout
            )

            HStack {
                Spacer()
                calculateRouteButton
            }

            routeStatusView
        }
    }

    private var calculateRouteButton: some View {
        Button {
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
                Text("Your average speed")
                    .font(inputLabelFont)
                    .foregroundStyle(Palette.cocoa)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    BrandedTextField(
                        text: $comparisonAverageSpeedText,
                        placeholder: "80",
                        width: 130,
                        fontSize: 24,
                        fontWeight: .bold,
                        compact: isMobileLayout
                    )

                    Text("mph")
                        .font(unitFont)
                        .foregroundStyle(Palette.cocoa)
                }
            } else {
                Text("Your trip time")
                    .font(inputLabelFont)
                    .foregroundStyle(Palette.cocoa)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    BrandedTextField(
                        text: $comparisonTripMinutesText,
                        placeholder: "30",
                        width: 130,
                        fontSize: 24,
                        fontWeight: .bold,
                        compact: isMobileLayout
                    )

                    Text("minutes")
                        .font(unitFont)
                        .foregroundStyle(Palette.cocoa)
                }
            }

            fuelModelInputs

            Text(tripCompareDistanceSource == .manualMiles ? "Compared against the same route distance at the posted speed. Average trip speed comes from the speed field or the derived duration." : "Compared against the Apple Maps route distance and ETA. Average trip speed comes from the speed field or the derived duration.")
                .font(panelDescriptionFont)
                .foregroundStyle(Palette.cocoa)
        }
    }

    private var fuelModelInputs: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            Text("Fuel penalty compares your baseline rated efficiency against the MPG you actually see at the faster pace.")
                .font(panelDescriptionFont)
                .foregroundStyle(Palette.cocoa)
        }
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
        switch workflow {
        case .segments:
            segmentSummarySection
        case .tripCompare:
            tripComparisonSummarySection
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
                        title: "Traffic lost",
                        value: Self.durationString(segmentSummary.lostMinutes),
                        tint: Palette.danger,
                        compact: true
                    )
                    SummaryCard(
                        title: "Net",
                        value: Self.netString(segmentSummary.netMinutes),
                        tint: segmentSummary.netMinutes >= 0 ? Palette.success : Palette.danger,
                        compact: true
                    )
                }

                mobilePillGrid(
                    items: [
                        StatPill(title: "Minutes above limit", value: Self.durationString(segmentSummary.speedingMinutes), compact: true),
                        StatPill(title: "Minutes below limit", value: Self.durationString(segmentSummary.trafficMinutes), compact: true),
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
                        title: "Traffic lost",
                        value: Self.durationString(segmentSummary.lostMinutes),
                        tint: Palette.danger
                    )
                    SummaryCard(
                        title: "Net",
                        value: Self.netString(segmentSummary.netMinutes),
                        tint: segmentSummary.netMinutes >= 0 ? Palette.success : Palette.danger
                    )
                }

                HStack(spacing: 10) {
                    StatPill(title: "Minutes above limit", value: Self.durationString(segmentSummary.speedingMinutes))
                    StatPill(title: "Minutes below limit", value: Self.durationString(segmentSummary.trafficMinutes))
                    StatPill(title: "Valid segments", value: "\(validSegments.count)")
                }
            }
        }
    }

    private var tripComparisonSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            brandedSectionHeader(
                title: "Route comparison",
                subtitle: "Compare your trip against the selected baseline."
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
        switch workflow {
        case .segments:
            segmentsSection
        case .tripCompare:
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
                    title: "Route comparison",
                    subtitle: "See how your pace compares to the selected baseline."
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
                        ? "Estimate the time gained against traffic delay, fuel burn, and ticket exposure using the posted limit as the risk baseline."
                        : "Estimate the time gained against traffic delay, fuel burn, and ticket exposure using the selected route pace as the risk baseline."
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
                        title: "Traffic delay",
                        value: Self.lossString(speedCostSummary.trafficDelayMinutes),
                        tint: trafficDelayTint,
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

    private func mobileHelperCard(_ text: String) -> some View {
        Text(text)
            .font(panelDescriptionFont)
            .foregroundStyle(Palette.cocoa)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panelAlt, in: RoundedRectangle(cornerRadius: Layout.innerCorner, style: .continuous))
    }

    // Platform parity requirement:
    // If the route preview content changes, update both macOS and iOS layouts to keep the same route selection behavior.
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
                Text("Select which Apple Maps route to compare against.")
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
        #if os(macOS)
        content.onHover { isInside in
            if isInside {
                hoveredRouteID = routeID
            } else if hoveredRouteID == routeID {
                hoveredRouteID = nil
            }
        }
        #else
        content
        #endif
    }

    private var comparisonTravelSubtitle: String {
        switch tripCompareEntryStyle {
        case .averageSpeed:
            return "\(Self.milesString(tripComparisonSummary.distanceMiles)) miles at \(Self.speedString(tripComparisonSummary.comparisonAverageSpeed)) mph average"
        case .tripDuration:
            return "\(Self.durationString(tripComparisonSummary.comparisonTravelMinutes)) across \(Self.milesString(tripComparisonSummary.distanceMiles)) miles"
        }
    }

    private var emptyComparisonPrompt: String {
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
                return "Enter both addresses, calculate the Apple Maps route, and then enter your trip speed or time."
            }

            if routeNeedsRefresh {
                return "The addresses changed after the last route lookup. Recalculate the Apple Maps route before comparing."
            }

            return "Calculate the Apple Maps route, then enter your trip speed or duration to compare against the selected route."
        }
    }

    private var overUnderPaceText: String {
        guard hasTripComparisonResult else { return summaryPlaceholderValue }

        if abs(comparisonSpeedDelta) < 0.01 {
            return "At pace"
        }

        if comparisonSpeedDelta > 0 {
            return "\(Self.speedString(comparisonSpeedDelta)) over"
        }

        return "\(Self.speedString(abs(comparisonSpeedDelta))) under"
    }

    private func shareResult() {
        isShareSheetPresented = true
    }

    private func calculateAppleMapsRoute() {
        routeErrorMessage = nil

        let sourceQuery = normalizedFromAddress
        let destinationQuery = normalizedToAddress

        guard !sourceQuery.isEmpty else {
            routeOptions = []
            selectedRouteID = nil
            routeErrorMessage = RouteLookupError.blankAddress("starting").localizedDescription
            return
        }

        guard !destinationQuery.isEmpty else {
            routeOptions = []
            selectedRouteID = nil
            routeErrorMessage = RouteLookupError.blankAddress("destination").localizedDescription
            return
        }

        isCalculatingRoute = true

        Task {
            do {
                let estimates = try await RouteLookupService.fetchRouteOptions(
                    sourceQuery: sourceQuery,
                    destinationQuery: destinationQuery
                )

                await MainActor.run {
                    routeOptions = estimates
                    selectedRouteID = estimates.first?.id
                    routeErrorMessage = nil
                    isCalculatingRoute = false
                    if captureSectionName == "routePreview" {
                        captureScrollTarget = Self.routePreviewCaptureID
                    }
                }
            } catch {
                await MainActor.run {
                    routeOptions = []
                    selectedRouteID = nil
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Time comparison")
                .font(inputLabelFont)
                .foregroundStyle(Palette.cocoa)

            ComparisonBarRow(
                title: baselineSummaryTitle,
                minutes: tripComparisonSummary.legalTravelMinutes,
                tint: Palette.ink,
                scaleMinutes: timeComparisonScaleMinutes,
                minutesLabel: Self.durationString(tripComparisonSummary.legalTravelMinutes),
                compact: isMobileLayout
            )
            ComparisonBarRow(
                title: "Your trip",
                minutes: tripComparisonSummary.comparisonTravelMinutes,
                tint: comparisonTripTint,
                scaleMinutes: timeComparisonScaleMinutes,
                minutesLabel: Self.durationString(tripComparisonSummary.comparisonTravelMinutes),
                compact: isMobileLayout
            )
        }
        .padding(isMobileLayout ? 14 : 16)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.surfaceBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 25, y: 10)
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
