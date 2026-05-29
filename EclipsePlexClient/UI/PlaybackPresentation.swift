//
//  PlaybackPresentation.swift
//  EclipsePlexClient
//

import Foundation
import SwiftUI

/// Identifiable wrapper for playback presentation on tvOS.
struct PlaybackPresentationItem: Identifiable, Hashable {
    let request: PlaybackRequest

    var id: String {
        switch request {
        case .plex(let server, let ratingKey, _, _, _, _):
            "plex|\(server.id.uuidString)|\(ratingKey)"
        case .downloadedPlexItem(let server, let ratingKey, _):
            "offline|\(server.id.uuidString)|\(ratingKey)"
        case .remoteStream(let url):
            "stream|\(url.absoluteString)"
        case .localFile(let url):
            "file|\(url.absoluteString)"
        case .bundledDemo:
            "bundledDemo"
        }
    }
}

/// Objects `ContentView` needs inside a sheet / full-screen cover.
/// Passed explicitly because those presentations do not inherit the full
/// environment tree from `RootShellView`.
struct PlaybackCoverDependencies {
    let downloadManager: OfflineDownloadManager
    let focusCoordinator: KeyboardFocusCoordinator
    let plexRegistry: PlexServerRegistry
}

/// Keeps one `ContentView` / VLC instance alive across full-screen and mini modes.
struct PlaybackSessionRoot: View {
    @ObservedObject var presenter: PlaybackPresenter
    let dependencies: PlaybackCoverDependencies

    var body: some View {
        Group {
            if let request = presenter.activeRequest {
                PlaybackCoverHost(
                    request: request,
                    isCompactSession: presenter.presentationMode == .mini,
                    dependencies: dependencies
                )
                .environmentObject(presenter)
                .modifier(PlaybackSessionLayout(mode: presenter.presentationMode))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: presenter.presentationMode)
    }
}

private struct PlaybackSessionLayout: ViewModifier {
    let mode: PlaybackPresentationMode

    func body(content: Content) -> some View {
        switch mode {
        case .fullScreen:
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .zIndex(1000)
#if os(macOS)
                .playbackSuppressesMacWindowTitle(true)
#endif
        case .mini:
            content
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(-1)
        }
    }
}

extension View {
    /// Hides browse chrome while fullscreen playback is on top (avoids bleed-through).
    func browseShellSuppressedForPlayback(_ suppressed: Bool) -> some View {
        opacity(suppressed ? 0 : 1)
            .allowsHitTesting(!suppressed)
            .accessibilityHidden(suppressed)
    }

    /// Presents `ContentView` edge-to-edge on iPhone / iPad (avoids navigation bar layout).
    @ViewBuilder
    func eclipsePlexFullscreenPlayback(
        item: Binding<PlaybackPresentationItem?>,
        dependencies: PlaybackCoverDependencies
    ) -> some View {
#if os(iOS)
        fullScreenCover(item: item) { presented in
            PlaybackCoverHost(
                request: presented.request,
                isCompactSession: false,
                dependencies: dependencies
            )
        }
#else
        self
#endif
    }
}

/// Hosts `ContentView` in a platform presentation with required dependencies wired in.
struct PlaybackCoverHost: View {
    let request: PlaybackRequest
    var isCompactSession = false
    let dependencies: PlaybackCoverDependencies

    var body: some View {
        ContentView(request: request, isCompactSession: isCompactSession)
            .offlineDownloads(dependencies.downloadManager)
            .environmentObject(dependencies.focusCoordinator)
            .environmentObject(dependencies.plexRegistry)
    }
}
