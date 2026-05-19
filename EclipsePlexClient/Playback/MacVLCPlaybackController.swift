#if os(macOS)
import Combine
import VLCKit

/// Drives SwiftUI transport controls for `MacVLCPlayerView`.
@MainActor
final class MacVLCPlaybackController: ObservableObject {
    @Published private(set) var positionMs = 0
    @Published private(set) var durationMs = 0
    @Published private(set) var isPlaying = false
    @Published var volume = 100
    @Published var isMuted = false

    weak var player: VLCMediaPlayer?

    var formattedPosition: String { Self.format(ms: positionMs) }
    var formattedDuration: String { Self.format(ms: durationMs) }

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(toMs: Int) {
        guard let player else { return }
        let clamped = max(0, min(toMs, durationMs > 0 ? durationMs : toMs))
        player.time = VLCTime(number: clamped as NSNumber)
        positionMs = clamped
    }

    func skip(by seconds: Int) {
        seek(toMs: positionMs + seconds * 1_000)
    }

    func setVolume(_ value: Int) {
        let clamped = min(100, max(0, value))
        volume = clamped
        guard let audio = player?.audio else { return }
        audio.volume = Int32(clamped)
        if clamped > 0 {
            isMuted = false
            audio.isMuted = false
        }
    }

    func toggleMute() {
        guard let audio = player?.audio else { return }
        isMuted.toggle()
        audio.isMuted = isMuted
    }

    func sync(from player: VLCMediaPlayer) {
        self.player = player
        positionMs = Int(player.time.intValue)
        durationMs = Int(player.media?.length.intValue ?? 0)
        isPlaying = player.isPlaying

        if let audio = player.audio {
            volume = Int(audio.volume)
            isMuted = audio.isMuted
        }
    }

    private static func format(ms: Int) -> String {
        guard ms > 0 else { return "0:00" }
        let totalSeconds = ms / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
#endif
