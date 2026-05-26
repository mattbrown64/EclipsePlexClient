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

extension View {
    /// Presents `ContentView` edge-to-edge on iPhone / iPad (avoids navigation bar layout).
    @ViewBuilder
    func eclipsePlexFullscreenPlayback(item: Binding<PlaybackPresentationItem?>) -> some View {
#if os(iOS)
        fullScreenCover(item: item) { presented in
            PlaybackCoverHost(request: presented.request)
        }
#else
        self
#endif
    }
}

#if os(iOS) || os(tvOS)
/// Forwards environment objects into the playback full-screen cover.
struct PlaybackCoverHost: View {
    let request: PlaybackRequest
    @EnvironmentObject private var downloadManager: OfflineDownloadManager
    @EnvironmentObject private var focusCoordinator: KeyboardFocusCoordinator

    var body: some View {
        ContentView(request: request)
            .offlineDownloads(downloadManager)
            .environmentObject(focusCoordinator)
    }
}
#endif
