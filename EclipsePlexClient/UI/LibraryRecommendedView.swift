//
//  LibraryRecommendedView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Per-library Recommended tab: horizontal hub shelves from `/hubs/sections/{id}`.
struct LibraryRecommendedView: View {
    let plexServer: PlexServer
    let library: PlexLibrary

    @State private var shelves: [PlexHubShelf] = []
    @State private var loadError: String?
    @State private var isLoading = false

    @Environment(\.catalogNavigationActions) private var catalogNavigation
    @EnvironmentObject private var focusCoordinator: KeyboardFocusCoordinator

    private var shelfKeyPrefix: String {
        "\(plexServer.id.uuidString)|\(library.id)|hub"
    }

    var body: some View {
        Group {
            if isLoading, shelves.isEmpty, loadError == nil {
                ProgressView("Loading recommendations…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError, shelves.isEmpty {
                ContentUnavailableView(
                    "Couldn't load recommendations",
                    systemImage: "sparkles",
                    description: Text(loadError)
                )
            } else if shelves.isEmpty {
                ContentUnavailableView(
                    "No recommendations",
                    systemImage: "sparkles",
                    description: Text("This library has no hub shelves from your Plex server yet.")
                )
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Avoid the per-body `Array(shelves.enumerated())`
                            // allocation; shelves are stable in identity over
                            // the view's lifetime so indexed iteration is safe.
                            ForEach(shelves.indices, id: \.self) { shelfIndex in
                                let shelf = shelves[shelfIndex]
                                HubRowView(
                                    title: shelf.title,
                                    hits: shelf.hits,
                                    plexServer: plexServer,
                                    shelfKey: "\(shelfKeyPrefix)|\(shelf.id)",
                                    homeFocusRangeStart: focusRangeStart(forShelfIndex: shelfIndex),
                                    navigatesInPlace: true
                                )
                            }
                        }
                        .padding()
                    }
#if os(tvOS)
                    .tvBrowseFocusSection(.homeHubs)
#endif
                    .onChange(of: focusCoordinator.homeFocusedIndex) { _, index in
                        scrollHomeFocus(to: index, proxy: scrollProxy)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .refreshable { await reload() }
        .task(id: taskKey) { await reload() }
        .onAppear {
            syncHomeFocusState()
            focusCoordinator.focusHome()
        }
        .onDisappear {
            focusCoordinator.clearHomeItems()
        }
        .onChange(of: shelves.map(\.id)) { _, _ in syncHomeFocusState() }
    }

    private var taskKey: String {
        "\(plexServer.id.uuidString)|\(library.id)|\(plexServer.usesLivePlexAPI)"
    }

    private func focusRangeStart(forShelfIndex shelfIndex: Int) -> Int {
        shelves.prefix(shelfIndex).reduce(0) { $0 + $1.hits.count }
    }

    private func scrollHomeFocus(to index: Int, proxy: ScrollViewProxy) {
        guard focusCoordinator.route == .homeHubs else { return }
        var offset = 0
        for shelf in shelves {
            if index < offset + shelf.hits.count {
                let local = index - offset
                guard shelf.hits.indices.contains(local) else { return }
                let focusID = HomeHubFocus.focusID(shelfKey: "\(shelfKeyPrefix)|\(shelf.id)", hit: shelf.hits[local])
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(focusID, anchor: .center)
                }
                return
            }
            offset += shelf.hits.count
        }
    }

    @MainActor
    private func reload() async {
        guard plexServer.usesLivePlexAPI, !plexServer.isDownloadsServer else {
            shelves = []
            loadError = nil
            syncHomeFocusState()
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let client = try PlexMediaServerClient(server: plexServer.withActiveConnection())
            shelves = try await client.fetchSectionHubs(library: library)
        } catch {
            loadError = error.localizedDescription
            shelves = []
        }
        syncHomeFocusState()
    }

    private func syncHomeFocusState() {
        var items: [HomeFocusItem] = []
        for shelf in shelves {
            HomeHubFocus.appendItems(
                into: &items,
                shelfKey: "\(shelfKeyPrefix)|\(shelf.id)",
                hits: shelf.hits,
                plexServer: plexServer,
                navigation: catalogNavigation,
                onSelectServer: nil,
                navigatesInPlace: true
            )
        }
        focusCoordinator.setHomeItems(items)
    }
}
