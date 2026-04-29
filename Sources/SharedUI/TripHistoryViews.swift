import SwiftUI

private let tripHistoryBackgroundTop = Color(red: 0.05, green: 0.07, blue: 0.11)
private let tripHistoryBackgroundBottom = Color(red: 0.09, green: 0.12, blue: 0.18)
private let tripHistoryPanel = Color(red: 0.11, green: 0.14, blue: 0.18)
private let tripHistoryPanelRaised = Color(red: 0.14, green: 0.17, blue: 0.22)
private let tripHistoryPanelMuted = Color(red: 0.16, green: 0.19, blue: 0.24)
private let tripHistoryBorder = Color.white.opacity(0.08)
private let tripHistoryPrimaryText = Color.white.opacity(0.94)
private let tripHistorySecondaryText = Color(red: 0.68, green: 0.73, blue: 0.79)
private let tripHistoryTertiaryText = Color.white.opacity(0.58)
private let tripHistoryShadow = Color.black.opacity(0.28)

struct TripHistoryScreen: View {
    @ObservedObject var store: TripHistoryStore
    let brandLogo: Image?
    let resultBrandLogo: Image?
    var showsCloseButton = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.trips.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.trips) { trip in
                            NavigationLink {
                                TripHistoryDetailView(trip: trip, resultBrandLogo: resultBrandLogo)
                            } label: {
                                TripHistoryRow(trip: trip)
                                    .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .onDelete { offsets in
                            store.deleteTrips(at: offsets)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .background(
                LinearGradient(
                    colors: [tripHistoryBackgroundTop, tripHistoryBackgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "car.rear.road.lane.dashed")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(Palette.success)

            VStack(spacing: 6) {
                Text("No trips saved yet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tripHistoryPrimaryText)

                Text("Completed Live Drive trips will appear here with speed-limit analysis and Apple ETA results.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tripHistorySecondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(
            LinearGradient(
                colors: [tripHistoryBackgroundTop, tripHistoryBackgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct TripHistoryRow: View {
    let trip: CompletedTripRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.displayRouteTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tripHistoryPrimaryText)

                Text(trip.completedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(tripHistorySecondaryText)
            }

            HStack(spacing: 8) {
                StatPill(title: "Above Limit", value: speedLimitMetricString(trip.timeSavedBySpeeding, measuredMinutes: trip.speedLimitMeasuredMinutes), foreground: Palette.success, background: tripHistoryPanelMuted, compact: true, titleColor: tripHistorySecondaryText, borderColor: tripHistoryBorder)
                StatPill(title: "Below Limit", value: speedLimitMetricString(trip.timeLostBelowTargetPace, measuredMinutes: trip.speedLimitMeasuredMinutes), foreground: Palette.danger, background: tripHistoryPanelMuted, compact: true, titleColor: tripHistorySecondaryText, borderColor: tripHistoryBorder)
                if trip.hasRouteBaseline {
                    StatPill(title: "Vs ETA", value: netString(trip.netTimeGain), foreground: trip.netTimeGain >= 0 ? Palette.success : Palette.danger, background: tripHistoryPanelMuted, compact: true, titleColor: tripHistorySecondaryText, borderColor: tripHistoryBorder)
                }
            }

            HStack(spacing: 8) {
                StatPill(title: "Top", value: topSpeedString(trip.topSpeedMPH), foreground: tripHistoryPrimaryText, background: tripHistoryPanelMuted, compact: true, titleColor: tripHistorySecondaryText, borderColor: tripHistoryBorder)
                StatPill(title: "Distance", value: "\(milesString(trip.distanceDrivenMiles)) mi", foreground: tripHistoryPrimaryText, background: tripHistoryPanelMuted, compact: true, titleColor: tripHistorySecondaryText, borderColor: tripHistoryBorder)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tripHistoryPanel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tripHistoryBorder, lineWidth: 1)
        }
        .shadow(color: tripHistoryShadow, radius: 18, y: 8)
    }
}

private struct TripHistoryDetailView: View {
    let trip: CompletedTripRecord
    let resultBrandLogo: Image?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                SectionCard(
                    background: tripHistoryPanel,
                    border: tripHistoryBorder,
                    shadowColor: tripHistoryShadow,
                    shadowRadius: 24,
                    shadowYOffset: 10
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 14) {
                            if let resultBrandLogo {
                                resultBrandLogo
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .frame(width: 70, height: 70)
                            } else {
                                Image(systemName: "gauge.with.needle")
                                    .font(.system(size: 34, weight: .semibold))
                                    .foregroundStyle(Palette.success)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(trip.displayRouteTitle)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(tripHistoryPrimaryText)

                                Text(trip.routeLabel)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(tripHistorySecondaryText)

                                Text(trip.completedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(tripHistorySecondaryText)
                            }
                        }

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 12
                        ) {
                            if trip.hasRouteBaseline {
                                SummaryCard(title: "Time Above Speed Limit", value: speedLimitMetricString(trip.timeSavedBySpeeding, measuredMinutes: trip.speedLimitMeasuredMinutes), tint: Palette.success, compact: true, titleColor: tripHistorySecondaryText, backgroundColor: tripHistoryPanelMuted, borderColor: tripHistoryBorder, shadowColor: tripHistoryShadow.opacity(0.65))
                                SummaryCard(title: "Time Below Speed Limit", value: speedLimitMetricString(trip.timeLostBelowTargetPace, measuredMinutes: trip.speedLimitMeasuredMinutes), tint: Palette.danger, compact: true, titleColor: tripHistorySecondaryText, backgroundColor: tripHistoryPanelMuted, borderColor: tripHistoryBorder, shadowColor: tripHistoryShadow.opacity(0.65))
                                SummaryCard(title: "Overall vs Apple ETA", value: netString(trip.netTimeGain), tint: trip.netTimeGain >= 0 ? Palette.success : Palette.danger, isProminent: true, compact: true, titleColor: tripHistorySecondaryText, backgroundColor: tripHistoryPanelMuted, borderColor: trip.netTimeGain >= 0 ? Palette.success.opacity(0.32) : Palette.danger.opacity(0.28), shadowColor: tripHistoryShadow.opacity(0.65))
                            }
                            SummaryCard(title: "Elapsed drive time", value: durationString(trip.elapsedDriveMinutes), tint: tripHistoryPrimaryText, compact: true, titleColor: tripHistorySecondaryText, backgroundColor: tripHistoryPanelMuted, borderColor: tripHistoryBorder, shadowColor: tripHistoryShadow.opacity(0.65))
                            SummaryCard(title: "Distance driven", value: "\(milesString(trip.distanceDrivenMiles)) mi", tint: tripHistoryPrimaryText, compact: true, titleColor: tripHistorySecondaryText, backgroundColor: tripHistoryPanelMuted, borderColor: tripHistoryBorder, shadowColor: tripHistoryShadow.opacity(0.65))
                            SummaryCard(title: "Average trip speed", value: "\(speedString(trip.averageTripSpeed)) mph", tint: tripHistoryPrimaryText, compact: true, titleColor: tripHistorySecondaryText, backgroundColor: tripHistoryPanelMuted, borderColor: tripHistoryBorder, shadowColor: tripHistoryShadow.opacity(0.65))
                            SummaryCard(title: "Top speed", value: topSpeedString(trip.topSpeedMPH), tint: tripHistoryPrimaryText, compact: true, titleColor: tripHistorySecondaryText, backgroundColor: tripHistoryPanelMuted, borderColor: tripHistoryBorder, shadowColor: tripHistoryShadow.opacity(0.65))
                            if !trip.hasRouteBaseline {
                                SummaryCard(title: "Time Above Speed Limit", value: speedLimitMetricString(trip.timeSavedBySpeeding, measuredMinutes: trip.speedLimitMeasuredMinutes), tint: Palette.success, compact: true, titleColor: tripHistorySecondaryText, backgroundColor: tripHistoryPanelMuted, borderColor: tripHistoryBorder, shadowColor: tripHistoryShadow.opacity(0.65))
                                SummaryCard(title: "Time Below Speed Limit", value: speedLimitMetricString(trip.timeLostBelowTargetPace, measuredMinutes: trip.speedLimitMeasuredMinutes), tint: Palette.danger, compact: true, titleColor: tripHistorySecondaryText, backgroundColor: tripHistoryPanelMuted, borderColor: tripHistoryBorder, shadowColor: tripHistoryShadow.opacity(0.65))
                            }
                        }

                        Text(trip.hasRouteBaseline ? "Overall vs Apple ETA compares the whole trip to Apple Maps. Time Above Speed Limit and Time Below Speed Limit are measured against available OpenStreetMap speed-limit estimates." : "Free Drive trips save distance, elapsed time, speed, and speed-limit time above/below where available. No Apple Maps ETA comparison is created without a route.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(tripHistorySecondaryText)
                    }
                }

                Text("Always obey traffic laws and road conditions.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(tripHistorySecondaryText)
                    .padding(.horizontal, 6)
            }
            .padding(Layout.screenPadding)
        }
        .background(
            LinearGradient(
                colors: [tripHistoryBackgroundTop, tripHistoryBackgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Trip Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

}

private func durationString(_ minutes: Double) -> String {
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

private func netString(_ minutes: Double) -> String {
    if abs(minutes) < 0.01 {
        return "Even"
    }

    return minutes > 0 ? "\(durationString(minutes)) ahead" : "\(durationString(abs(minutes))) behind"
}

private func speedLimitMetricString(_ minutes: Double, measuredMinutes: Double) -> String {
    measuredMinutes > 0 ? durationString(minutes) : "—"
}

private func milesString(_ miles: Double) -> String {
    String(format: "%.1f", miles)
}

private func speedString(_ speed: Double) -> String {
    String(format: "%.0f", speed)
}

private func topSpeedString(_ speed: Double?) -> String {
    guard let speed, speed > 0 else { return "—" }
    return "\(speedString(speed)) mph"
}
