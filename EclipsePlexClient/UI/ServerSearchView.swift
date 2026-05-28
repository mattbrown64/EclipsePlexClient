//
//  ServerSearchView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Plex server-wide search (`/search`) across libraries.
struct ServerSearchView: View {
    let plexServer: PlexServer
    let libraries: [PlexLibrary]

    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [PlexCatalogSearchHit] = []
    @State private var isSearching = false
    @State private var searchError: String?
    /// In-flight server search. Held so a new submission (or view disappear)
    /// can cancel the previous request and avoid blocking the UI / wasting
    /// a slot in the per-host connection pool.
    @State private var activeSearchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if isSearching, results.isEmpty {
                    ProgressView("Searching…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let searchError, results.isEmpty {
                    ContentUnavailableView {
                        Label("Search failed", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(searchError)
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { hit in
                        NavigationLink {
                            searchDestination(hit)
                        } label: {
                            HStack(spacing: 12) {
                                CatalogArtworkImage(
                                    plexServer: plexServer,
                                    thumbPath: hit.node.listThumbPath,
                                    style: .list
                                )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(hit.node.listTitle)
                                    Text(hit.library.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: Text("Search all libraries"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onSubmit(of: .search) {
                startSearch()
            }
            .onChange(of: query) { _, newValue in
                if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    activeSearchTask?.cancel()
                    activeSearchTask = nil
                    results = []
                    searchError = nil
                }
            }
            .onDisappear {
                activeSearchTask?.cancel()
                activeSearchTask = nil
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 400)
        #endif
    }

    private func startSearch() {
        activeSearchTask?.cancel()
        activeSearchTask = Task { @MainActor in
            await runSearch()
        }
    }

    @ViewBuilder
    private func searchDestination(_ hit: PlexCatalogSearchHit) -> some View {
        Group {
            switch hit.node {
            case .show(let show):
                ShowDetailView(plexServer: plexServer, library: hit.library, show: show)
            case .season(let season):
                CatalogListView(
                    plexServer: plexServer,
                    library: hit.library,
                    parent: .season(ratingKey: season.ratingKey),
                    navigationTitle: season.title
                )
            case .movie, .episode, .musicTrack, .photo:
                MediaDetailView(plexServer: plexServer, library: hit.library, node: hit.node)
            }
        }
    }

    @MainActor
    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            let client = try PlexMediaServerClient(server: plexServer)
            let hits = try await client.searchCatalog(query: trimmed, libraries: libraries)
            // If a newer search superseded this one (or view went away), bail
            // without overwriting state.
            guard !Task.isCancelled else { return }
            results = hits
        } catch is CancellationError {
            // Superseded by a newer query; leave state untouched.
        } catch {
            guard !Task.isCancelled else { return }
            searchError = error.localizedDescription
            results = []
        }
    }
}
