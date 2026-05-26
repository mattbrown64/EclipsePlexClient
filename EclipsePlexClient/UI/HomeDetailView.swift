//
//  HomeDetailView.swift
//  EclipsePlexClient
//

import SwiftUI
import UniformTypeIdentifiers

/// Detail when no library is selected — welcome, hubs, and server search entry.
struct HomeDetailView: View {
    let plexServer: PlexServer?
    let libraries: [PlexLibrary]
    var onAddPlexServer: () -> Void = {}

    @State private var continueWatching: [PlexCatalogSearchHit] = []
    @State private var recentlyAdded: [PlexCatalogSearchHit] = []
    @State private var hubsError: String?
    @State private var isLoadingHubs = false

    @Environment(\.openServerSearch) private var openServerSearch
    @State private var showFileImporter = false
    @State private var localPlayback: LocalFilePlayback?

    @EnvironmentObject private var focusCoordinator: KeyboardFocusCoordinator
    @Environment(\.catalogNavigationActions) private var catalogNavigation

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                homeScrollContent
            }
#if os(tvOS)
            .tvBrowseFocusSection(.homeHubs)
#endif
            .onChange(of: focusCoordinator.homeFocusedIndex) { _, index in
                scrollHomeSelection(to: index, proxy: scrollProxy)
            }
        }
        .navigationTitle("Home")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .browseMenuToolbar()
        .toolbar {
            if plexServer?.usesLivePlexAPI == true {
                ToolbarItem(placement: .automatic) {
                    Button {
                        openServerSearch?.open()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .accessibilityIdentifier("serverSearchButton")
                }
            }
        }
        .refreshable {
            await loadHubs()
        }
        .task(id: hubTaskKey) {
            await loadHubs()
        }
        .onAppear {
            syncHomeFocusState()
            focusCoordinator.focusHome()
        }
        .onDisappear {
            focusCoordinator.clearHomeItems()
        }
        .onChange(of: continueWatching.count) { _, _ in syncHomeFocusState() }
        .onChange(of: recentlyAdded.count) { _, _ in syncHomeFocusState() }
#if os(iOS)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .video, .audiovisualContent],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else {
                    AppToastCenter.show("Couldn’t access the selected file.")
                    return
                }
                localPlayback = LocalFilePlayback(url: url)
            case .failure(let error):
                AppToastCenter.show(error.localizedDescription)
            }
        }
#endif
        .modifier(LocalFilePlaybackPresentation(playback: $localPlayback))
    }

    private var homeScrollContent: some View {
        VStack(alignment: .leading, spacing: 24) {
                headerSection

                if let plexServer, plexServer.usesLivePlexAPI {
                    if isLoadingHubs, continueWatching.isEmpty, recentlyAdded.isEmpty {
                        ProgressView("Loading from Plex…")
                            .frame(maxWidth: .infinity)
                    }
                    if let hubsError {
                        Text(hubsError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    HubRowView(
                        title: "Continue Watching",
                        hits: continueWatching,
                        plexServer: plexServer,
                        shelfKey: "\(plexServer.id.uuidString)|cw",
                        homeFocusRangeStart: 0
                    )
                    HubRowView(
                        title: "Recently Added",
                        hits: recentlyAdded,
                        plexServer: plexServer,
                        shelfKey: "\(plexServer.id.uuidString)|ra",
                        homeFocusRangeStart: continueWatching.count
                    )
                }

                Text("Choose a library in the sidebar to browse its full catalog.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

    private var hubTaskKey: String {
        "\(plexServer?.id.uuidString ?? "none")|\(libraries.count)"
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EclipsePlexBrandingHeader(layout: .hero, subtitle: "Welcome")

            if let plexServer {
                HStack(spacing: 4) {
                    Text("Plex server:")
                        .foregroundStyle(.secondary)
                    Text(plexServer.name)
                        .fontWeight(.semibold)
                }
                .font(.body)
            } else {
                Text("Choose a Plex server in the sidebar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                onAddPlexServer()
            } label: {
                Label("Add Plex Server", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)

            if let plexServer, plexServer.usesLivePlexAPI {
                Button {
                    catalogNavigation.pushRoute(.liveTV)
                } label: {
                    Label("Live TV", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.bordered)
                if plexServer.connectionCandidates.count > 1 {
                    Text("Connection: \(plexServer.activeHostDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Button {
                showFileImporter = true
            } label: {
                Label("Open Video File…", systemImage: "folder")
            }
            .buttonStyle(.bordered)
        }
    }

    @MainActor
    private func loadHubs() async {
        guard let plexServer, plexServer.usesLivePlexAPI else {
            continueWatching = []
            recentlyAdded = []
            hubsError = nil
            isLoadingHubs = false
            return
        }
        // If the server is still loading its libraries, show a loading state for
        // the home hubs instead of presenting an empty screen.
        guard !libraries.isEmpty else {
            isLoadingHubs = true
            continueWatching = []
            recentlyAdded = []
            hubsError = nil
            return
        }
        isLoadingHubs = true
        hubsError = nil
        defer { isLoadingHubs = false }
        do {
            let client = try PlexMediaServerClient(server: plexServer)
            async let onDeck = client.fetchOnDeckHits(libraries: libraries)
            async let recent = client.fetchRecentlyAddedHits(libraries: libraries)
            continueWatching = try await onDeck
            recentlyAdded = try await recent
        } catch {
            hubsError = error.localizedDescription
            continueWatching = []
            recentlyAdded = []
            AppToastCenter.show("Couldn’t load home hubs: \(error.localizedDescription)")
        }
        syncHomeFocusState()
    }

    private func syncHomeFocusState() {
        guard let plexServer, plexServer.usesLivePlexAPI else {
            focusCoordinator.clearHomeItems()
            return
        }
        var items: [HomeFocusItem] = []
        HomeHubFocus.appendItems(
            into: &items,
            shelfKey: "\(plexServer.id.uuidString)|cw",
            hits: continueWatching,
            plexServer: plexServer,
            navigation: catalogNavigation
        )
        HomeHubFocus.appendItems(
            into: &items,
            shelfKey: "\(plexServer.id.uuidString)|ra",
            hits: recentlyAdded,
            plexServer: plexServer,
            navigation: catalogNavigation
        )
        focusCoordinator.setHomeItems(items)
    }
}

private struct LocalFilePlayback: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct LocalFilePlaybackPresentation: ViewModifier {
    @Binding var playback: LocalFilePlayback?

    func body(content: Content) -> some View {
        content
#if os(iOS)
            .fullScreenCover(item: $playback) { item in
                localPlayer(item)
            }
#else
            .sheet(item: $playback) { item in
                localPlayer(item)
                    .frame(minWidth: 900, minHeight: 560)
            }
#endif
    }

    @ViewBuilder
    private func localPlayer(_ item: LocalFilePlayback) -> some View {
        NavigationStack {
            ContentView(request: .localFile(item.url))
        }
    }
}

#Preview("Home — with server") {
    NavigationStack {
        let server = PlexSampleData.servers.first!
        HomeDetailView(
            plexServer: server,
            libraries: PlexSampleData.libraries(for: server.id)
        )
    }
}

#Preview("Home — no server") {
    NavigationStack {
        HomeDetailView(plexServer: nil, libraries: [])
    }
}
