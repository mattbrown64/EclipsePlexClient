//
//  LiveTVBrowseView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Spike UI: list tuners and channels when the server exposes Live TV.
struct LiveTVBrowseView: View {
    let plexServer: PlexServer

    @State private var tuners: [PlexLiveTVTuner]?
    @State private var channels: [PlexLiveTVChannel]?
    @State private var selectedTunerKey: String?
    @State private var loadError: String?

    var body: some View {
        Group {
            if tuners == nil, loadError == nil {
                ProgressView("Checking Live TV…")
            } else if let loadError {
                ContentUnavailableView(
                    "Live TV unavailable",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text(loadError)
                )
            } else if let tuners, tuners.isEmpty {
                ContentUnavailableView(
                    "No tuners",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("This server does not expose Live TV / DVR tuners.")
                )
            } else if let tuners, !tuners.isEmpty {
                List {
                    if tuners.count > 1 {
                        Section("Tuner") {
                            Picker("Tuner", selection: $selectedTunerKey) {
                                ForEach(tuners) { tuner in
                                    Text(tuner.title).tag(Optional(tuner.key))
                                }
                            }
                            .onChange(of: selectedTunerKey) { _, key in
                                if let key { Task { await loadChannels(tunerKey: key) } }
                            }
                        }
                    }
                    Section("Channels") {
                        if let channels, !channels.isEmpty {
                            ForEach(channels) { channel in
                                HStack(spacing: 12) {
                                    CatalogArtworkImage(
                                        plexServer: plexServer,
                                        thumbPath: channel.thumbPath,
                                        style: .list
                                    )
                                    Text(channel.title)
                                }
                            }
                        } else {
                            Text("Select a tuner or add a DVR in Plex.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Live TV")
        .task { await loadTuners() }
    }

    @MainActor
    private func loadTuners() async {
        loadError = nil
        guard plexServer.usesLivePlexAPI else {
            tuners = []
            return
        }
        do {
            let client = try PlexMediaServerClient(server: plexServer.withActiveConnection())
            let list = try await client.fetchLiveTVTuners()
            tuners = list
            if selectedTunerKey == nil, let first = list.first {
                selectedTunerKey = first.key
                await loadChannels(tunerKey: first.key)
            }
        } catch {
            loadError = error.localizedDescription
            tuners = []
        }
    }

    @MainActor
    private func loadChannels(tunerKey: String) async {
        do {
            let client = try PlexMediaServerClient(server: plexServer.withActiveConnection())
            channels = try await client.fetchLiveTVChannels(tunerKey: tunerKey)
        } catch {
            channels = []
        }
    }
}
