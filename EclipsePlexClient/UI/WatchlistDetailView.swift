//
//  WatchlistDetailView.swift
//  EclipsePlexClient
//

import SwiftUI

struct WatchlistDetailView: View {
    @ObservedObject var registry: PlexServerRegistry
    let server: PlexServer

    @State private var items: [WatchlistItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @EnvironmentObject private var playbackPresenter: PlaybackPresenter

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Loading watchlist…")
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView("Watchlist unavailable", systemImage: "star", description: Text(errorMessage))
            } else if items.isEmpty {
                ContentUnavailableView("Watchlist empty", systemImage: "star", description: Text("Add titles in Plex Discover."))
            } else {
                List(items) { item in
                    Button(item.title) {
                        playbackPresenter.present(
                            .plex(server: server, ratingKey: item.ratingKey, title: item.title)
                        )
                    }
                }
            }
        }
        .navigationTitle("Watchlist")
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    @MainActor
    private func load(force: Bool = false) async {
        guard let token = registry.plexAccountAuthToken, !token.isEmpty else {
            errorMessage = "Sign in to Plex.tv in Settings to load your Discover watchlist."
            return
        }
        if isLoading && !force { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await WatchlistService.fetchItems(accountToken: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
