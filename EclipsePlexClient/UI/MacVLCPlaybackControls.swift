#if os(macOS)
import SwiftUI

/// Transport bar for `MacVLCPlaybackController`.
struct MacVLCPlaybackControls: View {
    @ObservedObject var controller: MacVLCPlaybackController
    let playback: ResolvedPlayback
    let canReloadStream: Bool
    var onSubtitleSelection: (PlaybackSubtitleSelection) -> Void
    var onVideoResolution: (PlaybackVideoResolution) -> Void
    var onPlaybackSpeed: (Float) -> Void = { _ in }
    var nextEpisode: PlexEpisodeSummary? = nil
    var previousEpisode: PlexEpisodeSummary? = nil
    var onPlayNext: (() -> Void)? = nil
    var onPlayPrevious: (() -> Void)? = nil
    var onVLCSubtitleTrackSelected: (Int) -> Void
    var onVLCAudioTrackSelected: (Int) -> Void
    var onScrubbingChanged: (Bool) -> Void = { _ in }
    var onInteraction: () -> Void = {}
    var onSettingsEngage: () -> Void = {}
    var sleepTimer: SleepTimerController? = nil

    var body: some View {
        VStack(spacing: 0) {
            MacVLCProgressRow(
                controller: controller,
                tracker: controller.positionTracker,
                onScrubbingChanged: onScrubbingChanged
            )
            transportRow
        }
    }

    private var transportRow: some View {
        HStack(spacing: 16) {
            Button {
                onInteraction()
                controller.skip(by: -10)
            } label: {
                Image(systemName: "gobackward.10")
            }
            .help("Back 10 seconds")

            Button(action: {
                onInteraction()
                controller.togglePlayPause()
            }) {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .help(controller.isPlaying ? "Pause" : "Play")

            Button {
                onInteraction()
                controller.skip(by: 10)
            } label: {
                Image(systemName: "goforward.10")
            }
            .help("Forward 10 seconds")

            if let previous = previousEpisode, let onPlayPrevious {
                Button {
                    onInteraction()
                    onPlayPrevious()
                } label: {
                    Image(systemName: "backward.end.fill")
                }
                .help("Previous episode · S\(previous.seasonNumber)E\(previous.episodeNumber)")
            }

            if let next = nextEpisode, let onPlayNext {
                Button {
                    onInteraction()
                    onPlayNext()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .help("Next episode · S\(next.seasonNumber)E\(next.episodeNumber)")
            }

            Button {
                onInteraction()
                controller.toggleWindowFullScreen()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Enter full screen")

            if let sleepTimer {
                Menu {
                    Button("Off") { sleepTimer.cancel() }
                    Button("15 minutes") { sleepTimer.start(minutes: 15) }
                    Button("30 minutes") { sleepTimer.start(minutes: 30) }
                    Button("End of episode") { sleepTimer.startAfterEpisode() }
                } label: {
                    Image(systemName: "moon.zzz")
                }
                .help("Sleep timer")
            }

            embeddedSubtitleMenu
            audioTrackMenu

            PlaybackSettingsControls(
                playback: playback,
                canReloadStream: canReloadStream,
                onSubtitleSelection: onSubtitleSelection,
                onVideoResolution: onVideoResolution,
                onPlaybackSpeed: onPlaybackSpeed,
                onInteraction: onInteraction,
                onSettingsEngage: onSettingsEngage
            )

            Text(controller.formattedVideoResolution)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .leading)
                .help("Decoded video size")

            Spacer()

            Button(action: {
                onInteraction()
                controller.toggleMute()
            }) {
                Image(systemName: controller.isMuted || controller.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .help(controller.isMuted ? "Unmute" : "Mute")

            Slider(
                value: Binding(
                    get: { Double(controller.volume) },
                    set: {
                        onInteraction()
                        controller.setVolume(Int($0))
                    }
                ),
                in: 0 ... 100
            )
            .frame(width: 100)
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
    }

    @ViewBuilder
    private var embeddedSubtitleMenu: some View {
        if controller.subtitleTracks.isEmpty {
            EmptyView()
        } else {
            Menu {
                Button("Off") { onSettingsEngage(); onInteraction(); onVLCSubtitleTrackSelected(-1) }
                Divider()
                ForEach(controller.subtitleTracks) { track in
                    Button {
                        onSettingsEngage()
                        onInteraction()
                        onVLCSubtitleTrackSelected(track.index)
                    } label: {
                        HStack {
                            Text(track.title)
                            if controller.selectedSubtitleIndex == track.index {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "text.bubble")
            }
            .onTapGesture { onSettingsEngage() }
            .help("Embedded subtitle tracks (direct play)")
        }
    }

    private struct MacVLCProgressRow: View {
        let controller: MacVLCPlaybackController
        @ObservedObject var tracker: MacVLCPositionTracker
        var onScrubbingChanged: (Bool) -> Void

        @State private var scrubberMs: Double = 0
        @State private var isScrubbing = false

        var body: some View {
            HStack(spacing: 10) {
                Text(tracker.formattedPosition)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)

                Slider(
                    value: $scrubberMs,
                    in: 0 ... max(Double(tracker.durationMs), 1),
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        onScrubbingChanged(editing)
                        if !editing {
                            controller.seek(toMs: Int(scrubberMs))
                        }
                    }
                )
                .disabled(tracker.durationMs <= 0)

                Text(tracker.formattedDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
            }
            .padding(.bottom, 10)
            .onChange(of: tracker.positionMs) { _, position in
                if !isScrubbing {
                    scrubberMs = Double(position)
                }
            }
            .onAppear {
                scrubberMs = Double(tracker.positionMs)
            }
        }
    }

    @ViewBuilder
    private var audioTrackMenu: some View {
        if controller.audioTracks.count <= 1 {
            EmptyView()
        } else {
            Menu {
                ForEach(controller.audioTracks) { track in
                    Button {
                        onSettingsEngage()
                        onInteraction()
                        onVLCAudioTrackSelected(track.index)
                    } label: {
                        HStack {
                            Text(track.title)
                            if controller.selectedAudioIndex == track.index {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "waveform")
            }
            .onTapGesture { onSettingsEngage() }
            .help("Audio track")
        }
    }
}
#endif
