#if os(iOS) || os(tvOS)
import SwiftUI

/// iOS VLC player with direct-play → transcode fallback and Plex HTTP headers.
struct IOSVLCPlayerView: UIViewRepresentable {
    let playback: ResolvedPlayback
    @ObservedObject var proxy: VLCVideoPlayer.Proxy
    @Binding var statusText: String
    @Binding var errorMessage: String?
    var onPositionUpdate: (Int, Int) -> Void
    var onPlaybackInfoUpdate: (VLCVideoPlayer.PlaybackInformation) -> Void
    var onPlayerStateChange: (VLCVideoPlayer.State) -> Void = { _ in }
    var onNaturalEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            playback: playback,
            statusText: $statusText,
            errorMessage: $errorMessage,
            onPositionUpdate: onPositionUpdate,
            onPlaybackInfoUpdate: onPlaybackInfoUpdate,
            onPlayerStateChange: onPlayerStateChange,
            onNaturalEnd: onNaturalEnd
        )
    }

    func makeUIView(context: Context) -> UIVLCVideoPlayerView {
        let view = UIVLCVideoPlayerView(
            configuration: context.coordinator.currentConfiguration(),
            proxy: proxy,
            onTicksUpdated: { ticks, info in
                context.coordinator.handleTicks(ticks, info: info)
            },
            onStateUpdated: { state, info in
                context.coordinator.handleState(state, info: info)
            },
            loggingInfo: nil
        )
        context.coordinator.playerView = view
        context.coordinator.startInitialPlayback(on: view)
        return view
    }

    func updateUIView(_ uiView: UIVLCVideoPlayerView, context: Context) {
        context.coordinator.updatePlaybackIfNeeded(playback, view: uiView)
    }

    static func dismantleUIView(_ uiView: UIVLCVideoPlayerView, coordinator: Coordinator) {
        coordinator.deactivate()
        coordinator.persistPositionIfNeeded()
        uiView.teardownPlayback()
    }

    final class Coordinator {
        private var playback: ResolvedPlayback
        private var statusText: Binding<String>
        private var errorMessage: Binding<String?>
        private let onPositionUpdate: (Int, Int) -> Void
        private let onPlaybackInfoUpdate: (VLCVideoPlayer.PlaybackInformation) -> Void
        private let onPlayerStateChange: (VLCVideoPlayer.State) -> Void
        private let onNaturalEnd: () -> Void

        weak var playerView: UIVLCVideoPlayerView?
        private var isActive = true
        private var didNotifyNaturalEnd = false
        private var lastPositionMs = 0
        private var lastDurationMs = 0
        private var candidateIndex = 0
        private var activeStreamSignature: String?
        private var didFailAll = false
        private var didApplyPreferredSubtitle = false
        private var lastPositionSaveTime: CFAbsoluteTime = 0
        /// Coarse fingerprint of the last `PlaybackInformation` we forwarded to
        /// SwiftUI. Used to skip republishing during ticks when nothing the UI
        /// cares about has changed (tracks, selected indices, video size).
        private var lastPublishedInfoFingerprint: String?

        init(
            playback: ResolvedPlayback,
            statusText: Binding<String>,
            errorMessage: Binding<String?>,
            onPositionUpdate: @escaping (Int, Int) -> Void,
            onPlaybackInfoUpdate: @escaping (VLCVideoPlayer.PlaybackInformation) -> Void,
            onPlayerStateChange: @escaping (VLCVideoPlayer.State) -> Void,
            onNaturalEnd: @escaping () -> Void
        ) {
            self.playback = playback
            self.statusText = statusText
            self.errorMessage = errorMessage
            self.onPositionUpdate = onPositionUpdate
            self.onPlaybackInfoUpdate = onPlaybackInfoUpdate
            self.onPlayerStateChange = onPlayerStateChange
            self.onNaturalEnd = onNaturalEnd
        }

        func deactivate() {
            isActive = false
            playerView = nil
        }

        func currentConfiguration() -> VLCVideoPlayer.Configuration {
            playback.vlcConfiguration(candidateIndex: candidateIndex)
        }

        func startInitialPlayback(on view: UIVLCVideoPlayerView) {
            guard activeStreamSignature == nil else { return }
            startCandidate(on: view)
        }

        func updatePlaybackIfNeeded(_ newPlayback: ResolvedPlayback, view: UIVLCVideoPlayerView) {
            guard newPlayback.streamSignature != activeStreamSignature else { return }
            playback = newPlayback
            candidateIndex = 0
            activeStreamSignature = nil
            didFailAll = false
            didApplyPreferredSubtitle = false
            startCandidate(on: view)
        }

        func handleTicks(_ ticks: Int, info: VLCVideoPlayer.PlaybackInformation) {
            publishOnMain {
                self.lastPositionMs = ticks
                self.lastDurationMs = info.length
                self.onPositionUpdate(ticks, info.length)
                self.publishInfoIfChanged(info)
                self.persistPositionPeriodically(positionMs: ticks, durationMs: info.length)
            }
        }

        func handleState(_ state: VLCVideoPlayer.State, info: VLCVideoPlayer.PlaybackInformation) {
            publishOnMain {
                self.publishInfoIfChanged(info, force: true)
                self.onPlayerStateChange(state)
                self.statusText.wrappedValue = state.label
                switch state {
                case .playing:
                    self.errorMessage.wrappedValue = nil
                    if !self.didApplyPreferredSubtitle {
                        self.didApplyPreferredSubtitle = true
                        self.applyPreferredSubtitleIfNeeded()
                    }
                case .error:
                    self.handlePlaybackFailure(on: self.playerView)
                case .ended:
                    if let ctx = self.playback.resumeContext {
                        PlaybackPositionStore.clear(serverId: ctx.serverId, ratingKey: ctx.ratingKey)
                    }
                    self.onNaturalEnd()
                default:
                    break
                }
            }
        }

        func persistPositionIfNeeded() {
            guard let playerView else { return }
            let snapshot = playerView.playbackPositionSnapshot()
            persistPosition(positionMs: snapshot.positionMs, durationMs: snapshot.durationMs)
        }

        private func shouldTreatAsNaturalEnd(
            info: VLCVideoPlayer.PlaybackInformation,
            state: VLCVideoPlayer.State
        ) -> Bool {
            if state == .ended { return true }
            guard state == .stopped else { return false }
            let duration = lastDurationMs > 0 ? lastDurationMs : info.length
            let position = lastPositionMs
            guard duration > 60_000, position > 0 else { return false }
            return position >= duration - 5_000
        }

        private func notifyNaturalEndIfNeeded() {
            guard !didNotifyNaturalEnd else { return }
            didNotifyNaturalEnd = true
            if let ctx = playback.resumeContext {
                PlaybackPositionStore.clear(serverId: ctx.serverId, ratingKey: ctx.ratingKey)
            }
            onNaturalEnd()
        }

        private func startCandidate(on view: UIVLCVideoPlayerView) {
            guard isActive, candidateIndex < playback.candidates.count else { return }
            didNotifyNaturalEnd = false
            let candidate = playback.candidates[candidateIndex]
            activeStreamSignature = playback.streamSignature
            publishOnMain {
                guard self.isActive else { return }
                self.statusText.wrappedValue = "Opening \(candidate.label)…"
                self.errorMessage.wrappedValue = nil
            }
            view.setupVLCMediaPlayer(with: playback.vlcConfiguration(candidateIndex: candidateIndex))
        }

        private func handlePlaybackFailure(on view: UIVLCVideoPlayerView?) {
            let nextIndex = candidateIndex + 1
            if nextIndex < playback.candidates.count {
                candidateIndex = nextIndex
                activeStreamSignature = nil
                statusText.wrappedValue = "Trying \(playback.candidates[nextIndex].label)…"
                if let view {
                    startCandidate(on: view)
                }
                return
            }
            guard !didFailAll else { return }
            didFailAll = true
            let message = playback.candidates.first?.streamKind == .localFile
                ? "The downloaded file could not be opened. Try downloading again."
                : "The stream could not be opened."
            errorMessage.wrappedValue = PlaybackErrorMessages.friendly(message)
            statusText.wrappedValue = "Error"
        }

        private func applyPreferredSubtitleIfNeeded() {
            guard case .plexStream = playback.streamOptions.subtitleSelection else { return }
        }

        /// Skips forwarding `PlaybackInformation` to SwiftUI when none of the
        /// UI-relevant fields changed (track list, selected indices, video
        /// size). VLC publishes the same info on every tick (~3 Hz), so this
        /// keeps the player chrome from re-rendering 3× per second.
        private func publishInfoIfChanged(
            _ info: VLCVideoPlayer.PlaybackInformation,
            force: Bool = false
        ) {
            let fingerprint = infoFingerprint(info)
            if !force, fingerprint == lastPublishedInfoFingerprint { return }
            lastPublishedInfoFingerprint = fingerprint
            onPlaybackInfoUpdate(info)
        }

        /// VLC delegate callbacks arrive off the main thread; SwiftUI state
        /// must only be touched on the main actor while the view is mounted.
        private func publishOnMain(_ block: @escaping () -> Void) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActive else { return }
                block()
            }
        }

        private func infoFingerprint(_ info: VLCVideoPlayer.PlaybackInformation) -> String {
            let subIndexes = info.subtitleTracks.map { String($0.index) }.joined(separator: ",")
            let audIndexes = info.audioTracks.map { String($0.index) }.joined(separator: ",")
            let w = Int(info.videoSize.width)
            let h = Int(info.videoSize.height)
            return "\(subIndexes)|\(info.currentSubtitleTrack.index)|\(audIndexes)|\(info.currentAudioTrack.index)|\(w)x\(h)"
        }

        private func persistPositionPeriodically(positionMs: Int, durationMs: Int) {
            guard let ctx = playback.resumeContext else { return }
            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastPositionSaveTime > 5 else { return }
            lastPositionSaveTime = now
            if durationMs > 0, positionMs >= durationMs - 30_000 {
                PlaybackPositionStore.clear(serverId: ctx.serverId, ratingKey: ctx.ratingKey)
            } else if positionMs > 5_000 {
                PlaybackPositionStore.save(
                    serverId: ctx.serverId,
                    ratingKey: ctx.ratingKey,
                    positionMs: positionMs
                )
            }
        }

        private func persistPosition(positionMs: Int, durationMs: Int) {
            guard let ctx = playback.resumeContext else { return }
            if durationMs > 0, positionMs >= durationMs - 30_000 {
                PlaybackPositionStore.clear(serverId: ctx.serverId, ratingKey: ctx.ratingKey)
            } else if positionMs > 5_000 {
                PlaybackPositionStore.save(
                    serverId: ctx.serverId,
                    ratingKey: ctx.ratingKey,
                    positionMs: positionMs
                )
            }
        }
    }
}

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
