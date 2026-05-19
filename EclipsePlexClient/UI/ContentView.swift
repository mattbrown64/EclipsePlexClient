import SwiftUI

/// Binds sheet presentation to a URL so the player always receives media on macOS.
private struct PlaybackItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    private static let sampleStream = URL(string: "https://vjs.zencdn.net/v/oceans.mp4")!
    private static let bundledResource = (name: "Savior", ext: "mkv")

    @State private var playbackItem: PlaybackItem?
    @State private var playerStatus = "Idle"
    @State private var playerErrorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            if Bundle.main.url(forResource: Self.bundledResource.name, withExtension: Self.bundledResource.ext) != nil {
                Button("Play bundled Savior.mkv") {
                    openBundledVideo()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Video 'Savior.mkv' not found in project bundle.")
                    .foregroundStyle(.red)
            }

            Button("Play test stream (HTTP)") {
                presentPlayer(url: Self.sampleStream)
            }
            .buttonStyle(.bordered)

            if let playerErrorMessage, playbackItem == nil {
                Text(playerErrorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .fullScreenCover(item: $playbackItem, onDismiss: resetPlayerState) { item in
            PlaybackSheetView(
                url: item.url,
                statusText: $playerStatus,
                errorMessage: $playerErrorMessage,
                onClose: { playbackItem = nil }
            )
        }
        #else
        .sheet(item: $playbackItem, onDismiss: resetPlayerState) { item in
            PlaybackSheetView(
                url: item.url,
                statusText: $playerStatus,
                errorMessage: $playerErrorMessage,
                onClose: { playbackItem = nil }
            )
        }
        #endif
    }

    private func presentPlayer(url: URL) {
        playerErrorMessage = nil
        playerStatus = "Opening…"
        playbackItem = PlaybackItem(url: url)
    }

    private func openBundledVideo() {
        guard let bundleURL = Bundle.main.url(
            forResource: Self.bundledResource.name,
            withExtension: Self.bundledResource.ext
        ) else { return }
        do {
            let url = try LocalMediaURL.forPlayback(bundleURL)
            presentPlayer(url: url)
        } catch {
            playerErrorMessage = error.localizedDescription
        }
    }

    private func resetPlayerState() {
        playerStatus = "Idle"
    }
}

// MARK: - Player sheet

private struct PlaybackSheetView: View {
    let url: URL
    @Binding var statusText: String
    @Binding var errorMessage: String?
    let onClose: () -> Void

    #if os(macOS)
    @StateObject private var vlcController = MacVLCPlaybackController()
    #endif

    var body: some View {
        Group {
            #if os(macOS)
            MacVLCPlayerView(
                url: url,
                controller: vlcController,
                statusText: $statusText,
                errorMessage: $errorMessage
            )
            #else
            VLCVideoPlayer(configuration: .init(url: url))
                .onStateUpdated { state, _ in
                    statusText = state.label
                    if state == .error {
                        errorMessage = "VLC could not play this file."
                    }
                }
            #endif
        }
        .frame(minWidth: 960, minHeight: 540)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .overlay(alignment: .bottom) {
            MacVLCPlaybackControls(controller: vlcController, onClose: onClose)
        }
        #else
        .overlay(alignment: .top) {
            iosPlayerChrome
        }
        #endif
        .overlay {
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .background(.black)
        .onAppear {
            if statusText == "Idle" {
                statusText = "Opening…"
            }
        }
    }

    #if !os(macOS)
    private var iosPlayerChrome: some View {
        VStack {
            HStack {
                Button("Close", action: onClose)
                    .buttonStyle(.bordered)
                Spacer()
                Text(statusText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding()
            Spacer()
        }
    }
    #endif
}

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
    ContentView()
}
