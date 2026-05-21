#if os(macOS)
import Combine
import CoreGraphics
import VLCKit

/// Embedded or VLC-reported media track (subtitle or audio).
struct VLCMediaStreamTrack: Identifiable, Equatable {
    let index: Int
    let title: String

    var id: Int { index }
}

typealias VLCSubtitleTrack = VLCMediaStreamTrack
typealias VLCAudioTrack = VLCMediaStreamTrack

/// Drives SwiftUI transport controls for `MacVLCPlayerView`.
@MainActor
final class MacVLCPlaybackController: ObservableObject {
    @Published private(set) var positionMs = 0
    @Published private(set) var durationMs = 0
    @Published private(set) var isPlaying = false
    @Published var volume = 100
    @Published var isMuted = false

    @Published private(set) var subtitleTracks: [VLCSubtitleTrack] = []
    @Published private(set) var selectedSubtitleIndex: Int = -1
    @Published private(set) var audioTracks: [VLCAudioTrack] = []
    @Published private(set) var selectedAudioIndex: Int = -1
    @Published private(set) var videoDisplaySize: CGSize = .zero
    @Published private(set) var sourceVideoSize: CGSize?
    @Published private(set) var playbackRate: Float = 1.0

    weak var player: VLCMediaPlayer?

    var formattedPosition: String { Self.format(ms: positionMs) }
    var formattedDuration: String { Self.format(ms: durationMs) }

    var formattedVideoResolution: String {
        if videoDisplaySize.width > 0, videoDisplaySize.height > 0 {
            return "\(Int(videoDisplaySize.width))×\(Int(videoDisplaySize.height))"
        }
        if let sourceVideoSize, sourceVideoSize.width > 0, sourceVideoSize.height > 0 {
            return "\(Int(sourceVideoSize.width))×\(Int(sourceVideoSize.height))"
        }
        return "—"
    }

    func setSourceVideoSize(_ size: CGSize?) {
        guard sourceVideoSize != size else { return }
        sourceVideoSize = size
    }

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

    func applySavedPlaybackRate(to player: VLCMediaPlayer) {
        let rate = PlaybackPreferences.loadPlaybackRate()
        player.rate = rate
        playbackRate = rate
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
        PlaybackPreferences.savePlaybackRate(rate)
    }

    func seek(toMs: Int) {
        guard let player else { return }
        let cap = durationMs > 0 ? durationMs : max(toMs, 0)
        let clamped = max(0, min(toMs, cap))
        player.time = VLCTime(number: clamped as NSNumber)
        if durationMs > 0 {
            let fraction = Float(clamped) / Float(durationMs)
            player.position = min(1, max(0, fraction))
        }
        positionMs = clamped
        if !player.isPlaying, player.state != .playing {
            player.play()
        }
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

    func selectSubtitleTrack(index: Int) {
        guard let player else { return }
        player.currentVideoSubTitleIndex = Int32(index)
        selectedSubtitleIndex = index
    }

    func selectAudioTrack(index: Int) {
        guard let player else { return }
        player.currentAudioTrackIndex = Int32(index)
        selectedAudioIndex = index
    }

    /// Called from VLC delegate callbacks — defer to avoid layout recursion with SwiftUI.
    func scheduleSync(from player: VLCMediaPlayer) {
        Task { @MainActor in
            self.applySync(from: player)
        }
    }

    func applySync(from player: VLCMediaPlayer) {
        self.player = player

        let newPosition = Int(player.time.intValue)
        if newPosition != positionMs {
            positionMs = newPosition
        }

        let newDuration = Int(player.media?.length.intValue ?? 0)
        if newDuration != durationMs {
            durationMs = newDuration
        }

        let newIsPlaying = player.isPlaying
        if newIsPlaying != isPlaying {
            isPlaying = newIsPlaying
        }

        if let audio = player.audio {
            let newVolume = Int(audio.volume)
            let newMuted = audio.isMuted
            if newVolume != volume { volume = newVolume }
            if newMuted != isMuted { isMuted = newMuted }
        }

        let size = player.videoSize
        if size.width > 0, size.height > 0, size != videoDisplaySize {
            videoDisplaySize = size
        }

        refreshSubtitleTracks(from: player)
        refreshAudioTracks(from: player)
    }

    func refreshSubtitleTracks(from player: VLCMediaPlayer) {
        let names = player.videoSubTitlesNames as? [String] ?? []
        let indexes = player.videoSubTitlesIndexes as? [NSNumber] ?? []
        var tracks: [VLCSubtitleTrack] = []
        for (name, indexNumber) in zip(names, indexes) {
            let index = indexNumber.intValue
            guard index >= 0 else { continue }
            tracks.append(VLCSubtitleTrack(index: index, title: name))
        }
        if tracks != subtitleTracks {
            subtitleTracks = tracks
        }
        let current = Int(player.currentVideoSubTitleIndex)
        if current != selectedSubtitleIndex {
            selectedSubtitleIndex = current
        }
    }

    func refreshAudioTracks(from player: VLCMediaPlayer) {
        let names = player.audioTrackNames as? [String] ?? []
        let indexes = player.audioTrackIndexes as? [NSNumber] ?? []
        var tracks: [VLCAudioTrack] = []
        for (name, indexNumber) in zip(names, indexes) {
            let index = indexNumber.intValue
            guard index >= 0 else { continue }
            let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = label.isEmpty ? "Track \(index)" : label
            tracks.append(VLCAudioTrack(index: index, title: title))
        }
        if tracks != audioTracks {
            audioTracks = tracks
        }
        let current = Int(player.currentAudioTrackIndex)
        if current != selectedAudioIndex {
            selectedAudioIndex = current
        }
    }

    func applyPreferredSubtitle(from selection: PlaybackSubtitleSelection) {
        switch selection {
        case .off:
            selectSubtitleTrack(index: -1)
        case .auto:
            if let first = subtitleTracks.first {
                selectSubtitleTrack(index: first.index)
            }
        case .plexStream:
            break
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
