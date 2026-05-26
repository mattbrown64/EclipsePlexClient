import SwiftUI

#if os(macOS)
/// Subtitle and quality menus shared by macOS VLC transport bar.
struct PlaybackSettingsControls: View {
    let playback: ResolvedPlayback
    let canReloadStream: Bool
    var onSubtitleSelection: (PlaybackSubtitleSelection) -> Void
    var onVideoResolution: (PlaybackVideoResolution) -> Void
    var onPlaybackSpeed: (Float) -> Void = { _ in }
    var onInteraction: () -> Void = {}
    var onSettingsEngage: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            subtitleMenu
            speedMenu
            qualityMenu
        }
    }

    private var speedMenu: some View {
        Menu {
            ForEach(PlaybackSpeed.allCases) { speed in
                Button {
                    onSettingsEngage()
                    onInteraction()
                    onPlaybackSpeed(speed.rawValue)
                } label: {
                    HStack {
                        Text(speed.menuTitle)
                        if abs(PlaybackPreferences.loadPlaybackRate() - speed.rawValue) < 0.01 {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(PlaybackSpeed.nearest(to: PlaybackPreferences.loadPlaybackRate()).menuTitle, systemImage: "gauge.with.dots.needle.67percent")
        }
        .onTapGesture { onSettingsEngage() }
        .help("Playback speed")
    }

    private var subtitleMenu: some View {
        Menu {
            Button("Off") { onSettingsEngage(); onInteraction(); onSubtitleSelection(.off) }
            Button("Auto") { onSettingsEngage(); onInteraction(); onSubtitleSelection(.auto) }
            if !playback.plexSubtitleStreams.isEmpty {
                Divider()
                ForEach(playback.plexSubtitleStreams) { stream in
                    Button(stream.displayName) {
                        onSettingsEngage()
                        onInteraction()
                        onSubtitleSelection(.plexStream(id: stream.id, displayName: stream.displayName))
                    }
                }
            }
            if !playback.plexSubtitleStreams.isEmpty || canReloadStream {
                Divider()
            }
            Text("Embedded tracks (direct play)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } label: {
            Label("Subtitles", systemImage: "captions.bubble")
        }
        .onTapGesture { onSettingsEngage() }
        .help("Subtitle source for Plex transcode, or embedded tracks during direct play")
    }

    private var qualityMenu: some View {
        Menu {
            ForEach(PlaybackVideoResolution.allCases) { resolution in
                Button {
                    onSettingsEngage()
                    onInteraction()
                    onVideoResolution(resolution)
                } label: {
                    HStack {
                        Text(resolution.menuTitle)
                        if playback.streamOptions.videoResolution == resolution {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(playback.streamOptions.videoResolution.menuTitle, systemImage: "tv")
        }
        .onTapGesture { onSettingsEngage() }
        .help("Transcode fallback quality — direct play is tried first; changing quality restarts playback")
    }
}
#endif

#if os(iOS) || os(tvOS)
struct PlaybackSettingsControls: View {
    let playback: ResolvedPlayback
    let canReloadStream: Bool
    var onSubtitleSelection: (PlaybackSubtitleSelection) -> Void
    var onVideoResolution: (PlaybackVideoResolution) -> Void
    var onPlaybackSpeed: (Float) -> Void = { _ in }
    var onInteraction: () -> Void = {}
    var onSettingsEngage: () -> Void = {}

    var body: some View {
        HStack(spacing: 16) {
            subtitleMenu
            speedMenu
            qualityMenu
        }
    }

    private var speedMenu: some View {
        Menu {
            ForEach(PlaybackSpeed.allCases) { speed in
                Button {
                    onSettingsEngage()
                    onInteraction()
                    onPlaybackSpeed(speed.rawValue)
                } label: {
                    Text(speed.menuTitle)
                }
            }
        } label: {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .padding(8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .simultaneousGesture(TapGesture().onEnded { onInteraction() })
    }

    private var subtitleMenu: some View {
        Menu {
            Button("Off") { onSettingsEngage(); onInteraction(); onSubtitleSelection(.off) }
            Button("Auto") { onSettingsEngage(); onInteraction(); onSubtitleSelection(.auto) }
            ForEach(playback.plexSubtitleStreams) { stream in
                Button(stream.displayName) {
                    onInteraction()
                    onSubtitleSelection(.plexStream(id: stream.id, displayName: stream.displayName))
                }
            }
        } label: {
            Image(systemName: "captions.bubble")
                .padding(8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .simultaneousGesture(TapGesture().onEnded { onInteraction() })
    }

    private var qualityMenu: some View {
        Menu {
            ForEach(PlaybackVideoResolution.allCases) { resolution in
                Button(resolution.menuTitle) {
                    onSettingsEngage()
                    onInteraction()
                    onVideoResolution(resolution)
                }
            }
        } label: {
            Image(systemName: "tv")
                .padding(8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .simultaneousGesture(TapGesture().onEnded { onSettingsEngage(); onInteraction() })
    }
}
#endif
