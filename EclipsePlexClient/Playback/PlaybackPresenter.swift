//
//  PlaybackPresenter.swift
//  EclipsePlexClient
//

import SwiftUI
import Combine

#if os(macOS)
import VLCKit
#elseif os(tvOS)
import TVVLCKit
#elseif canImport(MobileVLCKit)
import MobileVLCKit
#endif

enum PlaybackPresentationMode: Equatable {
    case fullScreen
    case mini
}

/// Global playback session: what is playing, how it is presented, and shared VLC controls.
@MainActor
final class PlaybackPresenter: ObservableObject {
    @Published private(set) var activeRequest: PlaybackRequest?
    @Published private(set) var presentationMode: PlaybackPresentationMode = .fullScreen

    @Published private(set) var sessionTitle: String?
    @Published private(set) var positionMs = 0
    @Published private(set) var durationMs = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var activePlayback: ResolvedPlayback?

    var hasActiveSession: Bool { activeRequest != nil }

    func setActivePlayback(_ playback: ResolvedPlayback?) {
        activePlayback = playback
    }

    #if os(iOS) || os(tvOS)
    let vlcProxy = VLCVideoPlayer.Proxy()
    #elseif os(macOS)
    let macController = MacVLCPlaybackController()
    #endif

    func present(_ request: PlaybackRequest) {
        activeRequest = request
        presentationMode = .fullScreen
        sessionTitle = request.displayTitle
        positionMs = 0
        durationMs = 0
        isPlaying = false
        #if os(iOS)
        PlaybackOrientationLock.enterPlayback()
        #endif
    }

    func replaceRequest(_ request: PlaybackRequest) {
        activeRequest = request
        sessionTitle = request.displayTitle
    }

    func minimize() {
        guard activeRequest != nil else { return }
        presentationMode = .mini
    }

    func expand() {
        guard activeRequest != nil else { return }
        presentationMode = .fullScreen
    }

    func stop() {
        let requestForScrobble = activeRequest
        let finalPositionMs = positionMs
        let finalDurationMs = durationMs
        Task {
            await PlaybackScrobbleReporter.reportSessionEnd(
                request: requestForScrobble,
                positionMs: finalPositionMs,
                durationMs: finalDurationMs
            )
        }
        activeRequest = nil
        presentationMode = .fullScreen
        sessionTitle = nil
        positionMs = 0
        durationMs = 0
        isPlaying = false
        activePlayback = nil
        #if os(iOS)
        PlaybackOrientationLock.exitPlayback()
        #endif
        PlaybackNowPlayingController.shared.endSession()
    }

    /// Backward-compatible alias for stopping playback.
    func dismiss() {
        stop()
    }

    func updateTransport(title: String?, positionMs: Int, durationMs: Int, isPlaying: Bool) {
        if let title {
            sessionTitle = title
        }
        self.positionMs = positionMs
        self.durationMs = durationMs
        self.isPlaying = isPlaying

        PlaybackNowPlayingController.shared.update(
            title: sessionTitle,
            positionMs: positionMs,
            durationMs: durationMs,
            isPlaying: isPlaying
        )
    }

    func togglePlayPause() {
        #if os(macOS)
        macController.togglePlayPause()
        #else
        if isPlaying {
            vlcProxy.pause()
        } else {
            vlcProxy.play()
        }
        #endif
    }

    func seekBy(seconds: Int) {
        #if os(macOS)
        let target = max(0, macController.positionMs + seconds * 1000)
        macController.seek(toMs: target)
        #else
        if seconds >= 0 {
            vlcProxy.jumpForward(seconds)
        } else {
            vlcProxy.jumpBackward(-seconds)
        }
        #endif
    }

}

extension View {
    private func playbackPresentationBinding(for presenter: PlaybackPresenter) -> Binding<PlaybackPresentationItem?> {
        Binding(
            get: {
                presenter.activeRequest.map { PlaybackPresentationItem(request: $0) }
            },
            set: { item in
                if item == nil {
                    presenter.stop()
                }
            }
        )
    }

    /// Presents playback above browse UI while keeping the session alive when minimized.
    @ViewBuilder
    func attachPlaybackPresenter(
        _ presenter: PlaybackPresenter,
        dependencies: PlaybackCoverDependencies
    ) -> some View {
#if os(tvOS)
        fullScreenCover(item: playbackPresentationBinding(for: presenter)) { item in
            PlaybackCoverHost(request: item.request, dependencies: dependencies)
        }
#else
        overlay {
            ZStack {
                if presenter.hasActiveSession, presenter.presentationMode == .fullScreen {
                    Color.black
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
                PlaybackSessionRoot(presenter: presenter, dependencies: dependencies)
            }
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if presenter.hasActiveSession, presenter.presentationMode == .mini {
                MiniPlayerBar(presenter: presenter)
            }
        }
#endif
    }
}
