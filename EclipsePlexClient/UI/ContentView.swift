import SwiftUI

/// Full-screen video playback driven by `PlaybackRequest` (Plex, local file, or bundled demo).
struct ContentView: View {
    var request: PlaybackRequest?
    var isCompactSession = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloadManager: OfflineDownloadManager
    @EnvironmentObject private var focusCoordinator: KeyboardFocusCoordinator
    @EnvironmentObject private var playbackPresenter: PlaybackPresenter

    @StateObject private var playerChrome = PlayerChromeController()
    @State private var activeRequest: PlaybackRequest?
    @State private var resolvedPlayback: ResolvedPlayback?
    @State private var loadError: String?
    @State private var loadingMessage = "Preparing playback…"

    init(request: PlaybackRequest? = nil, isCompactSession: Bool = false) {
        self.request = request
        self.isCompactSession = isCompactSession
        _activeRequest = State(initialValue: request)
    }

    private var playbackLoadTaskKey: String {
        guard let req = activeRequest ?? request else { return "none" }
        switch req {
        case .plex(let server, let ratingKey, _, _, _, _):
            return "plex|\(server.id.uuidString)|\(ratingKey)"
        case .downloadedPlexItem(let server, let ratingKey, _):
            return "offline|\(server.id.uuidString)|\(ratingKey)"
        case .remoteStream(let url):
            return "stream|\(url.absoluteString)"
        case .localFile(let url):
            return "file|\(url.absoluteString)"
        case .bundledDemo:
            return "bundledDemo"
        }
    }

    var body: some View {
        Group {
            if resolvedPlayback != nil {
                VideoPlaybackView(
                    request: activeRequest,
                    playback: Binding(
                        get: { resolvedPlayback! },
                        set: { resolvedPlayback = $0 }
                    ),
                    windowTitle: $playerChromeShowTitle,
                    chrome: playerChrome,
                    isCompactSession: isCompactSession,
                    onStop: { playbackPresenter.stop() },
                    onMinimize: { playbackPresenter.minimize() },
                    onAdvanceTo: { next in
                        activeRequest = next
                        resolvedPlayback = nil
                        playbackPresenter.setActivePlayback(nil)
                        playerChromeShowTitle = nil
                        playbackPresenter.replaceRequest(next)
                    }
                )
            } else if let loadError {
                errorView(message: loadError)
            } else {
                ProgressView(loadingMessage)
            }
        }
        .accessibilityIdentifier("playbackShell")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            guard !isCompactSession else { return }
            focusCoordinator.browseKeyboardCommandsEnabled = false
            // Defer so `.task` and focus routing don't fight in the same frame.
            DispatchQueue.main.async {
                focusCoordinator.route = .player
            }
        }
        .onDisappear {
            guard !isCompactSession else { return }
            focusCoordinator.browseKeyboardCommandsEnabled = true
        }
#if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
#endif
#if os(macOS)
        .toolbar(.hidden)
        .playbackSuppressesMacWindowTitle(!isCompactSession)
#endif
        .task(id: playbackLoadTaskKey) {
            guard playbackLoadTaskKey != "none" else { return }
            PlaybackScrobbleReporter.resetSession()
            await resolvePlaybackURL()
        }
    }

    private var playerWindowTitle: String {
        playerChromeShowTitle
            ?? activeRequest?.displayTitle
            ?? request?.displayTitle
            ?? "Playback"
    }

    @State private var playerChromeShowTitle: String?

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("Cannot Play", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
            Button("Exit", action: { playbackPresenter.stop() })
                .buttonStyle(.pressableBordered)
            if let req = activeRequest ?? request,
               case .plex(let server, _, _, _, _, _) = req,
               server.connectionCandidates.count > 1 {
                Button("Try another connection") {
                    NotificationCenter.default.post(
                        name: .eclipsePlexOpenConnectionPicker,
                        object: nil,
                        userInfo: ["serverId": server.id]
                    )
                }
                .buttonStyle(.pressableBordered)
            }
        }
    }

    @MainActor
    private func resolvePlaybackURL() async {
        loadError = nil

        let req = self.activeRequest ?? request ?? .bundledDemo

        if let cached = playbackPresenter.activePlayback, matchesRequest(req, cached) {
            resolvedPlayback = cached
            return
        }

        switch req {
        case .plex:
            loadingMessage = "Loading from Plex…"
        case .downloadedPlexItem:
            loadingMessage = "Opening offline file…"
        case .remoteStream:
            loadingMessage = "Opening stream…"
        case .localFile:
            loadingMessage = "Opening file…"
        case .bundledDemo:
            loadingMessage = "Preparing video…"
        }

        do {
            if case .plex = req {
                loadingMessage = "Reading Plex metadata…"
            }
            let resolved = try await ContentViewPlaybackLoader.resolvePlayback(
                request: req,
                downloadManager: downloadManager
            )
            guard !Task.isCancelled else { return }
            resolvedPlayback = resolved
            playbackPresenter.setActivePlayback(resolved)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            AppLog.playback("ContentView playback failed: \(error.localizedDescription)")
            loadError = PlaybackErrorMessages.friendly(error.localizedDescription)
            if case .plex(let server, _, _, _, _, _) = req, server.connectionCandidates.count > 1 {
                NotificationCenter.default.post(
                    name: .eclipsePlexOpenConnectionPicker,
                    object: nil,
                    userInfo: ["serverId": server.id]
                )
            }
        }
    }

    private func matchesRequest(_ request: PlaybackRequest, _ playback: ResolvedPlayback) -> Bool {
        guard let ctx = playback.resumeContext else { return false }
        switch request {
        case .plex(let server, let ratingKey, _, _, _, _):
            return ctx.serverId == server.id && ctx.ratingKey == ratingKey
        case .downloadedPlexItem(let server, let ratingKey, _):
            return ctx.serverId == server.id && ctx.ratingKey == ratingKey
        default:
            return false
        }
    }
}

