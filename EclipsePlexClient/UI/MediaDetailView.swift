//
//  MediaDetailView.swift
//  EclipsePlexClient
//
//  Created by Matt Brown on 5/15/26.
//

import SwiftUI

/// Placeholder detail for leaf catalog items (movie, episode, track). Replace with play controls and full metadata.
struct MediaDetailView: View {
    let plexServer: PlexServer
    let library: PlexLibrary
    let node: PlexCatalogNode

    @EnvironmentObject private var sidebarInteraction: SidebarInteractionState

    var body: some View {
        Group {
            switch node {
            case .movie(let movie):
                movieContent(movie)
            case .episode(let episode):
                episodeContent(episode)
            case .musicTrack(let track):
                musicContent(track)
            case .show, .season:
                Text("Select a movie, episode, or track to see details.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .navigationTitle(detailTitle)
    }

    private var detailTitle: String {
        switch node {
        case .movie(let m): return m.title
        case .episode(let e): return e.title
        case .musicTrack(let t): return t.title
        case .show(let s): return s.title
        case .season(let s): return s.title
        }
    }

    @ViewBuilder
    private func movieContent(_ movie: PlexMovieSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer(minLength: 0)
                CatalogArtworkImage(
                    plexServer: plexServer,
                    thumbPath: movie.thumbPath,
                    style: .detailHero
                )
                Spacer(minLength: 0)
            }
            metaLine("Library", library.title)
            metaLine("Server", plexServer.name)
            if let year = movie.year {
                metaLine("Year", String(year))
            }
            if let summary = movie.summary {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            watchDemoNavigationLink
            Text("Playback and full Plex metadata will go here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func episodeContent(_ episode: PlexEpisodeSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer(minLength: 0)
                CatalogArtworkImage(
                    plexServer: plexServer,
                    thumbPath: episode.thumbPath,
                    style: .detailHero
                )
                Spacer(minLength: 0)
            }
            metaLine("Show", episode.showTitle)
            metaLine("Episode", "S\(episode.seasonNumber) E\(episode.episodeNumber)")
            if let seconds = episode.durationSeconds {
                metaLine("Duration", formatDuration(seconds))
            }
            metaLine("Library", library.title)
            metaLine("Server", plexServer.name)
            if let summary = episode.summary {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            watchDemoNavigationLink
            Text("Playback and progress sync will go here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func musicContent(_ track: PlexMusicTrackSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer(minLength: 0)
                CatalogArtworkImage(
                    plexServer: plexServer,
                    thumbPath: track.thumbPath,
                    style: .detailHero
                )
                Spacer(minLength: 0)
            }
            if let artist = track.artist { metaLine("Artist", artist) }
            if let album = track.album { metaLine("Album", album) }
            metaLine("Library", library.title)
            metaLine("Server", plexServer.name)
            Text("Audio playback will go here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func metaLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Opens the bundled demo player (`ContentView`); replace with real stream URLs later.
    private var watchDemoNavigationLink: some View {
        NavigationLink {
            ContentView()
                .onAppear { sidebarInteraction.suppressSidebarInteraction = true }
                .onDisappear { sidebarInteraction.suppressSidebarInteraction = false }
        } label: {
            Label("Watch", systemImage: "play.circle.fill")
        }
        .buttonStyle(.borderedProminent)
    }
}

#Preview("Movie detail") {
    NavigationStack {
        let server = PlexSampleData.servers[0]
        let lib = PlexSampleData.libraries(for: server.id)[0]
        let node = PlexSampleData.catalogNodes(for: lib, parent: .root).first!
        MediaDetailView(plexServer: server, library: lib, node: node)
    }
    .environmentObject(SidebarInteractionState())
}
