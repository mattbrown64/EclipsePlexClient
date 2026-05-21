import SwiftUI

/// Full-screen video playback driven by `PlaybackRequest` (Plex, local file, or bundled demo).
struct ContentView: View {
    var request: PlaybackRequest?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloadManager: OfflineDownloadManager

    @StateObject private var playerChrome = PlayerChromeController()
    @State private var activeRequest: PlaybackRequest?
    @State private var resolvedPlayback: ResolvedPlayback?
    @State private var loadError: String?
    @State private var loadingMessage = "Preparing playback…"

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
                    onDone: { dismiss() },
                    onAdvanceTo: { next in
                        activeRequest = next
                        resolvedPlayback = nil
                        playerChromeShowTitle = nil
                        Task { await resolvePlaybackURL() }
                    }
                )
            } else if let loadError {
                errorView(message: loadError)
            } else {
                ProgressView(loadingMessage)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .navigationBarBackButtonHidden(true)
        .navigationTitle(playerWindowTitle)
        .onAppear {
            if activeRequest == nil {
                activeRequest = request
            }
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(playerChrome.isVisible ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(playerChrome.isVisible ? .automatic : .hidden, for: .navigationBar)
        .persistentSystemOverlays(playerChrome.isVisible ? .automatic : .hidden)
#endif
        .task(id: activeRequest) {
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
            Button("Exit", action: { dismiss() })
                .buttonStyle(.bordered)
        }
    }

    @MainActor
    private func resolvePlaybackURL() async {
        loadError = nil
        resolvedPlayback = nil

        let req = self.activeRequest ?? request ?? .bundledDemo

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

        NSLog("[EclipsePlex] ContentView preparing playback…")
        do {
            if case .plex = req {
                loadingMessage = "Reading Plex metadata…"
            }
            let offlineFileURL = resolveOfflineFileURL(for: req)
            resolvedPlayback = try await PlaybackResolver.resolve(
                req,
                offlineFileURL: offlineFileURL
            )
            NSLog("[EclipsePlex] ContentView playback URL ready")
        } catch {
            NSLog("[EclipsePlex] ContentView playback failed: %@", error.localizedDescription)
            loadError = PlaybackErrorMessages.friendly(error.localizedDescription)
        }
    }

    /// Look up the download on disk when playback starts (not when the navigation link was created).
    private func resolveOfflineFileURL(for request: PlaybackRequest) -> URL? {
        guard case .downloadedPlexItem(let server, let ratingKey, _) = request else {
            return nil
        }
        guard let record = downloadManager.playableRecord(serverId: server.id, ratingKey: ratingKey),
              let url = downloadManager.localFileURL(for: record)
        else {
            NSLog(
                "[EclipsePlex] Offline file missing for server=%@ ratingKey=%@",
                server.id.uuidString,
                ratingKey
            )
            return nil
        }
        return url
    }
}

// MARK: - Inline player

private struct VideoPlaybackView: View {
    let request: PlaybackRequest?
    @Binding var playback: ResolvedPlayback
    @Binding var windowTitle: String?
    @ObservedObject var chrome: PlayerChromeController
    let onDone: () -> Void
    var onAdvanceTo: (PlaybackRequest) -> Void = { _ in }

    @EnvironmentObject private var plexRegistry: PlexServerRegistry
    @State private var nextEpisodeCandidate: PlexEpisodeSummary?
    @State private var previousEpisodeCandidate: PlexEpisodeSummary?
    @State private var nextEpisodeContext: EpisodePlayContext?
    @State private var playbackMarkers: [PlexPlaybackMarker] = []
    @State private var chromeEpisodeLine: String?
    @State private var isPlayNextOverlayVisible = false
    @State private var playNextCountdown = 15
    @State private var playNextCountdownTask: Task<Void, Never>?

    private var playNextTaskKey: String {
        guard case .plex(let server, let ratingKey, _, _) = request else { return "none" }
        return "\(server.id.uuidString)|\(ratingKey)"
    }

    #if os(macOS)
    @StateObject private var vlcController = MacVLCPlaybackController()
    #else
    @StateObject private var vlcProxy = VLCVideoPlayer.Proxy()
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

    private var canReloadStream: Bool {
        if case .plex = request { return true }
        return false
    }

    private var blocksAutoHide: Bool {
        isReloadingStream || playerErrorMessage != nil
    }

    var body: some View {
        ZStack {
            playerLayer
            tapToToggleLayer
            if chrome.isVisible {
                chromeOverlay
            }
            blockingOverlays
            playNextOverlay
                .zIndex(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .onChange(of: isPlayNextOverlayVisible) { _, showing in
            chrome.setPinned(showing)
            if showing {
                chrome.bumpActivity()
            }
        }
        .task(id: playNextTaskKey) {
            await refreshAdjacentEpisodeCandidates()
            await loadPlaybackPresentationInfo()
        }
        .onChange(of: playback.playbackMarkers) { _, markers in
            guard !markers.isEmpty else { return }
            playbackMarkers = PlexPlaybackMarkerParser.merged(
                xml: markers,
                json: playbackMarkers,
                durationMs: currentDurationMs() > 0 ? currentDurationMs() : nil
            )
        }
        .onAppear {
            if !playback.playbackMarkers.isEmpty {
                playbackMarkers = playback.playbackMarkers
            }
            chrome.bumpActivity()
            if blocksAutoHide {
                chrome.setPinned(true)
            }
            #if os(macOS)
            vlcController.setSourceVideoSize(playback.sourceVideoSize)
            #endif
            startPeriodicScrobble()
        }
#if os(macOS)
        .onChange(of: vlcController.positionMs) { _, _ in
            chrome.bumpActivity()
        }
#endif
        .onDisappear {
            chrome.tearDown()
            PlaybackScrobbleReporter.stopPeriodicReporting()
            Task { await reportWatchStateToPlex() }
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
        .background {
            Button("", action: vlcController.togglePlayPause)
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
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
        }
        #endif
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
                    positionMs = position
                    durationMs = duration
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
            onInteraction: { chrome.bumpActivity() },
            topTrailing: {
                #if os(iOS)
                PlaybackSettingsControls(
                    playback: playback,
                    canReloadStream: canReloadStream,
                    onSubtitleSelection: applySubtitleSelection,
                    onVideoResolution: applyVideoResolution,
                    onPlaybackSpeed: applyPlaybackSpeed,
                    onInteraction: { chrome.bumpActivity() },
                    onSettingsEngage: engageSettingsChrome
                )
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
                onSettingsEngage: engageSettingsChrome
            )
        #else
        IOSVLCPlaybackControls(
            proxy: vlcProxy,
            positionMs: $positionMs,
            durationMs: durationMs,
            isPlaying: isPlaying,
            nextEpisode: nextEpisodeCandidate,
            onPlayNext: playNextManually,
            subtitleTracks: vlcSubtitleTracks,
            selectedSubtitleIndex: selectedSubtitleIndex,
            audioTracks: vlcAudioTracks,
            selectedAudioIndex: selectedAudioIndex,
            formattedResolution: formattedResolution,
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
        if isReloadingStream {
            ProgressView("Updating stream…")
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
                    .buttonStyle(.bordered)
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

    private func exitPlayback() {
        cancelPlayNextCountdown()
        isPlayNextOverlayVisible = false
        Task {
            await reportWatchStateToPlex()
            onDone()
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
                    .buttonStyle(.bordered)
                    Button("Play now") {
                        Task { await playNextManually() }
                    }
                    .buttonStyle(.borderedProminent)
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
        vlcProxy.setTime(.absolute(ms))
        #endif
    }

    private func seekBy(seconds: Int) {
        seekToMs(max(0, currentPositionMs() + seconds * 1000))
    }

    @MainActor
    private func loadPlaybackPresentationInfo() async {
        windowTitle = nil
        chromeEpisodeLine = nil
        guard case .plex(let server, let ratingKey, let fallbackTitle, let episodeContext) = request else {
            playbackMarkers = []
            windowTitle = request?.displayTitle
            chromeEpisodeLine = nil
            return
        }
        guard server.usesLivePlexAPI,
              let client = try? PlexMediaServerClient(server: server),
              let detail = try? await client.fetchMediaDetail(ratingKey: ratingKey)
        else {
            playbackMarkers = playback.playbackMarkers
            windowTitle = fallbackTitle
            chromeEpisodeLine = nil
            return
        }
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
        guard case .plex(let server, let ratingKey, _, let explicitContext) = request else { return }
        guard server.usesLivePlexAPI else { return }

        guard let (context, library) = await resolvePlayNextContext(
            server: server,
            episodeRatingKey: ratingKey,
            explicit: explicitContext
        ) else { return }

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
            nextEpisodeCandidate = try await next
            previousEpisodeCandidate = try await previous
            nextEpisodeContext = context
        } catch {
            NSLog("[EclipsePlex] Adjacent episode prefetch failed: %@", error.localizedDescription)
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
            NSLog(
                "[EclipsePlex] Play next: offering S%dE%d — %@",
                next.seasonNumber,
                next.episodeNumber,
                next.title
            )
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
        guard case .plex(let server, _, let title, _) = request else { return }
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

#if os(iOS)
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
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                Button {
                    onInteraction()
                    proxy.jumpForward(10)
                } label: {
                    Image(systemName: "goforward.10")
                }

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
        .padding(.horizontal)
        .padding(.bottom, 12)
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
    }
    .environmentObject(OfflineDownloadManager())
}