// MARK: - Inline player

private struct VideoPlaybackView: View {
    let request: PlaybackRequest?
    @Binding var playback: ResolvedPlayback
    @Binding var windowTitle: String?
    @ObservedObject var chrome: PlayerChromeController
    var isCompactSession = false
    let onStop: () -> Void
    var onMinimize: (() -> Void)?
    var onAdvanceTo: (PlaybackRequest) -> Void = { _ in }

    @EnvironmentObject private var plexRegistry: PlexServerRegistry
    @EnvironmentObject private var playbackPresenter: PlaybackPresenter
    @EnvironmentObject private var downloadManager: OfflineDownloadManager
    @EnvironmentObject private var playbackQueue: PlaybackQueueManager
    @EnvironmentObject private var sleepTimer: SleepTimerController
    @State private var showResumeBanner = false
    @State private var skippedMarkerIDs: Set<String> = []
    @Environment(\.appThemePalette) private var themePalette
    @Environment(\.themeAccent) private var themeAccent
    @State private var nextEpisodeCandidate: PlexEpisodeSummary?
    @State private var previousEpisodeCandidate: PlexEpisodeSummary?
    @State private var nextEpisodeContext: EpisodePlayContext?
    @State private var playbackMarkers: [PlexPlaybackMarker] = []
    @State private var chromeEpisodeLine: String?
    @State private var isPlayNextOverlayVisible = false
    @State private var playNextCountdown = 15
    @State private var playNextCountdownTask: Task<Void, Never>?

    private var playNextTaskKey: String {
        guard case .plex(let server, let ratingKey, _, _, _, _) = request else { return "none" }
        return "\(server.id.uuidString)|\(ratingKey)"
    }

    #if os(macOS)
    private var vlcController: MacVLCPlaybackController { playbackPresenter.macController }
    #else
    private var vlcProxy: VLCVideoPlayer.Proxy { playbackPresenter.vlcProxy }
    @State private var positionMs = 0
    @State private var durationMs = 0
    @State private var isPlaying = false
    @State private var vlcSubtitleTracks: [MediaTrack] = []
    @State private var selectedSubtitleIndex = -1
    @State private var vlcAudioTracks: [MediaTrack] = []
    @State private var selectedAudioIndex = -1
    @State private var videoDisplaySize: CGSize = .zero
#endif

    @State private var statusText = "Opening…"
    @State private var playerErrorMessage: String?
    @State private var isReloadingStream = false
    @State private var didReportWatchState = false
    @State private var settingsPinReleaseTask: Task<Void, Never>?
    @State private var lastObservedPositionMs = 0
    @State private var lastPositionAdvancedAt: Date?

    private var canReloadStream: Bool {
        if case .plex = request { return true }
        return false
    }

    private var blocksAutoHide: Bool {
        isReloadingStream || playerErrorMessage != nil || shouldShowStatusOverlay
    }

    private var shouldShowStatusOverlay: Bool {
        if playbackProgressIsActive { return false }
        guard !statusText.isEmpty else { return false }
        let lower = statusText.lowercased()
        return lower.contains("opening") || lower.contains("buffering") || lower.contains("trying") || lower.contains("resuming")
    }

    /// Hides stale opening/buffering UI once time is clearly advancing.
    private var playbackProgressIsActive: Bool {
        #if os(macOS)
        if vlcController.isPlaying { return true }
        let position = vlcController.positionMs
        let duration = vlcController.durationMs
        #else
        if isPlaying { return true }
        let position = positionMs
        let duration = durationMs
        #endif
        if duration > 0, position >= 500 { return true }
        if let lastPositionAdvancedAt {
            return Date().timeIntervalSince(lastPositionAdvancedAt) < 3
        }
        return false
    }

    private func notePlaybackPositionAdvance(_ position: Int) {
        if position > lastObservedPositionMs + 150 {
            lastPositionAdvancedAt = Date()
        }
        lastObservedPositionMs = max(lastObservedPositionMs, position)
    }

