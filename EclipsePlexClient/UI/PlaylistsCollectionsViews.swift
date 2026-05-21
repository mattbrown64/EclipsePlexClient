//
//  PlaylistsCollectionsViews.swift
//  EclipsePlexClient
//

import SwiftUI

/// Server-wide Plex playlists.
struct ServerPlaylistsView: View {
    let plexServer: PlexServer

    @State private var playlists: [PlexPlaylistSummary]?
    @State private var loadError: String?

    @Environment(\.catalogNavigationActions) private var navigationActions

    var body: some View {
        Group {
            if playlists == nil, loadError == nil {
                ProgressView("Loading playlists…")
            } else if let loadError {
                ContentUnavailableView("Couldn't load playlists", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if let playlists, playlists.isEmpty {
                ContentUnavailableView("No playlists", systemImage: "music.note.list", description: Text("This server has no video playlists yet."))
            } else if let playlists {
                List(playlists) { playlist in
                    Button {
                        navigationActions.pushRoute(
                            .playlistItems(playlistKey: playlist.ratingKey, title: playlist.title)
                        )
                    } label: {
                        HStack(spacing: 12) {
                            CatalogArtworkImage(
                                plexServer: plexServer,
                                thumbPath: playlist.thumbPath,
                                style: .list
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.title)
                                if let summary = playlist.summary, !summary.isEmpty {
                                    Text(summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Playlists")
        .task { await reload() }
        .refreshable { await reload() }
    }

    @MainActor
    private func reload() async {
        loadError = nil
        guard plexServer.usesLivePlexAPI else {
            playlists = []
            return
        }
        do {
            let client = try PlexMediaServerClient(server: plexServer)
            playlists = try await client.fetchPlaylists()
        } catch {
            loadError = error.localizedDescription
            playlists = []
        }
    }
}

/// Collections in a movie/TV library section.
struct LibraryCollectionsView: View {
    let plexServer: PlexServer
    let library: PlexLibrary

    @State private var collections: [PlexCollectionSummary]?
    @State private var loadError: String?

    @Environment(\.catalogNavigationActions) private var navigationActions

    var body: some View {
        Group {
            if collections == nil, loadError == nil {
                ProgressView("Loading collections…")
            } else if let loadError {
                ContentUnavailableView("Couldn't load collections", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if let collections, collections.isEmpty {
                ContentUnavailableView("No collections", systemImage: "square.stack.3d.up", description: Text("This library has no collections."))
            } else if let collections {
                List(collections) { item in
                    Button {
                        navigationActions.pushRoute(
                            .collectionItems(collectionKey: item.ratingKey, title: item.title, library: library)
                        )
                    } label: {
                        HStack(spacing: 12) {
                            CatalogArtworkImage(
                                plexServer: plexServer,
                                thumbPath: item.thumbPath,
                                style: .list
                            )
                            Text(item.title)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Collections")
        .task { await reload() }
        .refreshable { await reload() }
    }

    @MainActor
    private func reload() async {
        loadError = nil
        guard plexServer.usesLivePlexAPI else {
            collections = []
            return
        }
        do {
            let client = try PlexMediaServerClient(server: plexServer)
            collections = try await client.fetchLibraryCollections(library: library)
        } catch {
            loadError = error.localizedDescription
            collections = []
        }
    }
}

/// Items inside a playlist or collection (reuses catalog list UI).
struct PlaylistOrCollectionItemsView: View {
    let plexServer: PlexServer
    let library: PlexLibrary
    let parent: PlexCatalogParent
    let navigationTitle: String

    var body: some View {
        CatalogListView(
            plexServer: plexServer,
            library: library,
            parent: parent,
            navigationTitle: navigationTitle
        )
    }
}
