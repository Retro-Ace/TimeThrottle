import SwiftUI

struct TripHistoryScreen: View {
    @ObservedObject var store: TripHistoryStore
    let brandLogo: Image?

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
                                TripHistoryDetailView(trip: trip, brandLogo: brandLogo)
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
                    .background(Palette.workspace)
                }
            }
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .background(Palette.workspace)
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
                    .foregroundStyle(Palette.ink)

                Text("Completed Live Drive trips will appear here with target-pace gain/loss and Apple ETA results.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.cocoa)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Palette.workspace)
    }
}

private struct TripHistoryRow: View {
    let trip: CompletedTripRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.displayRouteTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Palette.ink)

                Text(trip.completedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.cocoa)
            }

            HStack(spacing: 8) {
                StatPill(title: "Target gain", value: durationString(trip.timeSavedBySpeeding), foreground: Palette.success, background: Palette.successBackground, compact: true)
                StatPill(title: "Target loss", value: durationString(trip.timeLostBelowTargetPace), foreground: Palette.danger, background: Palette.dangerBackground, compact: true)
                StatPill(title: "Vs ETA", value: netString(trip.netTimeGain), foreground: trip.netTimeGain >= 0 ? Palette.success : Palette.danger, background: Palette.pill, compact: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.surfaceBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
    }
}

private struct TripHistoryDetailView: View {
    let trip: CompletedTripRecord
    let brandLogo: Image?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                detailHero

                SectionCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Trip summary")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Palette.ink)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 12
                        ) {
                            SummaryCard(title: "Above-target gain", value: durationString(trip.timeSavedBySpeeding), tint: Palette.success, compact: true)
                            SummaryCard(title: "Below-target loss", value: durationString(trip.timeLostBelowTargetPace), tint: Palette.danger, compact: true)
                            SummaryCard(title: "Overall vs Apple ETA", value: netString(trip.netTimeGain), tint: trip.netTimeGain >= 0 ? Palette.success : Palette.danger, isProminent: true, compact: true)
                        }

                        Text("Overall vs Apple ETA compares the whole trip to Apple Maps. Above-target gain and below-target loss are measured against your chosen target pace.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.cocoa)
                    }
                }

                SectionCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Drive details")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Palette.ink)

                        DetailRow(title: "Elapsed drive time", subtitle: trip.completedAt.formatted(date: .abbreviated, time: .shortened), value: durationString(trip.elapsedDriveMinutes), tint: Palette.ink, compact: true)
                        DetailRow(title: "Distance driven", subtitle: "Measured during Live Drive", value: "\(milesString(trip.distanceDrivenMiles)) mi", tint: Palette.ink, compact: true)
                        DetailRow(title: "Average trip speed", subtitle: "Whole-drive pace", value: "\(speedString(trip.averageTripSpeed)) mph", tint: Palette.ink, compact: true)
                        DetailRow(title: "Target speed", subtitle: "Chosen before the drive started", value: "\(speedString(trip.targetSpeed)) mph", tint: Palette.ink, compact: true)
                    }
                }

                Text("Always obey traffic laws and road conditions.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.cocoa)
                    .padding(.horizontal, 6)
            }
            .padding(Layout.screenPadding)
        }
        .background(Palette.workspace.ignoresSafeArea())
        .navigationTitle("Trip Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detailHero: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    if let brandLogo {
                        brandLogo
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 80, height: 52)
                    } else {
                        Image(systemName: "gauge.with.needle")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Palette.success)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(trip.displayRouteTitle)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Palette.ink)

                        Text(trip.routeLabel)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.cocoa)
                    }
                }
            }
        }
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

    return minutes > 0 ? "\(durationString(minutes)) saved" : "\(durationString(abs(minutes))) lost"
}

private func milesString(_ miles: Double) -> String {
    String(format: "%.1f", miles)
}

private func speedString(_ speed: Double) -> String {
    String(format: "%.0f", speed)
}
