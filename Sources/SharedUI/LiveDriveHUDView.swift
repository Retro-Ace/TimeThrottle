import Foundation
import SwiftUI

struct LiveDriveHUDGuidanceState: Equatable {
    var nextInstruction: String?
    var maneuverDistance: String?
    var isMuted: Bool
    var isOffRoute: Bool
    var rerouteStatus: String?
    var speedLimitEstimate: String?
    var speedLimitDetail: String?
    var weatherAlert: String?
    var isAircraftVisible: Bool
    var aircraftSummary: String?
    var enforcementAlertSummary: String?

    static let empty = LiveDriveHUDGuidanceState(
        nextInstruction: nil,
        maneuverDistance: nil,
        isMuted: false,
        isOffRoute: false,
        rerouteStatus: nil,
        speedLimitEstimate: nil,
        speedLimitDetail: nil,
        weatherAlert: nil,
        isAircraftVisible: false,
        aircraftSummary: nil,
        enforcementAlertSummary: nil
    )

    var hasVisibleContent: Bool {
        nextInstruction?.isEmpty == false ||
        isOffRoute ||
        rerouteStatus?.isEmpty == false ||
        speedLimitEstimate?.isEmpty == false ||
        weatherAlert?.isEmpty == false ||
        aircraftSummary?.isEmpty == false
    }
}

struct LiveDriveHUDVoiceOption: Identifiable, Equatable {
    var id: String { identifier }
    var identifier: String
    var name: String
    var language: String
}

struct LiveDriveHUDVoiceState: Equatable {
    var selectedVoiceIdentifier: String?
    var selectedVoiceName: String
    var speechRate: Double
    var isMuted: Bool
    var availableVoices: [LiveDriveHUDVoiceOption]

    static let empty = LiveDriveHUDVoiceState(
        selectedVoiceIdentifier: nil,
        selectedVoiceName: "System voice",
        speechRate: 0.46,
        isMuted: false,
        availableVoices: []
    )
}

struct LiveDriveHUDView: View {
    let statusTitle: String
    let milesDrivenValue: String
    let routeTitle: String
    let routeMeta: String
    let currentSpeedValue: String
    let averageSpeedValue: String
    let appleETAValue: String
    let liveETAValue: String
    let liveETADetail: String
    let aboveTargetValue: String
    let belowTargetValue: String
    let topSpeedValue: String
    let navigationLabel: String?
    let guidanceState: LiveDriveHUDGuidanceState
    let voiceState: LiveDriveHUDVoiceState
    let mapContent: AnyView?
    let isPaused: Bool
    let onToggleGuidanceMute: () -> Void
    let onSelectGuidanceVoice: (String?) -> Void
    let onShowGuidanceVoicePicker: () -> Void
    let onSetGuidanceSpeechRate: (Double) -> Void
    let onTestGuidanceVoice: () -> Void
    let onToggleAircraft: () -> Void
    let onPauseResume: () -> Void
    let onEndTrip: () -> Void
    let onClose: () -> Void

