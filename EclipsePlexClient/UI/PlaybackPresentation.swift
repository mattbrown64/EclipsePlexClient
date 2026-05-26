//
//  PlaybackPresentation.swift
//  EclipsePlexClient
//

import SwiftUI

/// Identifiable wrapper for `fullScreenCover` playback on iOS.
struct PlaybackPresentationItem: Identifiable, Hashable {
    let request: PlaybackRequest

    var id: String {
        switch request {
        case .plex(let server, let ratingKey, _, _):
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

extension View {
    /// Presents `ContentView` edge-to-edge on iPhone / iPad (avoids navigation bar layout).
    @ViewBuilder
    func eclipsePlexFullscreenPlayback(
        item: Binding<PlaybackPresentationItem?>,
        dependencies: PlaybackCoverDependencies
    ) -> some View {
#if os(iOS)
        fullScreenCover(item: item) { presented in
            PlaybackCoverHost(request: presented.request, dependencies: dependencies)
        }
#else
        self
#endif
    }
}

/// Hosts `ContentView` in a platform presentation with required dependencies wired in.
struct PlaybackCoverHost: View {
    let request: PlaybackRequest
    let dependencies: PlaybackCoverDependencies

    var body: some View {
        ContentView(request: request)
            .offlineDownloads(dependencies.downloadManager)
            .environmentObject(dependencies.focusCoordinator)
            .environmentObject(dependencies.plexRegistry)
    }
}
