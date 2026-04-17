import SwiftUI

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

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        topBar
                        routeCard
                        primaryCardSection
                        middleMetricRow
                        controlsSection
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 3)

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

    private var heroSpeedCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Text("Current speed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.66))

                Spacer(minLength: 6)

                avgSpeedChip
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(currentSpeedValue)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text("mph")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: topSectionHeight, maxHeight: topSectionHeight, alignment: .leading)
        .background(hudCardFill(cornerRadius: 20))
        .overlay(hudCardBorder(cornerRadius: 20, color: Palette.success.opacity(0.26), lineWidth: 1.2))
    }

    private var avgSpeedChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.caption.weight(.semibold))

            Text("Avg \(averageSpeedValue)")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.white.opacity(0.68))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    private var primaryCardSection: some View {
        HStack(alignment: .top, spacing: 4) {
            heroSpeedCard

            infoStackPanel
                .frame(maxWidth: .infinity, minHeight: topSectionHeight, maxHeight: topSectionHeight)
        }
    }

    private var infoStackPanel: some View {
        VStack(spacing: 3) {
            infoStackItem(
                title: "ETA",
                value: appleETAValue,
                detail: "Apple baseline"
            )

            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)

            infoStackItem(
                title: "ARRIVE",
                value: liveETAValue,
                detail: liveETADetail
            )
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
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(1)

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(detail)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.36))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var middleMetricRow: some View {
        HStack(spacing: 4) {
            compactMetricCard(
                title: "Time Saved",
                value: aboveTargetValue,
                tint: Palette.success,
                minHeight: 56,
                valueSize: 20
            )

            compactMetricCard(
                title: "Time Lost",
                value: belowTargetValue,
                tint: Palette.danger,
                minHeight: 56,
                valueSize: 20
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
                minHeight: max(330, viewportHeight * 0.50),
                idealHeight: viewportHeight * 0.58,
                maxHeight: .infinity,
                alignment: .bottom
            )
            .padding(.top, 2)
            .padding(.bottom, -bottomInset)
            .ignoresSafeArea(edges: .bottom)
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
        verticalPadding: CGFloat = 7,
        expandToFill: Bool = false,
        contentSpacing: CGFloat = 2,
        detailSize: CGFloat = 11,
        fixedHeight: CGFloat? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(1)
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
        136
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
