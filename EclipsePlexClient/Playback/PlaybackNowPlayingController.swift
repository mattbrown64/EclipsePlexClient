//
//  PlaybackNowPlayingController.swift
//  EclipsePlexClient
//

import Foundation

#if os(iOS) || os(tvOS) || os(macOS)
import AVFoundation
import MediaPlayer
#endif

/// Lock-screen / Control Center Now Playing and remote transport commands.
@MainActor
final class PlaybackNowPlayingController {
    static let shared = PlaybackNowPlayingController()

    private var isActive = false
    private var playHandler: (() -> Void)?
    private var pauseHandler: (() -> Void)?
    private var toggleHandler: (() -> Void)?
    private var skipForwardHandler: (() -> Void)?
    private var skipBackwardHandler: (() -> Void)?

    private init() {}

    func activateAudioSessionIfNeeded() {
#if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            AppLog.playback("AVAudioSession activation failed: \(error.localizedDescription)")
        }
#endif
    }

    func deactivateAudioSessionIfNeeded() {
#if os(iOS) || os(tvOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            AppLog.playback("AVAudioSession deactivation failed: \(error.localizedDescription)")
        }
#endif
    }

    func beginSession(
        title: String?,
        play: @escaping () -> Void,
        pause: @escaping () -> Void,
        toggle: @escaping () -> Void,
        skipForward: @escaping () -> Void,
        skipBackward: @escaping () -> Void
    ) {
        playHandler = play
        pauseHandler = pause
        toggleHandler = toggle
        skipForwardHandler = skipForward
        skipBackwardHandler = skipBackward

        guard !isActive else { return }
        isActive = true
        activateAudioSessionIfNeeded()
        registerRemoteCommands()
    }

    func endSession() {
        guard isActive else { return }
        isActive = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        unregisterRemoteCommands()
        playHandler = nil
        pauseHandler = nil
        toggleHandler = nil
        skipForwardHandler = nil
        skipBackwardHandler = nil
        deactivateAudioSessionIfNeeded()
    }

    func update(
        title: String?,
        positionMs: Int,
        durationMs: Int,
        isPlaying: Bool
    ) {
        guard isActive else { return }

        var info: [String: Any] = [:]
        if let title, !title.isEmpty {
            info[MPMediaItemPropertyTitle] = title
        }
        if durationMs > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000.0
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(positionMs) / 1000.0
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [15]

        center.playCommand.addTarget { [weak self] _ in
            self?.playHandler?()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pauseHandler?()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.toggleHandler?()
            return .success
        }
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForwardHandler?()
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackwardHandler?()
            return .success
        }
    }

    private func unregisterRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
    }
}