    var body: some View {
        Group {
            if isCompactSession {
                playerLayer
            } else {
                fullPlaybackChrome
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color.black.ignoresSafeArea()
        }
        .onAppear {
            registerNowPlayingIfNeeded()
            startPeriodicScrobble()
            guard !isCompactSession else { return }
            if !playback.playbackMarkers.isEmpty {
                playbackMarkers = playback.playbackMarkers
            }
            if let resumeMs = playback.resumePositionMs, resumeMs > 5_000 {
                showResumeBanner = true
                Task {
                    try? await Task.sleep(for: .seconds(8))
                    showResumeBanner = false
                }
            }
            chrome.bumpActivity()
            if blocksAutoHide {
                chrome.setPinned(true)
            }
            #if os(macOS)
            vlcController.setSourceVideoSize(playback.sourceVideoSize)
            #endif
        }
#if os(macOS)
        .onChange(of: vlcController.positionTracker.positionMs) { _, position in
            if !isCompactSession {
                chrome.bumpActivity()
            }
            notePlaybackPositionAdvance(position)
            publishTransportState(positionMs: position, durationMs: vlcController.durationMs)
            autoSkipIntroIfNeeded(at: position)
        }
        .onReceive(NotificationCenter.default.publisher(for: .eclipsePlexToggleFullScreen)) { _ in
            vlcController.toggleWindowFullScreen()
        }
        .onChange(of: sleepTimer.remainingSeconds) { _, remaining in
            if remaining == 0, sleepTimer.mode != .none {
                vlcController.pause()
            }
        }
        .onChange(of: vlcController.isPlaying) { _, playing in
            publishTransportState(positionMs: vlcController.positionMs, durationMs: vlcController.durationMs, isPlaying: playing)
        }
#endif
        .onDisappear {
            guard !isCompactSession else { return }
            chrome.tearDown()
            PlaybackScrobbleReporter.stopPeriodicReporting()
            guard !didReportWatchState else { return }
            didReportWatchState = true
            let req = request
            let position = currentPositionMs()
            let duration = currentDurationMs()
            Task {
                await PlaybackScrobbleReporter.reportSessionEnd(
                    request: req,
                    positionMs: position,
                    durationMs: duration
                )
            }
        }
    }

    private var fullPlaybackChrome: some View {
        ZStack {
            brandedLoadingUnderlay
            playerLayer
                .ignoresSafeArea()
            if !chrome.isVisible {
                tapToToggleLayer
                    .ignoresSafeArea()
            }
            if chrome.isVisible {
                chromeOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(1)
            }
            blockingOverlays
            playNextOverlay
                .zIndex(20)
        }
        .onChange(of: isPlayNextOverlayVisible) { _, showing in
            chrome.setPinned(showing)
            if showing {
                chrome.bumpActivity()
            }
        }
        .task(id: playNextTaskKey) {
            // Let VLC attach before competing Plex metadata fetches.
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await refreshAdjacentEpisodeCandidates()
            guard !Task.isCancelled else { return }
            await loadPlaybackPresentationInfo()
        }
        .onChange(of: playback.playbackMarkers) { _, markers in
            guard !markers.isEmpty else { return }
            let duration = currentDurationMs()
            let merged = PlexPlaybackMarkerParser.merged(
                xml: markers,
                json: playbackMarkers,
                durationMs: duration > 0 ? duration : nil
            )
            guard merged != playbackMarkers else { return }
            playbackMarkers = merged
        }
        .onChange(of: blocksAutoHide) { _, blocks in
            chrome.setPinned(blocks)
            if !blocks {
                chrome.bumpActivity()
            }
        }
        #if os(macOS)
        .onContinuousHover { phase in
            if case .active = phase {
                chrome.bumpActivity()
            }
        }
        #endif
        .background {
            playbackKeyboardCaptureButtons
        }
    }

    private var brandedLoadingUnderlay: some View {
        let show = isReloadingStream || shouldShowStatusOverlay
        let gradientColors = themePalette?.playerGradient ?? [
            Color(red: 0.09, green: 0.10, blue: 0.18),
            Color(red: 0.15, green: 0.08, blue: 0.22),
            Color(red: 0.04, green: 0.06, blue: 0.14)
        ]
        let logoTint = themeAccent
        let (start, end) = themePalette?.playerGradientPoints ?? (.topLeading, .bottomTrailing)

        return ZStack {
            LinearGradient(
                colors: gradientColors,
                startPoint: start,
                endPoint: end
            )

            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220)
                .saturation(0)
                .colorMultiply(logoTint)
                .opacity(0.20)
                .blendMode(.screen)

        }
        .opacity(show ? 1 : 0.35)
        .animation(.easeInOut(duration: 0.25), value: show)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var playerLayer: some View {
        Group {
            #if os(macOS)
            MacVLCPlayerView(
                playback: playback,
                controller: vlcController,
                statusText: $statusText,
                errorMessage: $playerErrorMessage,
                onNaturalEnd: {
                    Task { await handleNaturalEnd() }
                }
            )
            #else
            IOSVLCPlayerView(
                playback: playback,
                proxy: vlcProxy,
                statusText: $statusText,
                errorMessage: $playerErrorMessage,
                onPositionUpdate: { position, duration in
                    notePlaybackPositionAdvance(position)
                    positionMs = position
                    durationMs = duration
                    publishTransportState(positionMs: position, durationMs: duration)
                },
                onPlaybackInfoUpdate: { info in
                    vlcSubtitleTracks = info.subtitleTracks
                    selectedSubtitleIndex = info.currentSubtitleTrack.index
                    vlcAudioTracks = info.audioTracks
                    selectedAudioIndex = info.currentAudioTrack.index
                    if info.videoSize.width > 0, info.videoSize.height > 0 {
                        videoDisplaySize = info.videoSize
                    }
                },
                onPlayerStateChange: { state in
                    isPlaying = state == .playing
                    publishTransportState(isPlaying: state == .playing)
                },
                onNaturalEnd: {
                    Task { await handleNaturalEnd() }
                }
            )
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tapToToggleLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                chrome.toggle()
            }
    }

    @ViewBuilder
    private var chromeOverlay: some View {
        if playbackMarkers.isEmpty {
            playerChromeOverlayContent
        } else {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                playerChromeOverlayContent
            }
        }
    }

