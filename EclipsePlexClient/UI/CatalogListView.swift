//
//  CatalogListView.swift
//  EclipsePlexClient
//
//  Created by Matt Brown on 5/15/26.
//

import SwiftUI

/// Browses catalog rows for one `PlexLibrary`; sample fixtures or live Plex Media Server API.
struct CatalogListView: View {
    let plexServer: PlexServer
    let library: PlexLibrary
    let parent: PlexCatalogParent
    let navigationTitle: String

    @State private var searchText = ""
    @State private var liveLoadedNodes: [PlexCatalogNode]?
    @State private var liveLoadError: String?

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Offline fixtures only: match across every library on this server. Live servers search the current list.
    private var isAllLibrariesSearchMode: Bool {
        parent == .root && !trimmedSearch.isEmpty && !plexServer.usesLivePlexAPI
    }

    private var fixtureOrLiveNodes: [PlexCatalogNode] {
        if plexServer.usesLivePlexAPI {
            return liveLoadedNodes ?? []
        }
        return PlexSampleData.catalogNodes(for: library, parent: parent)
    }

    private var filteredNodes: [PlexCatalogNode] {
        let q = trimmedSearch
        let base = fixtureOrLiveNodes
        guard !q.isEmpty else { return base }
        return base.filter { $0.matchesSearch(trimmedQuery: q) }
    }

    private var allLibrariesSearchHits: [PlexCatalogSearchHit] {
        PlexSampleData.catalogSearchHits(forServerId: plexServer.id, query: trimmedSearch)
    }

    private var loadTaskKey: String {
        let parentKey: String
        switch parent {
        case .root: parentKey = "root"
        case .show(let k): parentKey = "show:\(k)"
        case .season(let k): parentKey = "season:\(k)"
        }
        return "\(plexServer.id.uuidString)|\(library.id)|\(parentKey)|\(plexServer.usesLivePlexAPI)"
    }

    var body: some View {
        Group {
            if plexServer.usesLivePlexAPI, liveLoadedNodes == nil, liveLoadError == nil {
                ProgressView("Loading catalog…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let liveLoadError, plexServer.usesLivePlexAPI {
                ContentUnavailableView {
                    Label("Couldn’t load library", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(liveLoadError)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                listContent
            }
        }
        .navigationTitle(navigationTitle)
        .searchable(
            text: $searchText,
            prompt: Text(parent == .root && !plexServer.usesLivePlexAPI ? "Search all libraries" : "Search this list")
        )
        .task(id: loadTaskKey) {
            guard plexServer.usesLivePlexAPI else {
                liveLoadedNodes = nil
                liveLoadError = nil
                return
            }
            liveLoadedNodes = nil
            liveLoadError = nil
            do {
                let client = try PlexMediaServerClient(server: plexServer)
                liveLoadedNodes = try await client.catalogNodes(library: library, parent: parent)
            } catch {
                liveLoadError = error.localizedDescription
                liveLoadedNodes = []
            }
        }
    }

    private var listContent: some View {
        List {
            if isAllLibrariesSearchMode {
                ForEach(allLibrariesSearchHits) { hit in
                    row(for: hit.node, itemLibrary: hit.library, showLibraryInRow: true)
                }
            } else {
                ForEach(filteredNodes) { node in
                    row(for: node, itemLibrary: library, showLibraryInRow: false)
                }
            }
        }
    }

    @ViewBuilder
    private func row(
        for node: PlexCatalogNode,
        itemLibrary: PlexLibrary,
        showLibraryInRow: Bool
    ) -> some View {
        let badge = showLibraryInRow ? itemLibrary.title : nil
        switch node {
        case .show(let show):
            NavigationLink {
                CatalogListView(
                    plexServer: plexServer,
                    library: itemLibrary,
                    parent: .show(ratingKey: show.ratingKey),
                    navigationTitle: show.title
                )
            } label: {
                CatalogRowView(
                    plexServer: plexServer,
                    node: node,
                    libraryContextTitle: badge
                )
            }
        case .season(let season):
            NavigationLink {
                CatalogListView(
                    plexServer: plexServer,
                    library: itemLibrary,
                    parent: .season(ratingKey: season.ratingKey),
                    navigationTitle: "\(season.showTitle) · \(season.title)"
                )
            } label: {
                CatalogRowView(
                    plexServer: plexServer,
                    node: node,
                    libraryContextTitle: badge
                )
            }
        case .movie, .episode, .musicTrack:
            NavigationLink {
                MediaDetailView(
                    plexServer: plexServer,
                    library: itemLibrary,
                    node: node
                )
            } label: {
                CatalogRowView(
                    plexServer: plexServer,
                    node: node,
                    libraryContextTitle: badge
                )
            }
        }
    }
}

// MARK: - Row

struct CatalogRowView: View {
    let plexServer: PlexServer
    let node: PlexCatalogNode
    var libraryContextTitle: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CatalogArtworkImage(
                plexServer: plexServer,
                thumbPath: node.listThumbPath,
                style: .list
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(node.listTitle)
                    .foregroundStyle(.primary)
                if let subtitle = node.listSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let lib = libraryContextTitle {
                    Text(lib)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview("Movie library") {
    NavigationStack {
        let server = PlexSampleData.servers[0]
        let lib = PlexSampleData.libraries(for: server.id)[0]
        CatalogListView(
            plexServer: server,
            library: lib,
            parent: .root,
            navigationTitle: lib.title
        )
    }
}

#Preview("TV library") {
    NavigationStack {
        let server = PlexSampleData.servers[0]
        let lib = PlexSampleData.libraries(for: server.id)[1]
        CatalogListView(
            plexServer: server,
            library: lib,
            parent: .root,
            navigationTitle: lib.title
        )
    }
}
