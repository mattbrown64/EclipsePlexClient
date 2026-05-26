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
    private func playbackPresentationBinding(for presenter: PlaybackPresenter) -> Binding<PlaybackPresentationItem?> {
        Binding(
            get: {
                presenter.activeRequest.map { PlaybackPresentationItem(request: $0) }
            },
            set: { item in
                presenter.activeRequest = item?.request
            }
        )
    }

    /// Platform-appropriate playback presentation for `ContentView`.
    @ViewBuilder
    func attachPlaybackPresenter(
        _ presenter: PlaybackPresenter,
        dependencies: PlaybackCoverDependencies
    ) -> some View {
#if os(iOS) || os(tvOS)
        fullScreenCover(item: playbackPresentationBinding(for: presenter)) { item in
            PlaybackCoverHost(request: item.request, dependencies: dependencies)
        }
#elseif os(macOS)
        sheet(item: playbackPresentationBinding(for: presenter)) { item in
            PlaybackCoverHost(request: item.request, dependencies: dependencies)
                .frame(minWidth: 900, minHeight: 560)
        }
#else
        self
#endif
    }
}