    private var playerChromeOverlayContent: some View {
        PlayerChromeOverlay(
            title: playbackTitle,
            skipMarkerTitle: pendingSkipAction?.title,
            onSkipMarker: performPendingSkip,
            onExit: exitPlayback,
            onMinimize: onMinimize,
            onInteraction: { chrome.bumpActivity() },
            onBackgroundTap: { chrome.toggle() },
            topTrailing: {
                #if os(iOS) || os(tvOS)
                HStack(spacing: 8) {
                    PlaybackSettingsControls(
                        playback: playback,
                        canReloadStream: canReloadStream,
                        onSubtitleSelection: applySubtitleSelection,
                        onVideoResolution: applyVideoResolution,
                        onPlaybackSpeed: applyPlaybackSpeed,
                        onInteraction: { chrome.bumpActivity() },
                        onSettingsEngage: engageSettingsChrome
                    )
                }
                #else
                EmptyView()
                #endif
            },
            bottom: {
                platformTransportControls
            }
        )
    }

    @ViewBuilder
    private var playbackKeyboardCaptureButtons: some View {
#if os(iOS) || os(macOS)
        #if os(macOS)
        Button("", action: vlcController.togglePlayPause)
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
        #else
        Button("", action: togglePlayPause)
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
        #endif
        Button("", action: exitPlayback)
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
        if nextEpisodeCandidate != nil {
            Button("", action: playNextManually)
                .keyboardShortcut("n", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        if previousEpisodeCandidate != nil {
            Button("", action: playPreviousManually)
                .keyboardShortcut("p", modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        Button("", action: { seekBy(seconds: -10) })
            .keyboardShortcut(",", modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
        Button("", action: { seekBy(seconds: 10) })
            .keyboardShortcut(".", modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
#endif
    }

    @ViewBuilder
    private var platformTransportControls: some View {
        #if os(macOS)
            MacVLCPlaybackControls(
                controller: vlcController,
                playback: playback,
                canReloadStream: canReloadStream,
                onSubtitleSelection: applySubtitleSelection,
                onVideoResolution: applyVideoResolution,
                onPlaybackSpeed: applyPlaybackSpeed,
                nextEpisode: nextEpisodeCandidate,
                previousEpisode: previousEpisodeCandidate,
                onPlayNext: playNextManually,
                onPlayPrevious: playPreviousManually,
                onVLCSubtitleTrackSelected: { index in
                    vlcController.selectSubtitleTrack(index: index)
                },
                onVLCAudioTrackSelected: { index in
                    vlcController.selectAudioTrack(index: index)
                },
                onScrubbingChanged: { chrome.setPinned($0) },
                onInteraction: { chrome.bumpActivity() },
                onSettingsEngage: engageSettingsChrome,
                sleepTimer: sleepTimer
            )
        #elseif os(iOS) || os(tvOS)
        IOSVLCPlaybackControls(
            proxy: vlcProxy,
            positionMs: $positionMs,
            durationMs: durationMs,
            isPlaying: isPlaying,
            subtitleTracks: vlcSubtitleTracks,
            selectedSubtitleIndex: selectedSubtitleIndex,
            audioTracks: vlcAudioTracks,
            selectedAudioIndex: selectedAudioIndex,
            formattedResolution: formattedResolution,
            nextEpisode: nextEpisodeCandidate,
            onPlayNext: playNextManually,
            onPlayPause: {
                chrome.bumpActivity()
                togglePlayPause()
            },
            onSubtitleTrack: { index in
                chrome.bumpActivity()
                vlcProxy.setSubtitleTrack(.absolute(index))
                selectedSubtitleIndex = index
            },
            onAudioTrack: { index in
                chrome.bumpActivity()
                vlcProxy.setAudioTrack(.absolute(index))
                selectedAudioIndex = index
            },
            onScrubbingChanged: { chrome.setPinned($0) },
            onInteraction: { chrome.bumpActivity() }
        )
        #endif
    }

    @ViewBuilder
    private var blockingOverlays: some View {
        if showResumeBanner, let resumeMs = playback.resumePositionMs, resumeMs > 0 {
            HStack(spacing: 12) {
                Text("Resuming from \(MacVLCPlaybackController.format(ms: resumeMs))")
                    .font(.callout)
                Button("Start over") {
                    seekToMs(0)
                    showResumeBanner = false
                }
                .buttonStyle(.pressableBordered)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        if isReloadingStream {
            ProgressView("Updating stream…")
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        if !isReloadingStream, shouldShowStatusOverlay {
            ProgressView(statusText)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        if let playerErrorMessage {
            VStack(spacing: 12) {
                Text(playerErrorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Exit", action: exitPlayback)
                    .buttonStyle(.pressableBordered)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func engageSettingsChrome() {
        chrome.setPinned(true)
        chrome.bumpActivity()
        settingsPinReleaseTask?.cancel()
        settingsPinReleaseTask = Task {
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard !Task.isCancelled else { return }
            chrome.setPinned(false)
            chrome.bumpActivity()
        }
    }

    private func startPeriodicScrobble() {
        PlaybackScrobbleReporter.startPeriodicReporting(
            request: request,
            positionMs: { currentPositionMs() },
            durationMs: { currentDurationMs() }
        )
    }

    private func currentPositionMs() -> Int {
        #if os(macOS)
        vlcController.positionMs
        #else
        positionMs
        #endif
    }

    private func currentDurationMs() -> Int {
        #if os(macOS)
        vlcController.durationMs
        #else
        durationMs
        #endif
    }

    private func registerNowPlayingIfNeeded() {
        PlaybackNowPlayingController.shared.beginSession(
            title: request?.displayTitle,
            play: { [playbackPresenter] in playbackPresenter.togglePlayPause() },
            pause: { [playbackPresenter] in playbackPresenter.togglePlayPause() },
            toggle: { [playbackPresenter] in playbackPresenter.togglePlayPause() },
            skipForward: { [playbackPresenter] in playbackPresenter.seekBy(seconds: 15) },
            skipBackward: { [playbackPresenter] in playbackPresenter.seekBy(seconds: -15) }
        )
        publishTransportState()
    }

    private func publishTransportState(
        positionMs: Int? = nil,
        durationMs: Int? = nil,
        isPlaying: Bool? = nil
    ) {
        let position = positionMs ?? currentPositionMs()
        let duration = durationMs ?? currentDurationMs()
        #if os(macOS)
        playbackPresenter.updateTransport(
            title: playbackTitle ?? request?.displayTitle,
            positionMs: position,
            durationMs: duration,
            isPlaying: isPlaying ?? vlcController.isPlaying
        )
        #else
        playbackPresenter.updateTransport(
            title: playbackTitle ?? request?.displayTitle,
            positionMs: position,
            durationMs: duration,
            isPlaying: isPlaying ?? self.isPlaying
        )
        #endif
    }

    private func exitPlayback() {
        cancelPlayNextCountdown()
        isPlayNextOverlayVisible = false
        Task {
            await reportWatchStateToPlex()
            onStop()
        }
    }

    @ViewBuilder
    private var playNextOverlay: some View {
        if isPlayNextOverlayVisible, let next = nextEpisodeCandidate {
            VStack(spacing: 12) {
                Text("Up next")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(next.showTitle) · S\(next.seasonNumber)E\(next.episodeNumber)")
                    .font(.headline)
                Text(next.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Starting in \(playNextCountdown)s")
                    .font(.caption.monospacedDigit())
                HStack(spacing: 12) {
                    Button("Cancel") {
                        cancelPlayNextCountdown()
                        isPlayNextOverlayVisible = false
                    }
                    .buttonStyle(.pressableBordered)
                    Button("Play now") {
                        Task { await playNextManually() }
                    }
                    .buttonStyle(.pressableBorderedProminent)
                }
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding()
        }
    }

    @MainActor
    private func handleNaturalEnd() async {
        await reportWatchStateToPlex()
        if sleepTimer.shouldStopAfterEpisode {
            sleepTimer.cancel()
            exitPlayback()
            return
        }
        if let item = playbackQueue.advance(),
           let server = plexRegistry.allServers.first(where: { $0.id == item.serverId }) {
            cancelPlayNextCountdown()
            isPlayNextOverlayVisible = false
            onAdvanceTo(item.playbackRequest(server: server))
            return
        }
        await offerPlayNextIfNeeded()
    }

    private var playbackTitle: String? {
        chromeEpisodeLine ?? request?.displayTitle
    }

    private var pendingSkipAction: (title: String, endMs: Int)? {
        guard let marker = PlexPlaybackMarkerParser.activeMarker(
            at: currentPositionMs(),
            in: playbackMarkers
        ) else { return nil }
        return (markerButtonTitle(marker), marker.endMs)
    }

    private func performPendingSkip() {
        guard let pendingSkipAction else { return }
        chrome.bumpActivity()
        seekToMs(pendingSkipAction.endMs)
        if let showKey = episodeShowRatingKey,
           !SkipIntroPreferences.alwaysSkip(for: currentServerId, showRatingKey: showKey),
           !PlaybackPreferences.alwaysSkipIntros {
            AppToastCenter.show("Enable “Always skip intros” in Settings to auto-skip this show")
        }
    }

    private var currentServerId: UUID {
        guard case .plex(let server, _, _, _, _, _) = request else {
            return UUID()
        }
        return server.id
    }

    private var episodeShowRatingKey: String? {
        nextEpisodeContext?.showRatingKey
    }

    private func autoSkipIntroIfNeeded(at positionMs: Int) {
        guard PlaybackPreferences.alwaysSkipIntros || perShowSkipEnabled else { return }
        guard let marker = PlexPlaybackMarkerParser.activeMarker(at: positionMs, in: playbackMarkers),
              marker.type == .intro,
              marker.isSkippable(at: positionMs)
        else { return }
        let markerID = "\(marker.startMs)-\(marker.endMs)"
        guard !skippedMarkerIDs.contains(markerID) else { return }
        skippedMarkerIDs.insert(markerID)
        seekToMs(marker.endMs)
    }

    private var perShowSkipEnabled: Bool {
        guard let showKey = episodeShowRatingKey else { return false }
        return SkipIntroPreferences.alwaysSkip(for: currentServerId, showRatingKey: showKey)
    }

    private func markerButtonTitle(_ marker: PlexPlaybackMarker) -> String {
        switch marker.type {
        case .intro: "Skip intro"
        case .credits: "Skip credits"
        case .commercial: "Skip"
        case .unknown: "Skip"
        }
    }

    private func seekToMs(_ ms: Int) {
        #if os(macOS)
        vlcController.seek(toMs: ms)
        #else
        vlcProxy.setTime(.ticks(ms))
        #endif
    }

    private func seekBy(seconds: Int) {
        seekToMs(max(0, currentPositionMs() + seconds * 1000))
    }

    @MainActor
    private func loadPlaybackPresentationInfo() async {
        windowTitle = nil
        chromeEpisodeLine = nil
        guard case .plex(let server, let ratingKey, let fallbackTitle, let episodeContext, _, _) = request else {
            playbackMarkers = []
            windowTitle = request?.displayTitle
            chromeEpisodeLine = nil
            return
        }
        guard server.usesLivePlexAPI,
              let client = try? PlexMediaServerClient(server: server),
              let detail = try? await client.fetchMediaDetail(ratingKey: ratingKey)
        else {
            guard !Task.isCancelled else { return }
            playbackMarkers = playback.playbackMarkers
            windowTitle = fallbackTitle
            chromeEpisodeLine = nil
            return
        }
        guard !Task.isCancelled else { return }
        playbackMarkers = PlexPlaybackMarkerParser.merged(
            xml: playback.playbackMarkers,
            json: detail.markers,
            durationMs: detail.durationMs
        )
        let labels = await resolvePlaybackLabels(
            detail: detail,
            client: client,
            episodeContext: episodeContext,
            fallback: fallbackTitle
        )
        guard !Task.isCancelled else { return }
        windowTitle = labels.showTitle
        chromeEpisodeLine = labels.episodeLine
    }

    @MainActor
    private func resolvePlaybackLabels(
        detail: PlexMediaDetail,
        client: PlexMediaServerClient,
        episodeContext: EpisodePlayContext?,
        fallback: String?
    ) async -> (showTitle: String?, episodeLine: String?) {
        if case .episode(let episode) = detail.node {
            let showTitle = await resolveShowTitle(
                episode: episode,
                client: client,
                episodeContext: episodeContext
            )
            let episodeLine = episodeLineLabel(
                season: episode.seasonNumber,
                episode: episode.episodeNumber,
                title: episode.title
            )
            return (showTitle, episodeLine)
        }
        if case .movie = detail.node {
            return (detail.title, nil)
        }
        return (fallback ?? detail.title, nil)
    }

    @MainActor
    private func resolveShowTitle(
        episode: PlexEpisodeSummary,
        client: PlexMediaServerClient,
        episodeContext: EpisodePlayContext?
    ) async -> String? {
        if !episode.showTitle.isEmpty { return episode.showTitle }
        if let showKey = episode.showRatingKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !showKey.isEmpty,
           let showDetail = try? await client.fetchMediaDetail(ratingKey: showKey),
           !showDetail.title.isEmpty {
            return showDetail.title
        }
        if let episodeContext,
           let showDetail = try? await client.fetchMediaDetail(ratingKey: episodeContext.showRatingKey),
           !showDetail.title.isEmpty {
            return showDetail.title
        }
        return nil
    }

    private func episodeLineLabel(season: Int, episode: Int, title: String) -> String {
        let code = "S\(season) E\(episode)"
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? code : "\(code) · \(trimmed)"
    }

    @MainActor
    private func refreshAdjacentEpisodeCandidates() async {
        nextEpisodeCandidate = nil
        previousEpisodeCandidate = nil
        nextEpisodeContext = nil
        guard case .plex(let server, let ratingKey, _, let explicitContext, _, _) = request else { return }
        guard server.usesLivePlexAPI else { return }

        guard let (context, library) = await resolvePlayNextContext(
            server: server,
            episodeRatingKey: ratingKey,
            explicit: explicitContext
        ) else { return }
        guard !Task.isCancelled else { return }

        do {
            let client = try PlexMediaServerClient(server: server)
            async let next = client.fetchNextEpisode(
                library: library,
                showRatingKey: context.showRatingKey,
                episodeRatingKey: ratingKey
            )
            async let previous = client.fetchPreviousEpisode(
                library: library,
                showRatingKey: context.showRatingKey,
                episodeRatingKey: ratingKey
            )
            let nextEpisode = try await next
            let previousEpisode = try await previous
            guard !Task.isCancelled else { return }
            nextEpisodeCandidate = nextEpisode
            previousEpisodeCandidate = previousEpisode
            nextEpisodeContext = context
        } catch is CancellationError {
            return
        } catch {
            AppLog.playback("Adjacent episode prefetch failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func playPreviousManually() {
        guard let previous = previousEpisodeCandidate, let context = nextEpisodeContext else { return }
        chrome.bumpActivity()
        Task {
            await reportWatchStateToPlex()
            startPlayNextEpisode(previous, context: context)
        }
    }

    @MainActor
    private func offerPlayNextIfNeeded() async {
        guard !isPlayNextOverlayVisible else { return }
        guard nextEpisodeCandidate != nil else { return }
        isPlayNextOverlayVisible = true
        playNextCountdown = 15
        startPlayNextCountdown()
        if let next = nextEpisodeCandidate {
            AppLog.playbackDebug("Play next: S\(next.seasonNumber)E\(next.episodeNumber) — \(next.title)")
        }
    }

    @MainActor
    private func playNextManually() {
        guard let next = nextEpisodeCandidate, let context = nextEpisodeContext else { return }
        chrome.bumpActivity()
        Task {
            await reportWatchStateToPlex()
            startPlayNextEpisode(next, context: context)
        }
    }

    @MainActor
    private func resolvePlayNextContext(
        server: PlexServer,
        episodeRatingKey: String,
        explicit: EpisodePlayContext?
    ) async -> (EpisodePlayContext, PlexLibrary)? {
        let libraries = plexRegistry.librariesByServerID[server.id] ?? []

        if let explicit {
            if let library = libraries.first(where: { $0.matchesLibrarySectionID(explicit.librarySectionID) }) {
                return (explicit, library)
            }
            if let library = libraries.first(where: { $0.sectionType == .show }) {
                return (explicit, library)
            }
        }

        guard let client = try? PlexMediaServerClient(server: server),
              let detail = try? await client.fetchMediaDetail(ratingKey: episodeRatingKey),
              case .episode(let episode) = detail.node
        else { return nil }

        var showKey = episode.showRatingKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if showKey?.isEmpty != false {
            showKey = await resolveShowRatingKey(
                client: client,
                episodeParentRatingKey: episode.parentRatingKey,
                libraries: libraries
            )
        }
        guard let showKey, !showKey.isEmpty else { return nil }

        let library = libraries.first(where: { $0.sectionType == .show })
            ?? libraries.first
        guard let library else { return nil }

        let context = EpisodePlayContext(
            serverId: server.id,
            librarySectionID: library.sectionID,
            showRatingKey: showKey
        )
        return (context, library)
    }

    private func resolveShowRatingKey(
        client: PlexMediaServerClient,
        episodeParentRatingKey: String,
        libraries: [PlexLibrary]
    ) async -> String? {
        guard !episodeParentRatingKey.isEmpty else { return nil }
        guard let parentDetail = try? await client.fetchMediaDetail(ratingKey: episodeParentRatingKey) else {
            return nil
        }
        switch parentDetail.node {
        case .show(let show):
            return show.ratingKey
        case .season(let season):
            return season.parentRatingKey
        case .episode(let episode):
            return episode.showRatingKey
        default:
            return nil
        }
    }

    private func startPlayNextCountdown() {
        playNextCountdownTask?.cancel()
        playNextCountdownTask = Task { @MainActor in
            for remaining in stride(from: 15, through: 1, by: -1) {
                playNextCountdown = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            guard let next = nextEpisodeCandidate, let context = nextEpisodeContext else { return }
            startPlayNextEpisode(next, context: context)
        }
    }

    private func cancelPlayNextCountdown() {
        playNextCountdownTask?.cancel()
        playNextCountdownTask = nil
    }

    @MainActor
    private func startPlayNextEpisode(_ episode: PlexEpisodeSummary, context: EpisodePlayContext) {
        guard case .plex(let server, _, let title, _, _, _) = request else { return }
        cancelPlayNextCountdown()
        isPlayNextOverlayVisible = false
        nextEpisodeCandidate = nil
        nextEpisodeContext = nil
        didReportWatchState = false
        let showTitle = episode.showTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextRequest = PlaybackRequest.plex(
            server: server,
            ratingKey: episode.ratingKey,
            title: showTitle.isEmpty ? episodeChromeTitle(episode) : showTitle,
            episodeContext: context
        )
        onAdvanceTo(nextRequest)
    }

    private func episodeChromeTitle(_ episode: PlexEpisodeSummary) -> String {
        "S\(episode.seasonNumber)E\(episode.episodeNumber) · \(episode.title)"
    }

    private func applyPlaybackSpeed(_ rate: Float) {
        chrome.bumpActivity()
        #if os(macOS)
        vlcController.setPlaybackRate(rate)
        #else
        vlcProxy.setRate(.absolute(rate))
        #endif
    }

    @MainActor
    private func reportWatchStateToPlex() async {
        guard !didReportWatchState else { return }
        didReportWatchState = true
        #if os(macOS)
        let position = vlcController.positionMs
        let duration = vlcController.durationMs
        #else
        let position = positionMs
        let duration = durationMs
        #endif
        await PlaybackScrobbleReporter.reportSessionEnd(
            request: request,
            positionMs: position,
            durationMs: duration
        )
    }

    private var formattedResolution: String {
        #if os(macOS)
        vlcController.formattedVideoResolution
        #else
        if videoDisplaySize.width > 0, videoDisplaySize.height > 0 {
            return "\(Int(videoDisplaySize.width))×\(Int(videoDisplaySize.height))"
        }
        if let size = playback.sourceVideoSize, size.width > 0, size.height > 0 {
            return "\(Int(size.width))×\(Int(size.height))"
        }
        return playback.streamOptions.videoResolution.menuTitle
        #endif
    }

    private func applySubtitleSelection(_ selection: PlaybackSubtitleSelection) {
        PlaybackPreferences.saveSubtitleSelection(selection)
        var newOptions = playback.streamOptions
        newOptions.subtitleSelection = selection
        let needsPlexTranscode = newOptions.videoResolution.forcesTranscode
            || newOptions.subtitleSelection.requiresTranscodeBurnIn
        if canReloadStream && needsPlexTranscode {
            Task { await reloadStream(subtitle: selection, resolution: nil) }
            return
        }
        #if os(macOS)
        vlcController.applyPreferredSubtitle(from: selection)
        #else
        switch selection {
        case .off:
            vlcProxy.setSubtitleTrack(.absolute(-1))
        case .auto:
            if let first = vlcSubtitleTracks.first {
                vlcProxy.setSubtitleTrack(.absolute(first.index))
            }
        case .plexStream:
            if canReloadStream {
                Task { await reloadStream(subtitle: selection, resolution: nil) }
            }
        }
        #endif
    }

    private func applyVideoResolution(_ resolution: PlaybackVideoResolution) {
        PlaybackPreferences.saveVideoResolution(resolution)
        guard canReloadStream else { return }
        // Quality affects the transcode fallback URL; restart so the new profile is used if direct play fails.
        guard resolution != playback.streamOptions.videoResolution else { return }
        Task { await reloadStream(subtitle: nil, resolution: resolution) }
    }

    @MainActor
    private func reloadStream(
        subtitle: PlaybackSubtitleSelection?,
        resolution: PlaybackVideoResolution?
    ) async {
        guard let request else { return }
        isReloadingStream = true
        playerErrorMessage = nil
        defer { isReloadingStream = false }

        var options = PlaybackStreamOptions.current
        if let subtitle { options.subtitleSelection = subtitle }
        if let resolution { options.videoResolution = resolution }
        PlaybackPreferences.save(options)

        #if os(macOS)
        let resumeMs = vlcController.positionMs > 0 ? vlcController.positionMs : playback.resumePositionMs
        #else
        let resumeMs = positionMs > 0 ? positionMs : playback.resumePositionMs
        #endif

        do {
            var updated = try await PlaybackResolver.resolve(request, options: options)
            if let resumeMs, resumeMs > 0 {
                updated = updated.withResumePositionMs(resumeMs)
            }
            playback = updated
            statusText = "Opening…"
        } catch {
            playerErrorMessage = PlaybackErrorMessages.friendly(error.localizedDescription)
        }
    }

    #if !os(macOS)
    private func togglePlayPause() {
        if isPlaying {
            vlcProxy.pause()
        } else {
            vlcProxy.play()
        }
    }
    #endif
}

#if os(iOS) || os(tvOS)
private extension View {
    /// Minimum 48pt targets so transport buttons work above the home indicator.
    func playbackControlHitTarget() -> some View {
        frame(minWidth: 48, minHeight: 48)
            .contentShape(Rectangle())
    }
}

/// Transport bar for VLCUI on iOS (mirrors macOS controls).
private struct IOSVLCPlaybackControls: View {
    @ObservedObject var proxy: VLCVideoPlayer.Proxy
    @Binding var positionMs: Int
    let durationMs: Int
    let isPlaying: Bool
    let subtitleTracks: [MediaTrack]
    let selectedSubtitleIndex: Int
    let audioTracks: [MediaTrack]
    let selectedAudioIndex: Int
    let formattedResolution: String
    var nextEpisode: PlexEpisodeSummary? = nil
    var onPlayNext: (() -> Void)? = nil
    let onPlayPause: () -> Void
    let onSubtitleTrack: (Int) -> Void
    let onAudioTrack: (Int) -> Void
    var onScrubbingChanged: (Bool) -> Void = { _ in }
    var onInteraction: () -> Void = {}

    @State private var scrubberMs: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(format(ms: positionMs))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)

                #if os(tvOS)
                Text("\(format(ms: positionMs)) / \(format(ms: durationMs))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                #else
                Slider(
                    value: $scrubberMs,
                    in: 0 ... max(Double(durationMs), 1),
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        onScrubbingChanged(editing)
                        if !editing {
                            proxy.setTime(.ticks(Int(scrubberMs)))
                        }
                    }
                )
                .disabled(durationMs <= 0)
                #endif

                Text(format(ms: durationMs))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
            }

            HStack(spacing: 20) {
                Button {
                    onInteraction()
                    proxy.jumpBackward(10)
                } label: {
                    Image(systemName: "gobackward.10")
                }
                .playbackControlHitTarget()

                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .playbackControlHitTarget()
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                Button {
                    onInteraction()
                    proxy.jumpForward(10)
                } label: {
                    Image(systemName: "goforward.10")
                }
                .playbackControlHitTarget()

                if let next = nextEpisode, let onPlayNext {
                    Button {
                        onInteraction()
                        onPlayNext()
                    } label: {
                        Image(systemName: "forward.end.fill")
                    }
                    .accessibilityLabel("Next episode, season \(next.seasonNumber) episode \(next.episodeNumber)")
                }

                if !subtitleTracks.isEmpty {
                    Menu {
                        Button("Off") { onInteraction(); onSubtitleTrack(-1) }
                        ForEach(subtitleTracks, id: \.index) { track in
                            Button {
                                onInteraction()
                                onSubtitleTrack(track.index)
                            } label: {
                                HStack {
                                    Text(track.title)
                                    if selectedSubtitleIndex == track.index {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "text.bubble")
                    }
                }

                if audioTracks.count > 1 {
                    Menu {
                        ForEach(audioTracks, id: \.index) { track in
                            Button {
                                onInteraction()
                                onAudioTrack(track.index)
                            } label: {
                                HStack {
                                    Text(track.title)
                                    if selectedAudioIndex == track.index {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "waveform")
                    }
                }

                Text(formattedResolution)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .labelStyle(.iconOnly)
        }
        .onChange(of: positionMs) { _, position in
            if !isScrubbing {
                scrubberMs = Double(position)
            }
        }
        .onAppear {
            scrubberMs = Double(positionMs)
        }
    }

    private func format(ms: Int) -> String {
        guard ms > 0 else { return "0:00" }
        let s = ms / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
#endif

#if !os(macOS)
private extension VLCVideoPlayer.State {
    var label: String {
        switch self {
        case .opening: "Opening…"
        case .buffering: "Buffering…"
        case .playing: "Playing"
        case .paused: "Paused"
        case .stopped: "Stopped"
        case .ended: "Ended"
        case .error: "Error"
        case .esAdded: "Ready"
        }
    }
}
#endif

#Preview {
    NavigationStack {
    ContentView()
        .environmentObject(KeyboardFocusCoordinator())
    }
    .environmentObject(OfflineDownloadManager())
}
