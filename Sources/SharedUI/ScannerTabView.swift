import SwiftUI
#if canImport(TimeThrottleCore)
import TimeThrottleCore
#endif

struct ScannerTabView: View {
    @ObservedObject var viewModel: ScannerViewModel
    var showsCloseButton = true

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ScannerTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        scannerHeader
                        scannerModePicker
                        scannerContent
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.loadSystemsIfNeeded()
        }
    }

    private var scannerHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "radio.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ScannerTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(ScannerTheme.panelRaised, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Public Scanner Listening")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(ScannerTheme.primaryText)

                    Text("Informational public feed audio, separate from Live Drive.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ScannerTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Coverage varies by scanner system. TimeThrottle does not record scanner audio.")
                .font(.caption.weight(.medium))
                .foregroundStyle(ScannerTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(ScannerTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ScannerTheme.border, lineWidth: 1)
        }
    }

    private var scannerModePicker: some View {
        Picker(
            "Scanner systems",
            selection: Binding(
                get: { viewModel.mode },
                set: { viewModel.setMode($0) }
            )
        ) {
            Text("Nearby").tag(ScannerSystemListMode.nearby)
            Text("Browse").tag(ScannerSystemListMode.browse)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var scannerContent: some View {
        if viewModel.isLoadingSystems && !viewModel.hasSystems {
            ScannerLoadingCard(title: "Loading scanner systems")
        } else if let message = viewModel.systemsErrorMessage, !viewModel.hasSystems {
            ScannerEmptyState(
                title: "Scanner systems unavailable",
                message: message,
                systemImage: "antenna.radiowaves.left.and.right.slash"
            ) {
                Button("Retry") {
                    Task { await viewModel.loadSystems() }
                }
            }
        } else {
            switch viewModel.mode {
            case .nearby:
                nearbySection
            case .browse:
                browseSection
            }
        }
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nearby Systems")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ScannerTheme.primaryText)

                    Text("Closest public scanner systems based on approximate system locations.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ScannerTheme.secondaryText)
                }

                Spacer(minLength: 8)

                Button {
                    Task { await viewModel.refreshNearby() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ScannerTheme.primaryText)
                        .frame(width: 34, height: 34)
                        .background(ScannerTheme.panelRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh nearby scanner systems")
            }

            if viewModel.isLoadingNearby {
                ScannerLoadingCard(title: "Finding nearby systems")
            } else if viewModel.nearbySystems.isEmpty {
                ScannerEmptyState(
                    title: "Browse scanner systems",
                    message: viewModel.nearbyMessage ?? "Nearby systems are unavailable right now.",
                    systemImage: "location.slash"
                ) {
                    Button("Browse systems") {
                        viewModel.setMode(.browse)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.nearbySystems) { system in
                        NavigationLink {
                            ScannerSystemDetailView(system: system, viewModel: viewModel)
                        } label: {
                            ScannerSystemRow(
                                system: system,
                                distance: viewModel.userCoordinate.flatMap { system.distanceMiles(from: $0) }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(ScannerTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ScannerTheme.border, lineWidth: 1)
        }
    }

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse Systems")
                .font(.headline.weight(.bold))
                .foregroundStyle(ScannerTheme.primaryText)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ScannerTheme.secondaryText)
                TextField(
                    "Search name, city, county, state",
                    text: $viewModel.searchText
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(ScannerTheme.primaryText)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(ScannerTheme.panelRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ScannerTheme.border, lineWidth: 1)
            }

            if viewModel.browseSystems.isEmpty {
                ScannerEmptyState(
                    title: viewModel.searchText.isEmpty ? "No active scanner systems" : "No matching scanner systems",
                    message: viewModel.searchText.isEmpty
                        ? "Active public scanner systems are unavailable from the provider right now."
                        : "Try a different system name, short name, city, county, or state.",
                    systemImage: "radio"
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.browseSystems) { system in
                        NavigationLink {
                            ScannerSystemDetailView(system: system, viewModel: viewModel)
                        } label: {
                            ScannerSystemRow(system: system, distance: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(ScannerTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ScannerTheme.border, lineWidth: 1)
        }
    }
}

private struct ScannerSystemDetailView: View {
    let system: ScannerSystem
    @ObservedObject var viewModel: ScannerViewModel

    var body: some View {
        ZStack {
            ScannerTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    systemHeader
                    ScannerLiveFeedCard(viewModel: viewModel)
                    latestCallsSection
                    scannerSafetyNote
                }
                .padding(16)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle(system.shortName.uppercased())
        .navigationBarTitleDisplayMode(.inline)
        .task(id: system.id) {
            await viewModel.selectSystem(system)
        }
    }

    private var systemHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "radio.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ScannerTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(ScannerTheme.panelRaised, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(system.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(ScannerTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(system.locationText.isEmpty ? system.shortName : system.locationText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ScannerTheme.secondaryText)
                }

                Spacer(minLength: 8)
                ScannerStatusBadge(system: system)
            }

            HStack(spacing: 8) {
                ScannerMiniStat(title: "System", value: system.shortName.uppercased())
                if let listenerCount = system.listenerCount ?? system.clientCount {
                    ScannerMiniStat(title: "Listeners", value: "\(listenerCount)")
                }
                if !viewModel.talkgroups.isEmpty {
                    ScannerMiniStat(title: "Talkgroups", value: "\(viewModel.talkgroups.count)")
                }
            }

            Button {
                Task { await viewModel.refreshSelectedSystem() }
            } label: {
                Label("Refresh latest calls", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ScannerTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(ScannerTheme.panelRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(ScannerTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ScannerTheme.border, lineWidth: 1)
        }
    }

    private var latestCallsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latest Calls")
                .font(.headline.weight(.bold))
                .foregroundStyle(ScannerTheme.primaryText)

            ScannerPlayerCard(viewModel: viewModel)

            if viewModel.isLoadingCalls {
                ScannerLoadingCard(title: "Loading latest calls")
            } else if let message = viewModel.callsErrorMessage {
                ScannerEmptyState(
                    title: viewModel.callsErrorTitle ?? "Latest calls unavailable",
                    message: message,
                    systemImage: "waveform.slash"
                )
            } else if viewModel.latestCalls.isEmpty {
                ScannerEmptyState(
                    title: viewModel.callsEmptyTitle,
                    message: viewModel.callsEmptyMessage,
                    systemImage: "waveform"
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.latestCalls) { call in
                        ScannerCallRow(
                            call: call,
                            isCurrent: viewModel.currentCall?.id == call.id,
                            isPlayable: viewModel.canPlay(call)
                        ) {
                            viewModel.play(call)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(ScannerTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ScannerTheme.border, lineWidth: 1)
        }
    }

    private var scannerSafetyNote: some View {
        Text("Scanner is listening only and independent from Live Drive. It does not create route warnings or driving recommendations.")
            .font(.caption.weight(.medium))
            .foregroundStyle(ScannerTheme.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ScannerLiveFeedCard: View {
    @ObservedObject var viewModel: ScannerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    viewModel.toggleLiveStreamPlayback()
                } label: {
                    Image(systemName: primaryIcon)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 44, height: 44)
                        .background(viewModel.canStartLiveFeed ? ScannerTheme.accent : ScannerTheme.panelRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canStartLiveFeed)
                .opacity(viewModel.canStartLiveFeed ? 1 : 0.45)
                .accessibilityLabel(viewModel.isLiveFeedPlaying ? "Pause Live Feed" : "Play Live Feed")

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.selectedLiveStream?.displayName.scannerViewNonEmpty ?? "Live Feed")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ScannerTheme.primaryText)
                        .lineLimit(1)

                    Text(providerText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ScannerTheme.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(viewModel.liveFeedStatusTitle)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.16), in: Capsule())
            }

            Text(viewModel.liveFeedStatusMessage)
                .font(.caption.weight(.medium))
                .foregroundStyle(statusMessageColor)
                .fixedSize(horizontal: false, vertical: true)

            Text("Live feed availability depends on configured public stream providers.")
                .font(.caption.weight(.medium))
                .foregroundStyle(ScannerTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(ScannerTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ScannerTheme.border, lineWidth: 1)
        }
    }

    private var primaryIcon: String {
        guard viewModel.playbackMode.liveStream != nil else { return "play.fill" }
        switch viewModel.playbackState {
        case .playing, .loading:
            return "pause.fill"
        case .paused, .stopped, .failed:
            return "play.fill"
        }
    }

    private var providerText: String {
        guard let stream = viewModel.selectedLiveStream else {
            return "Configured public stream required."
        }

        return [
            stream.providerLabel.scannerViewNonEmpty,
            stream.streamTypeText.scannerViewNonEmpty
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    private var statusColor: Color {
        switch viewModel.liveFeedStatusTitle {
        case "Playing":
            return ScannerTheme.accent
        case "Failed", "Unavailable":
            return ScannerTheme.warning
        default:
            return ScannerTheme.secondaryText
        }
    }

    private var statusMessageColor: Color {
        switch viewModel.liveFeedStatusTitle {
        case "Failed", "Unavailable":
            return ScannerTheme.warning
        default:
            return ScannerTheme.secondaryText
        }
    }
}

private struct ScannerPlayerCard: View {
    @ObservedObject var viewModel: ScannerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: primaryIcon)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 44, height: 44)
                        .background(ScannerTheme.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canStartPlayback)
                .opacity(viewModel.canStartPlayback ? 1 : 0.45)
                .accessibilityLabel(primaryAccessibilityLabel)

                VStack(alignment: .leading, spacing: 3) {
                    Text(playerTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(ScannerTheme.primaryText)
                        .lineLimit(1)

                    Text(playerDetail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ScannerTheme.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button {
                    viewModel.playNextCall()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ScannerTheme.primaryText)
                        .frame(width: 36, height: 36)
                        .background(ScannerTheme.panelRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!hasPlayableCalls)
                .opacity(hasPlayableCalls ? 1 : 0.45)
                .accessibilityLabel("Next scanner call")
            }

            if viewModel.playbackMode.callReplay != nil,
               case .failed(let message) = viewModel.playbackState {
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ScannerTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Playback can continue in the background after you start audio.")
                .font(.caption.weight(.medium))
                .foregroundStyle(ScannerTheme.tertiaryText)
        }
        .padding(14)
        .background(ScannerTheme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ScannerTheme.border, lineWidth: 1)
        }
    }

    private var primaryIcon: String {
        guard viewModel.playbackMode.callReplay != nil else { return "play.fill" }
        switch viewModel.playbackState {
        case .playing, .loading:
            return "pause.fill"
        case .paused, .stopped, .failed:
            return "play.fill"
        }
    }

    private var primaryAccessibilityLabel: String {
        viewModel.isCallReplayPlaying ? "Pause scanner audio" : "Play scanner audio"
    }

    private var playerTitle: String {
        guard let call = viewModel.currentCall else { return "Latest Calls player" }
        return call.displayTitle
    }

    private var playerDetail: String {
        guard let call = viewModel.currentCall else {
            if viewModel.latestCalls.contains(where: { viewModel.canPlay($0) }) {
                return "Press play to start the latest available call."
            }

            if viewModel.latestCalls.isEmpty {
                return viewModel.isLoadingCalls
                    ? "Latest calls are loading."
                    : "Latest calls will appear here when the provider responds."
            }

            return "Latest calls loaded, but no playable audio URL is available."
        }

        return [
            call.talkgroup.map { "Talkgroup \($0)" },
            ScannerFormatters.timestampText(call.timestamp)
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    private var hasPlayableCalls: Bool {
        viewModel.latestCalls.contains { viewModel.canPlay($0) }
    }
}

private struct ScannerSystemRow: View {
    let system: ScannerSystem
    let distance: Double?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.headline.weight(.bold))
                .foregroundStyle(ScannerTheme.accent)
                .frame(width: 38, height: 38)
                .background(ScannerTheme.panelRaised, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(system.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ScannerTheme.primaryText)
                        .lineLimit(1)

                    Text(system.shortName.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ScannerTheme.secondaryText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(ScannerTheme.panelRaised, in: Capsule())
                }

                Text(system.locationText.isEmpty ? "Location unavailable" : system.locationText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ScannerTheme.secondaryText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    ScannerStatusBadge(system: system)

                    if let distance {
                        Text(ScannerFormatters.distanceText(distance))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(ScannerTheme.primaryText)
                    }

                    if let listenerCount = system.listenerCount ?? system.clientCount {
                        Text("\(listenerCount) listening")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ScannerTheme.secondaryText)
                    }

                    if let lastActiveAt = system.lastActiveAt {
                        Text(ScannerFormatters.relativeTimeText(lastActiveAt))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ScannerTheme.tertiaryText)
                    }
                }
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(ScannerTheme.tertiaryText)
        }
        .padding(12)
        .background(ScannerTheme.panelRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ScannerTheme.border, lineWidth: 1)
        }
    }
}

private struct ScannerCallRow: View {
    let call: ScannerCall
    let isCurrent: Bool
    let isPlayable: Bool
    let playAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: playAction) {
                Image(systemName: isCurrent ? "speaker.wave.2.fill" : "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 34, height: 34)
                    .background(isCurrent ? ScannerTheme.accent : ScannerTheme.panelRaised, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isPlayable)
            .opacity(isPlayable ? 1 : 0.45)
            .accessibilityLabel(isPlayable ? "Play scanner call" : "Scanner call audio unavailable")

            VStack(alignment: .leading, spacing: 4) {
                Text(call.displayTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ScannerTheme.primaryText)
                    .lineLimit(1)

                Text(callSubtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ScannerTheme.secondaryText)
                    .lineLimit(2)

                if let metadata = call.metadataDisplayText {
                    Text(metadata)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(ScannerTheme.tertiaryText)
                        .lineLimit(2)
                }

                if !isPlayable {
                    Text("Audio URL unavailable")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(ScannerTheme.warning)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .background(ScannerTheme.panelRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isCurrent ? ScannerTheme.accent.opacity(0.45) : ScannerTheme.border, lineWidth: 1)
        }
    }

    private var callSubtitle: String {
        [
            call.talkgroup.map { "Talkgroup \($0)" },
            ScannerFormatters.timestampText(call.timestamp),
            ScannerFormatters.durationText(call.duration)
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }
}

private struct ScannerMiniStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(ScannerTheme.secondaryText)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(ScannerTheme.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(ScannerTheme.panelRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ScannerStatusBadge: View {
    let system: ScannerSystem

    var body: some View {
        Text(statusText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.16), in: Capsule())
    }

    private var statusText: String {
        guard system.isAvailable else { return "Unavailable" }
        return system.status?.trimmingCharacters(in: .whitespacesAndNewlines).scannerViewNonEmpty ?? "Active"
    }

    private var statusColor: Color {
        system.isAvailable ? ScannerTheme.accent : ScannerTheme.tertiaryText
    }
}

private extension String {
    var scannerViewNonEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct ScannerLoadingCard: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(ScannerTheme.accent)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ScannerTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ScannerTheme.panelRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ScannerEmptyState<ActionContent: View>: View {
    let title: String
    let message: String
    let systemImage: String
    let actionContent: ActionContent?

    init(
        title: String,
        message: String,
        systemImage: String,
        @ViewBuilder action: () -> ActionContent
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionContent = action()
    }

    init(title: String, message: String, systemImage: String) where ActionContent == EmptyView {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionContent = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(ScannerTheme.secondaryText)

            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(ScannerTheme.primaryText)

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ScannerTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let actionContent {
                actionContent
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ScannerTheme.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ScannerTheme.panelRaised, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ScannerTheme.panelRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private enum ScannerFormatters {
    static func timestampText(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func relativeTimeText(_ date: Date) -> String {
        timestampText(date) ?? "Recently active"
    }

    static func durationText(_ duration: TimeInterval?) -> String? {
        guard let duration else { return nil }
        let seconds = max(Int(duration.rounded()), 0)
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    static func distanceText(_ distance: Double) -> String {
        if distance < 10 {
            return "\(String(format: "%.1f", distance)) mi"
        }
        return "\(Int(distance.rounded())) mi"
    }
}

private enum ScannerTheme {
    static let background = Color(red: 0.05, green: 0.07, blue: 0.11)
    static let panel = Color(red: 0.11, green: 0.14, blue: 0.18)
    static let panelRaised = Color(red: 0.16, green: 0.19, blue: 0.24)
    static let border = Color.white.opacity(0.08)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color(red: 0.68, green: 0.73, blue: 0.79)
    static let tertiaryText = Color.white.opacity(0.56)
    static let accent = Palette.success
    static let warning = Color(red: 1.0, green: 0.75, blue: 0.35)
}
