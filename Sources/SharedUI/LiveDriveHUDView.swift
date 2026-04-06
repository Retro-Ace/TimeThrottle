import SwiftUI

struct LiveDriveHUDView: View {
    let statusTitle: String
    let routeTitle: String
    let routeMeta: String
    let currentSpeedValue: String
    let averageSpeedValue: String
    let appleETAValue: String
    let liveETAValue: String
    let liveETADetail: String
    let aboveTargetValue: String
    let belowTargetValue: String
    let navigationLabel: String?
    let mapContent: AnyView?
    let isPaused: Bool
    let onPauseResume: () -> Void
    let onEndTrip: () -> Void
    let onClose: () -> Void

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

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        topBar
                        routeCard
                        heroSpeedCard
                        primaryMetricsGrid
                        controlsSection

                        if let mapContent {
                            Spacer(minLength: 4)
                            mapSection(
                                mapContent: mapContent,
                                viewportHeight: geometry.size.height
                            )
                        }
                    }
                    .frame(
                        minHeight: geometry.size.height - geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom - 12,
                        alignment: .top
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
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

            Spacer(minLength: 10)

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
        .padding(.top, 2)
    }

    private var routeCard: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(panelBackground)
    }

    private var heroSpeedCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Current speed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.66))

                Spacer(minLength: 8)

                avgSpeedChip
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(currentSpeedValue)
                    .font(.system(size: 70, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text("mph")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Palette.success.opacity(0.26), lineWidth: 1.2)
        }
    }

    private var avgSpeedChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.caption2.weight(.semibold))

            Text("Avg \(averageSpeedValue)")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.white.opacity(0.68))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    private var primaryMetricsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            compactMetricCard(
                title: "APPLE ETA",
                detail: "baseline route time",
                value: appleETAValue
            )

            compactMetricCard(
                title: "ARRIVE",
                detail: liveETADetail,
                value: liveETAValue
            )

            compactMetricCard(
                title: "Time above\ntarget speed",
                value: aboveTargetValue,
                tint: Palette.success
            )

            compactMetricCard(
                title: "Time below\ntarget speed",
                value: belowTargetValue,
                tint: Palette.danger
            )
        }
    }

    private func mapSection(
        mapContent: AnyView,
        viewportHeight: CGFloat
    ) -> some View {
        mapContent
            .frame(height: min(176, max(116, viewportHeight * 0.2)))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(0.8)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
            }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
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
        }
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
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    background,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func compactMetricCard(
        title: String,
        detail: String? = nil,
        value: String,
        tint: Color = Color.white
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(panelBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private var panelBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.11),
                Color.white.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
