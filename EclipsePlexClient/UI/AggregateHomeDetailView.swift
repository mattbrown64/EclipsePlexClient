//
//  AggregateHomeDetailView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Home across all Plex servers (Continue Watching + Recently Added per server).
struct AggregateHomeDetailView: View {
    let plexServers: [PlexServer]
    let librariesByServerID: [UUID: [PlexLibrary]]
    var onAddPlexServer: () -> Void = {}
    var onSelectServer: (UUID) -> Void = { _ in }

    @EnvironmentObject private var plexRegistry: PlexServerRegistry
    @State private var shelves: [AggregateHomeShelf] = []
    @State private var isLoading = false
    @State private var loadGeneration = 0

    @Environment(\.catalogNavigationActions) private var catalogNavigation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EclipsePlexBrandingHeader(layout: .hero, subtitle: "All servers")

                if isLoading, shelves.isEmpty {
                    ProgressView("Loading from Plex…")
                        .frame(maxWidth: .infinity)
                }

                ForEach(shelves, id: \.server.id) { shelf in
                    serverShelf(shelf)
                }

                if plexServers.isEmpty {
                    Text("Add a Plex server to see Continue Watching and Recently Added.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if !isLoading, shelves.isEmpty {
                    Text("Loading libraries from your Plex servers…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if !isLoading, shelves.allSatisfy({ $0.continueWatching.isEmpty && $0.recentlyAdded.isEmpty && $0.errorMessage == nil }) {
                    Text("No continue watching or recently added items right now. Try refreshing or open a server’s Home.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button(action: onAddPlexServer) {
                    Label("Add Plex Server", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Home")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .browseMenuToolbar()
        .refreshable {
            await reloadShelves(invalidateCache: true)
        }
        .task(id: reloadTaskKey) {
            await reloadShelves(invalidateCache: false)
        }
    }

    private var reloadTaskKey: String {
        plexServers.map { server in
            let count = plexRegistry.librariesByServerID[server.id]?.count ?? 0
            return "\(server.id.uuidString):\(count)"
        }.joined(separator: "|")
    }

    @ViewBuilder
    private func serverShelf(_ shelf: AggregateHomeShelf) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.server.name)
                .font(.title3.weight(.semibold))

            if let error = shelf.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            AggregateHubRowView(
                title: "Continue Watching",
                hits: shelf.continueWatching,
                plexServer: shelf.server,
                onSelectServer: onSelectServer
            )
            AggregateHubRowView(
                title: "Recently Added",
                hits: shelf.recentlyAdded,
                plexServer: shelf.server,
                onSelectServer: onSelectServer
            )
        }
    }

    @MainActor
    private func reloadShelves(invalidateCache: Bool) async {
        loadGeneration += 1
        let generation = loadGeneration
        if invalidateCache {
            await AggregateHomeHubService.invalidateAll()
        }
        for server in plexServers where server.usesLivePlexAPI {
            await plexRegistry.refreshLibraries(for: server)
        }
        isLoading = true
        defer { isLoading = false }
        let loaded = await AggregateHomeHubService.load(
            servers: plexServers,
            librariesByServerID: plexRegistry.librariesByServerID
        )
        guard generation == loadGeneration else { return }
        shelves = loaded
    }
}

/// Hub row that selects the hit's server before navigating.
private struct AggregateHubRowView: View {
    let title: String
    let hits: [PlexCatalogSearchHit]
    let plexServer: PlexServer
    var onSelectServer: (UUID) -> Void

    @Environment(\.catalogNavigationActions) private var catalogNavigation

    var body: some View {
        if hits.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(hits) { hit in
                            Button {
                                onSelectServer(plexServer.id)
                                catalogNavigation.selectLibrary(hit.library)
                                catalogNavigation.pushRoute(hubRoute(for: hit))
                            } label: {
                                HubTileView(plexServer: plexServer, hit: hit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func hubRoute(for hit: PlexCatalogSearchHit) -> CatalogNavigationRoute {
        switch hit.node {
        case .show(let show):
            return .showDetail(library: hit.library, show: show)
        case .season(let season):
            return .browse(
                library: hit.library,
                parent: .season(ratingKey: season.ratingKey),
                navigationTitle: season.title
            )
        case .movie, .episode, .musicTrack:
            return .media(library: hit.library, node: hit.node)
        }
    }
}
