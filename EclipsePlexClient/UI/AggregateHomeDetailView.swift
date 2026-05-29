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
    @EnvironmentObject private var focusCoordinator: KeyboardFocusCoordinator
    @Environment(\.catalogNavigationActions) private var catalogNavigation

    @State private var shelves: [AggregateHomeShelf] = []
    @State private var isLoading = false
    @State private var loadGeneration = 0

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                aggregateScrollContent
            }
#if os(tvOS)
            .tvBrowseFocusSection(.homeHubs)
#endif
            .onChange(of: focusCoordinator.homeFocusedIndex) { index in
                scrollHomeSelection(to: index, proxy: scrollProxy)
            }
        }
        .navigationTitle("Home")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .refreshable {
            await reloadShelves(invalidateCache: true)
        }
        .task(id: reloadTaskKey) {
            await reloadShelves(invalidateCache: false)
        }
        .onAppear {
            syncHomeFocusState()
            focusCoordinator.focusHome()
        }
        .onDisappear {
            focusCoordinator.clearHomeItems()
        }
        .onChange(of: shelves.map(\.server.id)) { _ in syncHomeFocusState() }
    }

    private var aggregateScrollContent: some View {
        VStack(alignment: .leading, spacing: 24) {
                EclipsePlexBrandingHeader(layout: .hero, subtitle: "All servers")

                if isLoading, shelves.isEmpty {
                    ProgressView("Loading from Plex…")
                        .frame(maxWidth: .infinity)
                }

                // Iterate `indices` rather than `Array(enumerated())` to avoid
                // re-allocating the tuple array on every body pass. `shelves`
                // identity is stable across the view's lifetime (one entry per
                // server); the per-server `shelfIndex` is positional and feeds
                // home-focus range start computations only.
                ForEach(shelves.indices, id: \.self) { shelfIndex in
                    serverShelf(shelves[shelfIndex], shelfIndex: shelfIndex)
                }

                if plexServers.isEmpty {
                    Text("Add a Plex server to see Continue Watching and Recently Added.")
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
                .buttonStyle(.pressableBorderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scrollHomeSelection(to index: Int, proxy: ScrollViewProxy) {
        guard focusCoordinator.route == .homeHubs,
              focusCoordinator.homeItems.indices.contains(index)
        else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(focusCoordinator.homeItems[index].id, anchor: .center)
        }
    }

    private var reloadTaskKey: String {
        plexServers.map { server in
            let count = plexRegistry.librariesByServerID[server.id]?.count ?? 0
            return "\(server.id.uuidString):\(count)"
        }.joined(separator: "|")
    }

    @ViewBuilder
    private func serverShelf(_ shelf: AggregateHomeShelf, shelfIndex: Int) -> some View {
        let rangeStart = homeFocusRangeStart(forShelfIndex: shelfIndex)
        let cwCount = shelf.continueWatching.count
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.server.name)
                .font(.title3.weight(.semibold))

            if let error = shelf.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HubRowView(
                title: "Continue Watching",
                hits: shelf.continueWatching,
                plexServer: shelf.server,
                shelfKey: "\(shelf.server.id.uuidString)|cw",
                homeFocusRangeStart: rangeStart,
                onSelectServer: onSelectServer
            )
            HubRowView(
                title: "Recently Added",
                hits: shelf.recentlyAdded,
                plexServer: shelf.server,
                shelfKey: "\(shelf.server.id.uuidString)|ra",
                homeFocusRangeStart: rangeStart + cwCount,
                onSelectServer: onSelectServer
            )
        }
    }

    private func homeFocusRangeStart(forShelfIndex shelfIndex: Int) -> Int {
        guard shelfIndex > 0 else { return 0 }
        return shelves.prefix(shelfIndex).reduce(0) { partial, shelf in
            partial + shelf.continueWatching.count + shelf.recentlyAdded.count
        }
    }

    private func syncHomeFocusState() {
        var items: [HomeFocusItem] = []
        for shelf in shelves {
            HomeHubFocus.appendItems(
                into: &items,
                shelfKey: "\(shelf.server.id.uuidString)|cw",
                hits: shelf.continueWatching,
                plexServer: shelf.server,
                navigation: catalogNavigation,
                onSelectServer: onSelectServer
            )
            HomeHubFocus.appendItems(
                into: &items,
                shelfKey: "\(shelf.server.id.uuidString)|ra",
                hits: shelf.recentlyAdded,
                plexServer: shelf.server,
                navigation: catalogNavigation,
                onSelectServer: onSelectServer
            )
        }
        focusCoordinator.setHomeItems(items)
    }

    @MainActor
    private func reloadShelves(invalidateCache: Bool) async {
        loadGeneration += 1
        let generation = loadGeneration
        if invalidateCache {
            await AggregateHomeHubService.invalidateAll()
            plexRegistry.invalidateLibraryCache()
        }
        isLoading = true
        await Task.detached { @MainActor in
            await plexRegistry.refreshLibraries(for: plexServers, force: invalidateCache)
        }.value
        defer { isLoading = false }
        let loaded = await AggregateHomeHubService.load(
            servers: plexServers,
            librariesByServerID: plexRegistry.librariesByServerID
        )
        guard generation == loadGeneration else { return }
        shelves = loaded
        syncHomeFocusState()
    }
}
