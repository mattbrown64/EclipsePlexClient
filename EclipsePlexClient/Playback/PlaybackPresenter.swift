//
//  PlaybackPresenter.swift
//  EclipsePlexClient
//

import SwiftUI
import Combine

@MainActor
final class PlaybackPresenter: ObservableObject {
    @Published var activeRequest: PlaybackRequest?

    func present(_ request: PlaybackRequest) {
        activeRequest = request
    }

    func dismiss() {
        activeRequest = nil
    }
}

extension View {
    /// Platform-appropriate playback presentation for `ContentView`.
    @ViewBuilder
    func attachPlaybackPresenter(_ presenter: PlaybackPresenter) -> some View {
#if os(iOS) || os(tvOS)
        fullScreenCover(item: Binding(
            get: {
                presenter.activeRequest.map { PlaybackPresentationItem(request: $0) }
            },
            set: { item in
                presenter.activeRequest = item?.request
            }
        )) { item in
            PlaybackCoverHost(request: item.request)
        }
#elseif os(macOS)
        self
#else
        self
#endif
    }
}

