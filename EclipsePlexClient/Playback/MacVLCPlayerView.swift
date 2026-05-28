#if os(macOS)
import AppKit
import SwiftUI
import VLCKit

/// Minimal macOS VLC bridge — `VLCVideoView` with an explicit frame; defers only audio setup to first tick.
struct MacVLCPlayerView: NSViewRepresentable {
    let playback: ResolvedPlayback
    @ObservedObject var controller: MacVLCPlaybackController
    @Binding var statusText: String
    @Binding var errorMessage: String?
    var onNaturalEnd: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            playback: playback,
            controller: controller,
            statusText: $statusText,
            errorMessage: $errorMessage,
            onNaturalEnd: onNaturalEnd
        )
    }

    func makeNSView(context: Context) -> VLCVideoView {
        let view = VLCVideoView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
        view.autoresizingMask = [.width, .height]
        view.backColor = .black
        view.wantsLayer = true
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: VLCVideoView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.schedulePlaybackUpdate(playback)
    }

    static func dismantleNSView(_ nsView: VLCVideoView, coordinator: Coordinator) {
        coordinator.teardown(savePosition: true)
    }

    final class Coordinator: NSObject, VLCMediaPlayerDelegate {
        private var playback: ResolvedPlayback
        private var activeStreamSignature: String?
        private let controller: MacVLCPlaybackController
        private var statusText: Binding<String>
        private var errorMessage: Binding<String?>
        private let onNaturalEnd: () -> Void
        private weak var videoView: VLCVideoView?

        private var player: VLCMediaPlayer?
        private var candidateIndex = 0
        private var didFailAll = false
        private var didConfigureAudio = false
        private var didApplyResumePosition = false
        private var didApplyPreferredSubtitle = false
        private var lastVLCError: String?
        private var lastPublishedState: VLCMediaPlayerState?
        private var didNotifyNaturalEnd = false
        private var lastControllerSyncTime: CFAbsoluteTime = 0
        private var lastPositionSaveTime: CFAbsoluteTime = 0
        private var lastTickPositionMs = 0
        private var playbackInferredFromTicks = false
        private var pendingPlaybackUpdate: ResolvedPlayback?
        private var isProcessingPlaybackUpdate = false

        init(
            playback: ResolvedPlayback,
            controller: MacVLCPlaybackController,
            statusText: Binding<String>,
            errorMessage: Binding<String?>,
            onNaturalEnd: @escaping () -> Void
        ) {
            self.playback = playback
            self.controller = controller
            self.statusText = statusText
            self.errorMessage = errorMessage
            self.onNaturalEnd = onNaturalEnd
        }

        deinit {
            teardown(savePosition: true)
        }

        func attach(to view: VLCVideoView) {
            if videoView !== view {
                videoView = view
                if !view.gestureRecognizers.contains(where: { $0 is NSClickGestureRecognizer }) {
                    let click = NSClickGestureRecognizer(target: self, action: #selector(toggleFullscreen(_:)))
                    click.numberOfClicksRequired = 2
                    view.addGestureRecognizer(click)
                }
            }
        }

        func schedulePlaybackUpdate(_ newPlayback: ResolvedPlayback) {
            pendingPlaybackUpdate = newPlayback
            guard !isProcessingPlaybackUpdate else { return }
            DispatchQueue.main.async { [weak self] in
                self?.processPendingPlaybackUpdate()
            }
        }

        private func processPendingPlaybackUpdate() {
            guard let newPlayback = pendingPlaybackUpdate else { return }
            pendingPlaybackUpdate = nil
            guard newPlayback.streamSignature != activeStreamSignature else { return }

            isProcessingPlaybackUpdate = true
            defer { isProcessingPlaybackUpdate = false }

            let savedMs = controller.positionMs > 0 ? controller.positionMs : newPlayback.resumePositionMs
            playback = savedMs.map { newPlayback.withResumePositionMs($0) } ?? newPlayback
            controller.setSourceVideoSize(playback.sourceVideoSize)
            candidateIndex = 0
            activeStreamSignature = nil
            didNotifyNaturalEnd = false
            startCurrentCandidate()
        }

        @objc private func toggleFullscreen(_ sender: NSClickGestureRecognizer) {
            videoView?.window?.toggleFullScreen(nil)
        }

        func startCurrentCandidate() {
            guard candidateIndex < playback.candidates.count else { return }
            DispatchQueue.main.async { [weak self] in
                self?.startCandidate(at: self?.candidateIndex ?? 0)
            }
        }

        func teardown(savePosition: Bool) {
            if savePosition {
                persistPositionIfNeeded()
            }
            player?.stop()
            player = nil
            controller.player = nil
        }

        private func startCandidate(at index: Int) {
            guard let videoView, index < playback.candidates.count else { return }
            candidateIndex = index
            activeStreamSignature = playback.streamSignature
            let candidate = playback.candidates[index]
            stopPlayerOnly()

            didFailAll = false
            didConfigureAudio = false
            didApplyResumePosition = false
            didApplyPreferredSubtitle = false
            lastVLCError = nil
            lastPublishedState = nil
            didNotifyNaturalEnd = false
            lastControllerSyncTime = 0
            lastTickPositionMs = 0
            playbackInferredFromTicks = false
            errorMessage.wrappedValue = nil

            let url = candidate.url
            let media: VLCMedia = if url.isFileURL {
                VLCMedia(path: url.path)
            } else {
                VLCMedia(url: url)
            }
            applyNetworkOptions(to: media, url: url)

            let player = VLCMediaPlayer(videoView: videoView)
            player.media = media
            player.delegate = self
            self.player = player
            controller.player = player
            controller.applySavedPlaybackRate(to: player)

            let label = playback.candidates.count > 1 ? candidate.label : candidate.streamKind.debugLabel
            AppLog.playbackDebug(
                "VLC opening \(label) (\(url.pathExtension.isEmpty ? "stream" : url.pathExtension)) → \(AppLog.redactURL(url) ?? "stream")"
            )
            let openingStatus = playback.candidates.count > 1
                ? "Opening (\(candidate.label))…"
                : "Opening…"
            updateStatus {
                self.statusText.wrappedValue = openingStatus
            }
            player.play()
        }

        private func stopPlayerOnly() {
            player?.stop()
            player = nil
            controller.player = nil
        }

        func mediaPlayerTimeChanged(_ aNotification: Notification) {
            guard let player = aNotification.object as? VLCMediaPlayer else { return }
            configureAudioIfNeeded(player)
            applyResumeIfNeeded(player)
            promotePlayingStateIfTimeIsAdvancing(player)
            publishState(from: player)
            persistPositionPeriodically(from: player)
        }

        func mediaPlayerStateChanged(_ aNotification: Notification) {
            guard let player = aNotification.object as? VLCMediaPlayer else { return }
            configureAudioIfNeeded(player)
            applyResumeIfNeeded(player)
            publishState(from: player)
        }

        private func applyNetworkOptions(to media: VLCMedia, url: URL) {
            VLCNetworkMediaOptions.apply(to: media, url: url, headerFields: playback.httpHeaderFields)
        }

        private func applyResumeIfNeeded(_ player: VLCMediaPlayer) {
            guard !didApplyResumePosition,
                  let resumeMs = playback.resumePositionMs,
                  resumeMs > 0,
                  player.state == .playing || player.isPlaying
            else { return }

            let duration = Int(player.media?.length.intValue ?? 0)
            guard duration <= 0 || resumeMs < duration - 30_000 else {
                didApplyResumePosition = true
                if let ctx = playback.resumeContext {
                    PlaybackPositionStore.clear(serverId: ctx.serverId, ratingKey: ctx.ratingKey)
                }
                return
            }

            didApplyResumePosition = true
            player.time = VLCTime(number: resumeMs as NSNumber)
            AppLog.playbackDebug("VLC resumed at \(resumeMs) ms")
            updateStatus { self.statusText.wrappedValue = "Resuming…" }
        }

        private func configureAudioIfNeeded(_ player: VLCMediaPlayer) {
            guard player.isPlaying || player.state == .esAdded else { return }

            if let audio = player.audio {
                audio.isMuted = false
                if audio.volume <= 0 {
                    audio.volume = 100
                }
            }

            if player.currentAudioTrackIndex < 0,
               player.numberOfAudioTracks > 0,
               let indexes = player.audioTrackIndexes as? [Int],
               let track = indexes.first(where: { $0 >= 0 })
            {
                player.currentAudioTrackIndex = Int32(track)
            }

            didConfigureAudio = true
        }

        private func publishState(from player: VLCMediaPlayer) {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastControllerSyncTime > 0.5 {
                lastControllerSyncTime = now
                controller.scheduleSync(from: player)
            }

            let state = player.state
            if playbackInferredFromTicks,
               lastPublishedState == .playing,
               state == .buffering || state == .opening {
                return
            }
            guard state != lastPublishedState else { return }
            lastPublishedState = state

            updateStatus {
                self.statusText.wrappedValue = self.stateName(state)
            }

            switch state {
            case .playing:
                playbackInferredFromTicks = false
                updateStatus { self.errorMessage.wrappedValue = nil }
                configureAudioIfNeeded(player)
                if !self.didApplyPreferredSubtitle {
                    self.didApplyPreferredSubtitle = true
                    if case .plexStream = self.playback.streamOptions.subtitleSelection {
                        // Burned in via Plex transcode URL.
                    } else {
                        let selection = self.playback.streamOptions.subtitleSelection
                        DispatchQueue.main.async {
                            self.controller.applyPreferredSubtitle(from: selection)
                        }
                    }
                }
            case .error:
                let detail = lastVLCError ?? "The stream could not be opened."
                handlePlaybackFailure(detail)
            case .ended, .stopped:
                if shouldTreatAsNaturalEnd(player, state: state) {
                    notifyNaturalEndIfNeeded()
                }
            default:
                break
            }
        }

        private func shouldTreatAsNaturalEnd(_ player: VLCMediaPlayer, state: VLCMediaPlayerState) -> Bool {
            if state == .ended { return true }
            guard state == .stopped else { return false }
            let duration = Int(player.media?.length.intValue ?? 0)
            let position = Int(player.time.intValue)
            guard duration > 60_000, position > 0 else { return false }
            return position >= duration - 5_000
        }

        private func notifyNaturalEndIfNeeded() {
            guard !didNotifyNaturalEnd else { return }
            didNotifyNaturalEnd = true
            if let ctx = playback.resumeContext {
                PlaybackPositionStore.clear(serverId: ctx.serverId, ratingKey: ctx.ratingKey)
            }
            updateStatus { self.onNaturalEnd() }
        }

        private func handlePlaybackFailure(_ message: String) {
            let nextIndex = candidateIndex + 1
            if nextIndex < playback.candidates.count {
                AppLog.playback("VLC stream failed (\(message)), trying fallback: \(playback.candidates[nextIndex].label)")
                updateStatus {
                    self.statusText.wrappedValue = "Trying \(self.playback.candidates[nextIndex].label)…"
                    self.errorMessage.wrappedValue = nil
                }
                DispatchQueue.main.async { [weak self] in
                    self?.startCandidate(at: nextIndex)
                }
                return
            }

            guard !didFailAll else { return }
            didFailAll = true
            let friendly = PlaybackErrorMessages.friendly(message)
            updateStatus {
                self.errorMessage.wrappedValue = friendly
                self.statusText.wrappedValue = "Error"
            }
            AppLog.playback("VLC playback failed: \(friendly)")
        }

        private func persistPositionPeriodically(from player: VLCMediaPlayer) {
            guard let ctx = playback.resumeContext else { return }
            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastPositionSaveTime > 5 else { return }
            lastPositionSaveTime = now
            persistPosition(from: player, context: ctx)
        }

        private func persistPositionIfNeeded() {
            guard let ctx = playback.resumeContext, let player else { return }
            persistPosition(from: player, context: ctx)
        }

        private func persistPosition(from player: VLCMediaPlayer, context: PlaybackResumeContext) {
            let position = Int(player.time.intValue)
            let duration = Int(player.media?.length.intValue ?? 0)
            if duration > 0, position >= duration - 30_000 {
                PlaybackPositionStore.clear(serverId: context.serverId, ratingKey: context.ratingKey)
            } else if position > 5_000 {
                PlaybackPositionStore.save(
                    serverId: context.serverId,
                    ratingKey: context.ratingKey,
                    positionMs: position
                )
            }
        }

        private func updateStatus(_ block: @escaping () -> Void) {
            DispatchQueue.main.async(execute: block)
        }

        private func promotePlayingStateIfTimeIsAdvancing(_ player: VLCMediaPlayer) {
            let position = Int(player.time.intValue)
            guard position > lastTickPositionMs + 150 else { return }
            lastTickPositionMs = position

            let vlcReportsLoading = player.state == .buffering || player.state == .opening
            guard vlcReportsLoading || lastPublishedState == .buffering || lastPublishedState == .opening else {
                return
            }

            playbackInferredFromTicks = vlcReportsLoading
            guard lastPublishedState != .playing else { return }
            lastPublishedState = .playing
            updateStatus {
                self.statusText.wrappedValue = "Playing"
            }
        }

        private func stateName(_ state: VLCMediaPlayerState) -> String {
            switch state {
            case .stopped: "Stopped"
            case .opening: "Opening"
            case .buffering: "Buffering"
            case .ended: "Ended"
            case .error: "Error"
            case .playing: "Playing"
            case .paused: "Paused"
            case .esAdded: "Ready"
            @unknown default: "Unknown"
            }
        }
    }
}

private extension PlaybackStreamKind {
    var debugLabel: String {
        switch self {
        case .localFile: "Local file"
        case .remote: "Remote stream"
        case .plexTranscode: "Plex transcode"
        case .plexDirect: "Plex direct"
        }
    }
}
#endif
