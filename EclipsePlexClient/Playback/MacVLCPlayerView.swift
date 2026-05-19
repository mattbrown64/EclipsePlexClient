#if os(macOS)
import AppKit
import SwiftUI
import VLCKit

/// Minimal macOS VLC bridge — `VLCVideoView` with an explicit frame; defers only audio setup to first tick.
struct MacVLCPlayerView: NSViewRepresentable {
    let url: URL
    @ObservedObject var controller: MacVLCPlaybackController
    @Binding var statusText: String
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            controller: controller,
            statusText: $statusText,
            errorMessage: $errorMessage
        )
    }

    func makeNSView(context: Context) -> VLCVideoView {
        let view = VLCVideoView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
        view.autoresizingMask = [.width, .height]
        view.backColor = .black
        view.wantsLayer = true
        context.coordinator.start(in: view, url: url)
        return view
    }

    func updateNSView(_ nsView: VLCVideoView, context: Context) {
        context.coordinator.restartIfNeeded(in: nsView, url: url)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: VLCVideoView, context: Context) -> CGSize? {
        let width = proposal.width ?? 960
        let height = proposal.height ?? 540
        return CGSize(
            width: max(width, 320),
            height: max(height, 180)
        )
    }

    final class Coordinator: NSObject, VLCMediaPlayerDelegate, VLCLibraryLogReceiverProtocol {
        private let controller: MacVLCPlaybackController
        private var statusText: Binding<String>
        private var errorMessage: Binding<String?>
        private var player: VLCMediaPlayer?
        private var didFail = false
        private var didConfigureAudio = false
        private var activeURL: URL?

        init(
            controller: MacVLCPlaybackController,
            statusText: Binding<String>,
            errorMessage: Binding<String?>
        ) {
            self.controller = controller
            self.statusText = statusText
            self.errorMessage = errorMessage
        }

        deinit {
            player?.stop()
        }

        func start(in videoView: VLCVideoView, url: URL) {
            guard activeURL != url || player == nil else { return }
            stop()

            activeURL = url
            didFail = false
            didConfigureAudio = false
            errorMessage.wrappedValue = nil

            let library = VLCLibrary.shared()
            library.debugLogging = false

            let media: VLCMedia = if url.isFileURL {
                VLCMedia(path: url.path)
            } else {
                VLCMedia(url: url)
            }

            let player = VLCMediaPlayer(videoView: videoView)
            player.media = media
            player.delegate = self
            self.player = player
            controller.player = player

            player.play()
            updateStatus { self.publishState(from: player) }
        }

        func restartIfNeeded(in videoView: VLCVideoView, url: URL) {
            if activeURL != url {
                start(in: videoView, url: url)
            }
        }

        private func stop() {
            player?.stop()
            player = nil
            controller.player = nil
        }

        func mediaPlayerTimeChanged(_ aNotification: Notification) {
            guard let player = aNotification.object as? VLCMediaPlayer else { return }
            configureAudioIfNeeded(player)
            updateStatus { self.publishState(from: player) }
        }

        func mediaPlayerStateChanged(_ aNotification: Notification) {
            guard let player = aNotification.object as? VLCMediaPlayer else { return }
            configureAudioIfNeeded(player)
            updateStatus { self.publishState(from: player) }
        }

        func handleMessage(_ message: String, debugLevel level: Int32) {
            if message.localizedCaseInsensitiveContains("403")
                || message.localizedCaseInsensitiveContains("can't be opened")
                || message.localizedCaseInsensitiveContains("unable to open")
            {
                fail(with: message)
            }
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
            controller.sync(from: player)

            let name = stateName(player.state)
            let ticks = player.time.intValue
            statusText.wrappedValue = "\(name) · \(ticks)ms"

            switch player.state {
            case .playing:
                didFail = false
                errorMessage.wrappedValue = nil
                configureAudioIfNeeded(player)
            case .error:
                fail(with: "Playback failed. Check the URL or file path.")
            default:
                break
            }
        }

        private func fail(with message: String) {
            guard !didFail else { return }
            didFail = true
            updateStatus {
                self.errorMessage.wrappedValue = message
                self.statusText.wrappedValue = "Error"
            }
        }

        private func updateStatus(_ block: @escaping () -> Void) {
            if Thread.isMainThread {
                block()
            } else {
                DispatchQueue.main.async(execute: block)
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
#endif
