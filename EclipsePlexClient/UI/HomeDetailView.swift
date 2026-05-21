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
    @State private var showSearch = false
    @State private var showFileImporter = false
    @State private var localPlayback: LocalFilePlayback?

    var body: some View {
        ScrollView {
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
                        plexServer: plexServer
                    )
                    HubRowView(
                        title: "Recently Added",
                        hits: recentlyAdded,
                        plexServer: plexServer
                    )
                }

                Text("Choose a library in the sidebar to browse its full catalog.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
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
                        showSearch = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            if let plexServer {
                ServerSearchView(plexServer: plexServer, libraries: libraries)
            }
        }
        .refreshable {
            await loadHubs()
        }
        .task(id: hubTaskKey) {
            await loadHubs()
        }
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
        .modifier(LocalFilePlaybackPresentation(playback: $localPlayback))
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
        guard let plexServer, plexServer.usesLivePlexAPI, !libraries.isEmpty else {
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
