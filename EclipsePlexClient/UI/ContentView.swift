import SwiftUI

/// Full-screen video playback driven by `PlaybackRequest` (Plex, local file, or bundled demo).
struct ContentView: View {
    var request: PlaybackRequest?

    @Environment(\.dismiss) private var dismiss

    @State private var resolvedPlayback: ResolvedPlayback?
    @State private var loadError: String?
    @State private var loadingMessage = "Preparing playback…"

    var body: some View {
        Group {
            if let resolvedPlayback {
                VideoPlaybackView(
                    playback: resolvedPlayback,
                    onDone: { dismiss() }
                )
            } else if let loadError {
                errorView(message: loadError)
            } else {
                ProgressView(loadingMessage)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Done", action: { dismiss() })
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .navigationTitle(request?.displayTitle ?? "Playback")
        .task(id: request) {
            await resolvePlaybackURL()
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("Cannot Play", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
            Button("Done", action: { dismiss() })
                .buttonStyle(.bordered)
        }
    }

    @MainActor
    private func resolvePlaybackURL() async {
        loadError = nil
        resolvedPlayback = nil

        let activeRequest = request ?? .bundledDemo

        switch activeRequest {
        case .plex:
            loadingMessage = "Loading from Plex…"
        case .remoteStream:
            loadingMessage = "Opening stream…"
        case .localFile:
            loadingMessage = "Opening file…"
        case .bundledDemo:
            loadingMessage = "Preparing video…"
        }

        NSLog("[EclipsePlex] ContentView preparing playback…")
        do {
            if case .plex = activeRequest {
                loadingMessage = "Reading Plex metadata…"
            }
            resolvedPlayback = try await PlaybackResolver.resolve(activeRequest)
            NSLog("[EclipsePlex] ContentView playback URL ready")
        } catch {
            NSLog("[EclipsePlex] ContentView playback failed: %@", error.localizedDescription)
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Inline player

private struct VideoPlaybackView: View {
    let playback: ResolvedPlayback
    let onDone: () -> Void

    #if os(macOS)
    @StateObject private var vlcController = MacVLCPlaybackController()
    #else
    @StateObject private var vlcProxy = VLCVideoPlayer.Proxy()
    @State private var positionMs = 0
    @State private var durationMs = 0
    @State private var isPlaying = false
    #endif

    @State private var statusText = "Opening…"
    @State private var playerErrorMessage: String?

    var body: some View {
        Group {
            #if os(macOS)
            MacVLCPlayerView(
                url: playback.url,
                streamKind: playback.streamKind,
                httpHeaderFields: playback.httpHeaderFields,
                controller: vlcController,
                statusText: $statusText,
                errorMessage: $playerErrorMessage
            )
            #else
            VLCVideoPlayer(configuration: .init(url: playback.url, autoPlay: true))
                .proxy(vlcProxy)
                .onTicksUpdated { ticks, info in
                    positionMs = ticks
                    durationMs = info.length
                }
                .onStateUpdated { state, _ in
                    statusText = state.label
                    isPlaying = state == .playing
                    if state == .error {
                        playerErrorMessage = "VLC could not play this file."
                    }
                }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            Button(action: onDone) {
                Label("Done", systemImage: "chevron.backward")
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding()
        }
        #if os(macOS)
        .overlay(alignment: .bottom) {
            MacVLCPlaybackControls(controller: vlcController, onClose: onDone)
        }
        #else
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                IOSVLCPlaybackControls(
                    proxy: vlcProxy,
                    positionMs: $positionMs,
                    durationMs: durationMs,
                    isPlaying: isPlaying,
                    onPlayPause: togglePlayPause
                )
                Button("Done", action: onDone)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
            }
        }
        #endif
        .overlay {
            if let playerErrorMessage {
                VStack(spacing: 12) {
                    Text(playerErrorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("Done", action: onDone)
                        .buttonStyle(.bordered)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .background(.black)
    }

    #if !os(macOS)
    private func togglePlayPause() {
        if isPlaying {
            vlcProxy.pause()
        } else {
            vlcProxy.play()
        }
    }
    #endif
}

#if os(iOS)
/// Transport bar for VLCUI on iOS (mirrors macOS controls).
private struct IOSVLCPlaybackControls: View {
    @ObservedObject var proxy: VLCVideoPlayer.Proxy
    @Binding var positionMs: Int
    let durationMs: Int
    let isPlaying: Bool
    let onPlayPause: () -> Void

    @State private var scrubberMs: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(format(ms: positionMs))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)

                Slider(
                    value: $scrubberMs,
                    in: 0 ... max(Double(durationMs), 1),
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing {
                            proxy.setTime(.ticks(Int(scrubberMs)))
                        }
                    }
                )
                .disabled(durationMs <= 0)

                Text(format(ms: durationMs))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
            }

            HStack(spacing: 20) {
                Button { proxy.jumpBackward(10) } label: {
                    Image(systemName: "gobackward.10")
                }
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                Button { proxy.jumpForward(10) } label: {
                    Image(systemName: "goforward.10")
                }
            }
            .buttonStyle(.plain)
            .labelStyle(.iconOnly)
        }
        .padding()
        .background(.ultraThinMaterial)
        .onChange(of: positionMs) { _, position in
            if !isScrubbing {
                scrubberMs = Double(position)
            }
        }
        .onAppear {
            scrubberMs = Double(positionMs)
        }
    }

    private func format(ms: Int) -> String {
        guard ms > 0 else { return "0:00" }
        let s = ms / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
#endif

#if !os(macOS)
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

#Preview {
    NavigationStack {
        ContentView()
    }
}
