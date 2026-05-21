#if os(iOS)
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
        coordinator.persistPositionIfNeeded()
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
        private var didNotifyNaturalEnd = false
        private var lastPositionMs = 0
        private var lastDurationMs = 0
        private var candidateIndex = 0
        private var activeStreamSignature: String?
        private var didFailAll = false
        private var didApplyPreferredSubtitle = false
        private var lastPositionSaveTime: CFAbsoluteTime = 0

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
            lastPositionMs = ticks
            lastDurationMs = info.length
            onPositionUpdate(ticks, info.length)
            onPlaybackInfoUpdate(info)
            persistPositionPeriodically(positionMs: ticks, durationMs: info.length)
        }

        func handleState(_ state: VLCVideoPlayer.State, info: VLCVideoPlayer.PlaybackInformation) {
            onPlaybackInfoUpdate(info)
            onPlayerStateChange(state)
            statusText.wrappedValue = state.label
            switch state {
            case .playing:
                errorMessage.wrappedValue = nil
                if !didApplyPreferredSubtitle {
                    didApplyPreferredSubtitle = true
                    applyPreferredSubtitleIfNeeded()
                }
            case .error:
                handlePlaybackFailure(on: playerView)
            case .ended:
                if let ctx = playback.resumeContext {
                    PlaybackPositionStore.clear(serverId: ctx.serverId, ratingKey: ctx.ratingKey)
                }
                onNaturalEnd()
            default:
                break
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
            guard candidateIndex < playback.candidates.count else { return }
            didNotifyNaturalEnd = false
            let candidate = playback.candidates[candidateIndex]
            activeStreamSignature = playback.streamSignature
            statusText.wrappedValue = "Opening \(candidate.label)…"
            errorMessage.wrappedValue = nil
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
