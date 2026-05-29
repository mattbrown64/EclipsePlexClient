//
//  PseudoTVChannelsView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Virtual broadcast channels (Pseudo-TV) for a Plex server.
struct PseudoTVChannelsView: View {
    let plexServer: PlexServer

    @EnvironmentObject private var registry: PlexServerRegistry
    @EnvironmentObject private var playbackPresenter: PlaybackPresenter
    @StateObject private var coordinator: PseudoTVCoordinator

    init(plexServer: PlexServer, registry: PlexServerRegistry) {
        self.plexServer = plexServer
        _coordinator = StateObject(wrappedValue: PseudoTVCoordinator(server: plexServer, registry: registry))
    }

    var body: some View {
        Group {
            if coordinator.isLoading, coordinator.channels.isEmpty {
                ProgressView("Building channels…")
            } else if let error = coordinator.errorMessage, coordinator.channels.isEmpty {
                ContentUnavailableView("Pseudo-TV unavailable", systemImage: "tv", description: Text(error))
            } else if coordinator.channels.isEmpty {
                ContentUnavailableView(
                    "No channels yet",
                    systemImage: "tv",
                    description: Text("Refresh to generate channels from your libraries.")
                )
            } else {
                channelList
            }
        }
        .navigationTitle("TV Channels")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") {
                    Task { await coordinator.refreshAll(force: true) }
                }
                .disabled(coordinator.isLoading)
            }
        }
        .task {
            if coordinator.channels.isEmpty {
                await coordinator.refreshAll()
            }
        }
    }

    private var channelList: some View {
        List(coordinator.channels) { channel in
            VStack(alignment: .leading, spacing: 8) {
                Text(channel.name)
                    .font(.headline)
                if let info = coordinator.nowPlaying(for: channel),
                   let current = info.current {
                    Text(nowPlayingLine(current: current, offsetMs: info.offsetMs))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let next = info.upNext {
                        Text("Up next: \(next.program.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        tuneIn(channel)
                    } label: {
                        Label("Watch now", systemImage: "play.tv")
                    }
                    .buttonStyle(.pressableBorderedProminent)
                } else {
                    Text("Schedule loading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func nowPlayingLine(current: PseudoTVSlot, offsetMs: Int) -> String {
        let pos = MacVLCPlaybackController.format(ms: offsetMs)
        let dur = MacVLCPlaybackController.format(ms: current.program.durationMs)
        return "On now: \(current.program.title) (\(pos) / \(dur))"
    }

    private func tuneIn(_ channel: PseudoTVChannel) {
        guard let request = coordinator.tuneIn(for: channel) else { return }
        playbackPresenter.present(request)
    }
}
