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
    @State private var showCreate = false
    @State private var newPlaylistTitle = ""

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
                List {
                    ForEach(playlists) { playlist in
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
                        .buttonStyle(.pressablePlain)
                    }
                    .onDelete(perform: deletePlaylists)
                }
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New playlist", isPresented: $showCreate) {
            TextField("Title", text: $newPlaylistTitle)
            Button("Create") { Task { await createPlaylist() } }
            Button("Cancel", role: .cancel) { newPlaylistTitle = "" }
        }
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
            let client = try PlexMediaServerClient(server: plexServer.withActiveConnection())
            playlists = try await client.fetchPlaylists()
        } catch {
            loadError = error.localizedDescription
            playlists = []
        }
    }

    @MainActor
    private func createPlaylist() async {
        let title = newPlaylistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newPlaylistTitle = ""
        do {
            let client = try PlexMediaServerClient(server: plexServer.withActiveConnection())
            _ = try await client.createPlaylist(title: title, librarySectionID: 1)
            await reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func deletePlaylists(at offsets: IndexSet) {
        guard let playlists else { return }
        Task {
            let client = try? PlexMediaServerClient(server: plexServer.withActiveConnection())
            for index in offsets {
                let key = playlists[index].ratingKey
                try? await client?.deletePlaylist(playlistKey: key)
            }
            await reload()
        }
    }
}

/// Collections in a movie/TV library section.
struct LibraryCollectionsView: View {
    let plexServer: PlexServer
    let library: PlexLibrary
    var embedInLibraryShell: Bool = false

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
                    .buttonStyle(.pressablePlain)
                }
            }
        }
        .modifier(CollectionsChrome(embedInLibraryShell: embedInLibraryShell))
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
            let client = try PlexMediaServerClient(server: plexServer.withActiveConnection())
            collections = try await client.fetchLibraryCollections(library: library)
        } catch {
            loadError = error.localizedDescription
            collections = []
        }
    }
}

/// Items inside a playlist or collection (reuses catalog list UI).
private struct CollectionsChrome: ViewModifier {
    let embedInLibraryShell: Bool

    func body(content: Content) -> some View {
        if embedInLibraryShell {
            content
        } else {
            content.navigationTitle("Collections")
        }
    }
}

struct PlaylistOrCollectionItemsView: View {
    let plexServer: PlexServer
    let library: PlexLibrary
    let parent: PlexCatalogParent
    let navigationTitle: String

    @EnvironmentObject private var playbackQueue: PlaybackQueueManager

    var body: some View {
        CatalogListView(
            plexServer: plexServer,
            library: library,
            parent: parent,
            navigationTitle: navigationTitle
        )
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    playbackQueue.shuffle()
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
            }
        }
    }
}
