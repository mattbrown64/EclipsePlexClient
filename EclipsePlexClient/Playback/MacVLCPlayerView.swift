#if os(macOS)
import AppKit
import SwiftUI
import VLCKit

/// Minimal macOS VLC bridge — `VLCVideoView` with an explicit frame; defers only audio setup to first tick.
struct MacVLCPlayerView: NSViewRepresentable {
    let url: URL
    let streamKind: PlaybackStreamKind
    let httpHeaderFields: [String: String]
    @ObservedObject var controller: MacVLCPlaybackController
    @Binding var statusText: String
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            streamKind: streamKind,
            httpHeaderFields: httpHeaderFields,
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
        context.coordinator.scheduleStart(in: view, url: url)
        return view
    }

    func updateNSView(_ nsView: VLCVideoView, context: Context) {
        context.coordinator.scheduleStart(in: nsView, url: url)
    }

    final class Coordinator: NSObject, VLCMediaPlayerDelegate, VLCLibraryLogReceiverProtocol {
        private let streamKind: PlaybackStreamKind
        private let httpHeaderFields: [String: String]
        private let controller: MacVLCPlaybackController
        private var statusText: Binding<String>
        private var errorMessage: Binding<String?>
        private var player: VLCMediaPlayer?
        private var didFail = false
        private var didConfigureAudio = false
        private var activeURL: URL?
        private var lastVLCError: String?
        private var lastPublishedState: VLCMediaPlayerState?
        private var lastControllerSyncTime: CFAbsoluteTime = 0

        init(
            streamKind: PlaybackStreamKind,
            httpHeaderFields: [String: String],
            controller: MacVLCPlaybackController,
            statusText: Binding<String>,
            errorMessage: Binding<String?>
        ) {
            self.streamKind = streamKind
            self.httpHeaderFields = httpHeaderFields
            self.controller = controller
            self.statusText = statusText
            self.errorMessage = errorMessage
        }

        deinit {
            player?.stop()
        }

        func scheduleStart(in videoView: VLCVideoView, url: URL) {
            DispatchQueue.main.async { [weak self, weak videoView] in
                guard let self, let videoView else { return }
                self.start(in: videoView, url: url)
            }
        }

        func start(in videoView: VLCVideoView, url: URL) {
            guard activeURL != url || player == nil else { return }
            stop()

            activeURL = url
            didFail = false
            didConfigureAudio = false
            lastVLCError = nil
            lastPublishedState = nil
            lastControllerSyncTime = 0
            errorMessage.wrappedValue = nil

            let library = VLCLibrary.shared()
            library.debugLogging = true
            library.debugLoggingLevel = 1
            library.debugLoggingTarget = self

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

            NSLog("[EclipsePlex VLC] Opening \(streamKind) → %@", url.host ?? url.absoluteString)
            player.play()
            updateStatus { self.publishState(from: player) }
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
            if level <= 1 {
                NSLog("[EclipsePlex VLC] libvlc[\(level)]: %@", message)
            }
            if level <= 0
                || message.localizedCaseInsensitiveContains("error")
                || message.localizedCaseInsensitiveContains("403")
                || message.localizedCaseInsensitiveContains("401")
                || message.localizedCaseInsensitiveContains("can't be opened")
                || message.localizedCaseInsensitiveContains("unable to open")
            {
                lastVLCError = message
            }
        }

        private func applyNetworkOptions(to media: VLCMedia, url: URL) {
            guard !url.isFileURL else { return }
            media.addOption(":http-user-agent=\(PlexHTTPConstants.productName)/\(PlexHTTPConstants.productVersion)")
            media.addOption(":http-reconnect")
            media.addOption(":network-caching=5000")
            if !httpHeaderFields.isEmpty {
                let lines = httpHeaderFields
                    .map { key, value in
                        let escaped = value
                            .replacingOccurrences(of: "\r", with: "")
                            .replacingOccurrences(of: "\n", with: "")
                        return "\(key): \(escaped)"
                    }
                    .joined(separator: "\r\n")
                media.addOption(":http-extra-headers=\(lines)\r\n")
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
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastControllerSyncTime > 0.5 {
                lastControllerSyncTime = now
                controller.sync(from: player)
            }

            let state = player.state
            guard state != lastPublishedState else { return }
            lastPublishedState = state

            updateStatus {
                let name = self.stateName(state)
                self.statusText.wrappedValue = name
            }

            switch state {
            case .playing:
                didFail = false
                updateStatus { self.errorMessage.wrappedValue = nil }
                configureAudioIfNeeded(player)
            case .error:
                let detail = lastVLCError ?? "The stream could not be opened."
                fail(with: detail)
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
            NSLog("[EclipsePlex VLC] Playback failed: %@", message)
        }

        private func updateStatus(_ block: @escaping () -> Void) {
            DispatchQueue.main.async(execute: block)
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