    @State private var isRouteInfoExpanded = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.10, blue: 0.13),
                        Color(red: 0.03, green: 0.04, blue: 0.05)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    hudChromeSection(viewportHeight: geometry.size.height)

                    if let mapContent {
                        mapSection(
                            mapContent: mapContent,
                            viewportHeight: geometry.size.height,
                            bottomInset: geometry.safeAreaInsets.bottom
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    @ViewBuilder
    private func hudChromeSection(viewportHeight: CGFloat) -> some View {
        if isRouteInfoExpanded {
            ScrollView(.vertical, showsIndicators: true) {
                hudChromeContent
                    .padding(.bottom, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: expandedChromeMaxHeight(for: viewportHeight), alignment: .top)
        } else {
            hudChromeContent
        }
    }

    private var hudChromeContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            topBar
            guidanceFoundationPanel
            primaryCardSection
            controlsSection
            routeInfoDrawer
        }
        .padding(.horizontal, 10)
        .padding(.top, 3)
    }

    private func expandedChromeMaxHeight(for viewportHeight: CGFloat) -> CGFloat {
        let reservedMapHeight = expandedMapMinimumHeight(for: viewportHeight)
        return max(360, viewportHeight - reservedMapHeight)
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: isPaused ? "pause.circle.fill" : "location.fill")
                    .font(.caption.weight(.bold))

                Text(statusTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (isPaused ? Palette.danger : Palette.success).opacity(0.26),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }

            Spacer(minLength: 6)

            milesDrivenSummary

            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.035), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    }
                    .accessibilityLabel("Close HUD")
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 1)
    }

    private var milesDrivenSummary: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("Miles Driven")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.54))

            Text(milesDrivenValue)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.76))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var routeCard: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(routeTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if !routeMeta.isEmpty {
                    Text(routeMeta)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.56))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let navigationLabel {
                Text(navigationLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.05), in: Capsule())
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(hudCardFill(cornerRadius: 18))
        .overlay(hudCardBorder(cornerRadius: 18, opacity: 0.06))
    }

    @ViewBuilder
    private var guidanceFoundationPanel: some View {
        if guidanceState.hasVisibleContent {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: guidanceState.isOffRoute ? "exclamationmark.triangle.fill" : "arrow.turn.up.right")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(guidanceState.isOffRoute ? Palette.danger : Palette.success)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.055), in: Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(guidanceTitle)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)

                        if let guidanceDetail {
                            Text(guidanceDetail)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.52))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }

                    Spacer(minLength: 6)

                    Button(action: onToggleGuidanceMute) {
                        Image(systemName: guidanceState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.66))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(guidanceState.isMuted ? "Unmute guidance" : "Mute guidance")
                }

                if primaryWeatherIndicator != nil || primaryAircraftIndicator != nil || primaryEnforcementIndicator != nil {
                    HStack(spacing: 6) {
                        if let primaryWeatherIndicator {
                            passiveIndicatorChip(title: primaryWeatherIndicator)
                        }

                        if let primaryAircraftIndicator {
                            passiveIndicatorChip(title: primaryAircraftIndicator)
                        }

                        if let primaryEnforcementIndicator {
                            passiveIndicatorChip(title: primaryEnforcementIndicator)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [
                        Palette.success.opacity(0.34),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(hudCardBorder(cornerRadius: 22, opacity: 0.075))
        }
    }

    private var guidanceTitle: String {
        if let rerouteStatus = guidanceState.rerouteStatus, !rerouteStatus.isEmpty {
            return rerouteStatus
        }

        if guidanceState.isOffRoute {
            return "Off route"
        }

        return guidanceState.nextInstruction ?? "Guidance based on Apple Maps route steps"
    }

    private var guidanceDetail: String? {
        if guidanceState.isOffRoute {
            return "Attempting route guidance back to destination"
        }

        return guidanceState.maneuverDistance
    }

    private var primaryWeatherIndicator: String? {
        guard let weatherAlert = guidanceState.weatherAlert?.trimmingCharacters(in: .whitespacesAndNewlines),
              !weatherAlert.isEmpty else {
            return nil
        }

        let lowercased = weatherAlert.lowercased()
        if lowercased == "checking" ||
            lowercased == "hidden" ||
            lowercased.contains("loading") ||
            lowercased.contains("unavailable") ||
            lowercased.contains("checkpoint") {
            return nil
        }

        return "Weather Ahead"
    }

    private var primaryAircraftIndicator: String? {
        guard guidanceState.isAircraftVisible,
              let aircraftSummary = guidanceState.aircraftSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !aircraftSummary.isEmpty else {
            return nil
        }

        let lowercased = aircraftSummary.lowercased()
        if lowercased == "off" ||
            lowercased == "checking" ||
            lowercased == "none nearby" ||
            lowercased.contains("no fresh") ||
            lowercased.contains("last update") ||
            lowercased.contains("unavailable") {
            return nil
        }

        return aircraftSummary
    }

    private var primaryEnforcementIndicator: String? {
        guard let summary = guidanceState.enforcementAlertSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty else {
            return nil
        }

        let lowercased = summary.lowercased()
        if lowercased == "off" ||
            lowercased.contains("unavailable") ||
            lowercased.contains("no alerts") {
            return nil
        }

        return summary
    }

    private func passiveIndicatorChip(title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.76))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.055), in: Capsule())
    }

    private func guidanceChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.42))
                .lineLimit(1)

            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var heroSpeedCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(currentSpeedValue)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text("mph")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
            .frame(maxWidth: .infinity, alignment: .center)

            speedLimitMiniPanel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: topSectionHeight, maxHeight: topSectionHeight, alignment: .leading)
        .background(hudCardFill(cornerRadius: 20))
        .overlay(hudCardBorder(cornerRadius: 20, color: Palette.success.opacity(0.26), lineWidth: 1.2))
    }

    private var avgSpeedChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 10.5, weight: .semibold))

            Text("Avg Spd \(averageSpeedValue)")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .foregroundStyle(Color.white.opacity(0.68))
        .frame(minWidth: 124, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    private var speedLimitMiniPanel: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Speed Limit")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.5))
                .lineLimit(1)

            Text(guidanceState.speedLimitEstimate ?? "Unavailable")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var primaryCardSection: some View {
        HStack(alignment: .top, spacing: 4) {
            heroSpeedCard

            infoStackPanel
                .frame(maxWidth: .infinity, minHeight: topSectionHeight, maxHeight: topSectionHeight)
        }
    }

    private var infoStackPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(routeTitle)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 8) {
                infoStackItem(
                    title: "Apple Maps ETA",
                    value: appleETAValue,
                    detail: nil
                )

                infoStackItem(
                    title: "ARRIVE",
                    value: liveETAValue,
                    detail: nil
                )
            }

            HStack(spacing: 6) {
                Image(systemName: "road.lanes")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.42))

                Text(remainingDistanceSummary)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.56))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: topSectionHeight, maxHeight: topSectionHeight, alignment: .topLeading)
        .background(hudCardFill(cornerRadius: 20))
        .overlay(hudCardBorder(cornerRadius: 20, opacity: 0.06))
    }

    private func infoStackItem(
        title: String,
        value: String,
        detail: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.36))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var remainingDistanceSummary: String {
        let pieces = routeMeta
            .split(separator: "•")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return pieces.last ?? routeMeta
    }

    private var middleMetricRow: some View {
        HStack(spacing: 4) {
            compactMetricCard(
                title: "Time Above Speed Limit",
                value: aboveTargetValue,
                tint: Palette.success,
                minHeight: 56,
                valueSize: 20,
                titleSize: 10,
                titleLineLimit: 2
            )

            compactMetricCard(
                title: "Time Below Speed Limit",
                value: belowTargetValue,
                tint: Palette.danger,
                minHeight: 56,
                valueSize: 20,
                titleSize: 10,
                titleLineLimit: 2
            )
        }
    }

    private func mapSection(
        mapContent: AnyView,
        viewportHeight: CGFloat,
        bottomInset: CGFloat
    ) -> some View {
        mapContent
            .frame(maxWidth: .infinity)
            .frame(
                minHeight: mapMinimumHeight(for: viewportHeight),
                idealHeight: mapIdealHeight(for: viewportHeight),
                maxHeight: .infinity,
                alignment: .bottom
            )
            .padding(.top, 2)
            .padding(.bottom, 0)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 16,
                    style: .continuous
                )
            )
    }

    private func mapMinimumHeight(for viewportHeight: CGFloat) -> CGFloat {
        isRouteInfoExpanded ? expandedMapMinimumHeight(for: viewportHeight) : max(360, viewportHeight * 0.58)
    }

    private func mapIdealHeight(for viewportHeight: CGFloat) -> CGFloat {
        isRouteInfoExpanded ? max(320, viewportHeight * 0.42) : viewportHeight * 0.66
    }

    private func expandedMapMinimumHeight(for viewportHeight: CGFloat) -> CGFloat {
        max(300, viewportHeight * 0.42)
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                compactActionButton(
                    title: isPaused ? "Resume" : "Pause",
                    systemImage: isPaused ? "play.fill" : "pause.fill",
                    foreground: Color.white,
                    background: isPaused ? Palette.success.opacity(0.9) : Color.white.opacity(0.08),
                    border: Color.white.opacity(isPaused ? 0.0 : 0.08),
                    action: onPauseResume
                )

                compactActionButton(
                    title: "End Trip",
                    systemImage: "stop.fill",
                    foreground: Palette.danger,
                    background: Palette.dangerBackground.opacity(0.82),
                    border: Palette.danger.opacity(0.14),
                    action: onEndTrip
                )
            }

            Text("Always obey traffic laws and road conditions.")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.38))
                .padding(.leading, 1)
        }
    }

    private var routeInfoDrawer: some View {
        VStack(alignment: .leading, spacing: isRouteInfoExpanded ? 9 : 0) {
            Button {
                withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                    isRouteInfoExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Capsule()
                        .fill(Color.white.opacity(0.34))
                        .frame(width: 34, height: 4)

                    Text("Route Info")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    drawerStatusChip("Weather")
                    drawerStatusChip("Aircraft")
                    drawerStatusChip("Pace")

                    Image(systemName: isRouteInfoExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.48))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isRouteInfoExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    drawerInfoRow(
                        title: "Speed Limit",
                        value: guidanceState.speedLimitEstimate ?? "Unavailable",
                        detail: guidanceState.speedLimitDetail ?? "OpenStreetMap estimate"
                    )

                    drawerInfoRow(
                        title: "Route Forecast",
                        value: weatherDrawerValue,
                        detail: "Forecasts are matched to expected arrival times."
                    )

                    drawerInfoRow(
                        title: "Enforcement Alerts",
                        value: guidanceState.enforcementAlertSummary ?? "Off",
                        detail: "Camera and enforcement reports. Coverage varies by region."
                    )

                    aircraftDrawerRow

                    drawerPaceGrid

                    voiceControlPanel

                    drawerInfoRow(
                        title: "Average speed",
                        value: averageSpeedValue,
                        detail: "Current trip average"
                    )

                    drawerInfoRow(
                        title: "Top speed",
                        value: topSpeedValue,
                        detail: "Highest valid GPS speed this trip"
                    )
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .background(hudCardFill(cornerRadius: 18))
        .overlay(hudCardBorder(cornerRadius: 18, opacity: 0.055))
    }

    private func drawerStatusChip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.48))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.035), in: Capsule())
    }

    private var weatherDrawerValue: String {
        guard let weatherAlert = guidanceState.weatherAlert, !weatherAlert.isEmpty else {
            return "Forecast unavailable"
        }

        return weatherAlert
    }

    private var aircraftDrawerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Low Aircraft Nearby")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .lineLimit(1)

                Text(guidanceState.aircraftSummary ?? (guidanceState.isAircraftVisible ? "Checking" : "Off"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onToggleAircraft) {
                Text(guidanceState.isAircraftVisible ? "Hide" : "Show")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.84))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.07), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var drawerPaceGrid: some View {
        HStack(spacing: 8) {
            drawerInfoRow(
                title: "Time Above Speed Limit",
                value: aboveTargetValue,
                detail: nil,
                tint: Palette.success
            )

            drawerInfoRow(
                title: "Time Below Speed Limit",
                value: belowTargetValue,
                detail: nil,
                tint: Palette.danger
            )
        }
    }

    private var voiceControlPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice Guidance")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.48))
                        .lineLimit(1)

                    Text(voiceState.isMuted ? "Muted" : voiceState.selectedVoiceName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 8)

                Button(action: onToggleGuidanceMute) {
                    Text(voiceState.isMuted ? "Unmute" : "Mute")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.84))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onTestGuidanceVoice) {
                    Text("Test")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.84))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(voiceState.isMuted)
                .opacity(voiceState.isMuted ? 0.55 : 1)
            }

            if !voiceState.availableVoices.isEmpty {
                Button(action: onShowGuidanceVoicePicker) {
                    HStack(spacing: 6) {
                        Text("Voice")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                        Spacer(minLength: 6)
                        Text(voiceState.selectedVoiceName)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Color.white.opacity(0.72))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Speech speed")
                    Spacer()
                    Text(voiceState.speechRate < 0.44 ? "Slower" : "Clear")
                }
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.48))

                Slider(
                    value: Binding(
                        get: { voiceState.speechRate },
                        set: { onSetGuidanceSpeechRate($0) }
                    ),
                    in: 0.38...0.56
                )
                .tint(Palette.success.opacity(0.84))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func drawerInfoRow(
        title: String,
        value: String,
        detail: String?,
        tint: Color = Color.white
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.48))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(tint.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func compactActionButton(
        title: String,
        systemImage: String,
        foreground: Color,
        background: Color,
        border: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(background)
                )
                .overlay(hudCardBorder(cornerRadius: 14, color: border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func compactMetricCard(
        title: String,
        detail: String? = nil,
        value: String,
        tint: Color = Color.white,
        minHeight: CGFloat = 64,
        valueSize: CGFloat = 20,
        titleSize: CGFloat = 11,
        titleLineLimit: Int = 1,
        verticalPadding: CGFloat = 7,
        expandToFill: Bool = false,
        contentSpacing: CGFloat = 2,
        detailSize: CGFloat = 11,
        fixedHeight: CGFloat? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            Text(title)
                .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(titleLineLimit)
                .fixedSize(horizontal: false, vertical: true)

            Text(value)
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: detailSize, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, verticalPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: minHeight,
            maxHeight: fixedHeight ?? (expandToFill ? .infinity : nil),
            alignment: .leading
        )
        .frame(height: fixedHeight)
        .background(hudCardFill(cornerRadius: 18))
        .overlay(hudCardBorder(cornerRadius: 18, opacity: 0.06))
    }

    private var topSectionHeight: CGFloat {
        112
    }

    private func hudCardFill(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.11),
                        Color.white.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func hudCardBorder(
        cornerRadius: CGFloat,
        color: Color = Color.white,
        opacity: Double,
        lineWidth: CGFloat = 1
    ) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(color.opacity(opacity), lineWidth: lineWidth)
    }

    private func hudCardBorder(
        cornerRadius: CGFloat,
        color: Color,
        lineWidth: CGFloat = 1
    ) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(color, lineWidth: lineWidth)
    }
}
