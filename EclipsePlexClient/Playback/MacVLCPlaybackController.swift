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

/// High-frequency position updates for the Mac transport bar.
///
/// Lives on its own `ObservableObject` so that the per-tick position publishes
/// (≈2 Hz during playback) don't re-render every consumer of
/// `MacVLCPlaybackController`. Only the progress row subview subscribes here.
@MainActor
final class MacVLCPositionTracker: ObservableObject {
    @Published fileprivate(set) var positionMs = 0
    @Published fileprivate(set) var durationMs = 0

    var formattedPosition: String { MacVLCPlaybackController.format(ms: positionMs) }
    var formattedDuration: String { MacVLCPlaybackController.format(ms: durationMs) }
}

/// Drives SwiftUI transport controls for `MacVLCPlayerView`.
@MainActor
final class MacVLCPlaybackController: ObservableObject {
    /// Position/duration are published from a dedicated tracker so the rest of
    /// the transport bar (buttons, menus, volume) doesn't re-render twice a
    /// second during playback.
    let positionTracker = MacVLCPositionTracker()

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
    weak var hostWindow: NSWindow?

    func toggleWindowFullScreen() {
        hostWindow?.toggleFullScreen(nil)
    }

    var positionMs: Int { positionTracker.positionMs }
    var durationMs: Int { positionTracker.durationMs }

    var formattedPosition: String { positionTracker.formattedPosition }
    var formattedDuration: String { positionTracker.formattedDuration }

    /// Cheap fingerprint of the VLC track lists used to avoid re-bridging the
    /// Obj-C arrays on every applySync. Recomputed only when VLC reports a
    /// change to track count / current index.
    private var lastSubtitleSignature: String?
    private var lastAudioSignature: String?

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
        let duration = positionTracker.durationMs
        let cap = duration > 0 ? duration : max(toMs, 0)
        let clamped = max(0, min(toMs, cap))
        player.time = VLCTime(number: clamped as NSNumber)
        if duration > 0 {
            let fraction = Float(clamped) / Float(duration)
            player.position = min(1, max(0, fraction))
        }
        positionTracker.positionMs = clamped
        if !player.isPlaying, player.state != .playing {
            player.play()
        }
    }

    func skip(by seconds: Int) {
        seek(toMs: positionTracker.positionMs + seconds * 1_000)
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
        if newPosition != positionTracker.positionMs {
            positionTracker.positionMs = newPosition
        }

        let newDuration = Int(player.media?.length.intValue ?? 0)
        if newDuration != positionTracker.durationMs {
            positionTracker.durationMs = newDuration
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

        refreshSubtitleTracksIfChanged(from: player)
        refreshAudioTracksIfChanged(from: player)
    }

    /// Re-bridges VLC's Obj-C track arrays only when a cheap fingerprint
    /// (count + current index) tells us something changed. Previously this ran
    /// every applySync (~2 Hz), allocating new Swift arrays each tick.
    private func refreshSubtitleTracksIfChanged(from player: VLCMediaPlayer) {
        let currentIndex = Int(player.currentVideoSubTitleIndex)
        let signature = "\(player.numberOfSubtitlesTracks)|\(currentIndex)"
        guard signature != lastSubtitleSignature else { return }
        lastSubtitleSignature = signature
        refreshSubtitleTracks(from: player)
    }

    private func refreshAudioTracksIfChanged(from player: VLCMediaPlayer) {
        let currentIndex = Int(player.currentAudioTrackIndex)
        let signature = "\(player.numberOfAudioTracks)|\(currentIndex)"
        guard signature != lastAudioSignature else { return }
        lastAudioSignature = signature
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
            if let preferred = PlaybackPreferences.preferredSubtitleLanguage,
               let track = subtitleTracks.first(where: { Self.matchesLanguage($0.title, preferred) }) {
                selectSubtitleTrack(index: track.index)
            } else if let first = subtitleTracks.first {
                selectSubtitleTrack(index: first.index)
            }
        case .plexStream:
            break
        }
    }

    func applyPreferredAudioLanguageIfNeeded() {
        guard let preferred = PlaybackPreferences.preferredAudioLanguage,
              let track = audioTracks.first(where: { Self.matchesLanguage($0.title, preferred) })
        else { return }
        selectAudioTrack(index: track.index)
    }

    private static func matchesLanguage(_ trackTitle: String, _ preferred: String) -> Bool {
        let norm = preferred.lowercased()
        let title = trackTitle.lowercased()
        if title.contains(norm) { return true }
        if norm.count == 2 || norm.count == 3 {
            return title.contains("[\(norm)]") || title.hasPrefix("\(norm) ")
        }
        return false
    }

    static func format(ms: Int) -> String {
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
