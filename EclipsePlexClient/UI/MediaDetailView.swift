//
//  MediaDetailView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Detail for leaf catalog items (movie, episode, track) with Watch → playback.
struct MediaDetailView: View {
    let plexServer: PlexServer
    let library: PlexLibrary
    let node: PlexCatalogNode

    @EnvironmentObject private var downloadManager: OfflineDownloadManager
    @EnvironmentObject private var focusCoordinator: KeyboardFocusCoordinator
    @Environment(\.dismissBrowseMenu) private var dismissBrowseMenu

    @State private var detail: PlexMediaDetail?
#if os(macOS)
    @State private var macOSPlaybackRequest: PlaybackRequest?
#endif
    @State private var isLoadingDetail = false
    @State private var detailError: String?
    @State private var isUpdatingWatchState = false
    @State private var extras: [PlexExtraItem] = []
    @State private var relatedShelves: [PlexHubShelf] = []
#if os(iOS) || os(tvOS)
    @State private var fullscreenPlayback: PlaybackPresentationItem?
#endif
#if os(tvOS)
    @FocusState private var tvDetailFocus: TVDetailFocusField?
#endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch node {
                case .movie(let movie):
                    heroArtwork(movie.thumbPath)
                    baseContent(for: movie.title, summary: movie.summary, year: movie.year)
                case .episode(let episode):
                    heroArtwork(episode.thumbPath)
                    metaLine("Show", episode.showTitle)
                    metaLine("Episode", "S\(episode.seasonNumber) E\(episode.episodeNumber)")
                    if let seconds = episode.durationSeconds {
                        metaLine("Duration", formatDuration(seconds))
                    }
                    baseContent(for: episode.title, summary: episode.summary, year: nil)
                case .musicTrack(let track):
                    heroArtwork(track.thumbPath)
                    if let artist = track.artist { metaLine("Artist", artist) }
                    if let album = track.album { metaLine("Album", album) }
                    baseContent(for: track.title, summary: nil, year: nil)
                case .photo(let photo):
                    heroArtwork(photo.thumbPath)
                    baseContent(for: photo.title, summary: nil, year: nil)
                case .show, .season:
                    Text("Select a movie, episode, or track to see details.")
                        .foregroundStyle(.secondary)
                }

                if let detail {
                    enrichedMetadata(detail)
                }
                if !extras.isEmpty {
                    Text("Extras")
                        .font(.headline)
                    ForEach(extras) { extra in
                        if plexServer.usesLivePlexAPI {
                            playButton(
                                request: .plex(server: plexServer, ratingKey: extra.ratingKey, title: extra.title),
                                label: "\(extra.displayType): \(extra.title)",
                                isProminent: false
                            )
                        }
                    }
                }
                if !relatedShelves.isEmpty {
                    ForEach(relatedShelves) { shelf in
                        HubRowView(
                            title: shelf.title,
                            hits: shelf.hits,
                            plexServer: plexServer,
                            shelfKey: "detail|\(playbackRatingKey ?? "")|\(shelf.id)",
                            navigatesInPlace: true
                        )
                    }
                }
                if detail == nil, isLoadingDetail {
                    ProgressView("Loading details…")
                } else if let detailError {
                    Text(detailError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                metaLine("Library", library.title)
                if let offlineRecord {
                    metaLine("From", offlineRecord.serverName)
                } else {
                    metaLine("Server", plexServer.name)
                }
                watchControls
                if node.supportsVideoPlayback,
                   let ratingKey = playbackRatingKey,
                   !plexServer.isDownloadsServer {
                    DownloadControls(
                        plexServer: plexServer,
                        ratingKey: ratingKey,
                        title: detailTitle,
                        thumbPath: node.listThumbPath
                    )
                    .environment(\.offlineDownloads, downloadManager)
                    .environmentObject(downloadManager)
                }
                if plexServer.isDownloadsServer, let record = offlineRecord {
                    offlineFileActions(record: record)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(detailTitle)
        .task(id: detailTaskKey) {
            await loadDetail()
        }
#if os(iOS) || os(tvOS)
        .eclipsePlexFullscreenPlayback(item: $fullscreenPlayback)
#endif
#if os(macOS)
        .navigationDestination(item: $macOSPlaybackRequest) { request in
            ContentView(request: request)
        }
#endif
        .onAppear {
            focusCoordinator.route = .detailActions
        }
        .onKeyPress(keys: [.init("w")]) { _ in
            startKeyboardWatch(resume: false)
            return .handled
        }
        .onKeyPress(keys: [.init("W")]) { _ in
            startKeyboardWatch(resume: false)
            return .handled
        }
        .onKeyPress(keys: [.init("r")]) { _ in
            if canResumePlayback {
                startKeyboardWatch(resume: true)
            }
            return .handled
        }
        .onKeyPress(keys: [.init("R")]) { _ in
            if canResumePlayback {
                startKeyboardWatch(resume: true)
            }
            return .handled
        }
    }

    private func startKeyboardWatch(resume: Bool) {
        guard node.supportsVideoPlayback,
              let ratingKey = playbackRatingKey,
              plexServer.usesLivePlexAPI,
              !plexServer.isDownloadsServer
        else { return }
        if resume, !canResumePlayback { return }
        let request = PlaybackRequest.plex(
            server: plexServer,
            ratingKey: ratingKey,
            title: detailTitle,
            episodeContext: episodePlayContext
        )
#if os(iOS) || os(tvOS)
        dismissBrowseMenu?.dismiss()
        fullscreenPlayback = PlaybackPresentationItem(request: request)
#elseif os(macOS)
        dismissBrowseMenu?.dismiss()
        macOSPlaybackRequest = request
#endif
    }

    private var detailTaskKey: String {
        "\(plexServer.id)|\(playbackRatingKey ?? "")"
    }

    private var detailTitle: String {
        detail?.title ?? node.listTitle
    }

    private var playbackRatingKey: String? {
        node.playbackRatingKey
    }

    private var offlineRecord: OfflineDownloadRecord? {
        guard plexServer.isDownloadsServer, let key = playbackRatingKey else { return nil }
        return downloadManager.record(forCatalogRatingKey: key)
    }

    private var originPlexServer: PlexServer? {
        guard let offlineRecord else { return nil }
        return downloadManager.server(for: offlineRecord)
    }

    @ViewBuilder
    private func heroArtwork(_ thumbPath: String?) -> some View {
        HStack {
            Spacer(minLength: 0)
            CatalogArtworkImage(
                plexServer: plexServer,
                thumbPath: thumbPath,
                artworkServer: originPlexServer,
                style: .detailHero,
                showsDownloadedBadge: !plexServer.isDownloadsServer
                    && downloadManager.isDownloaded(
                        serverId: plexServer.id,
                        ratingKey: playbackRatingKey ?? ""
                    )
                    && playbackRatingKey != nil
            )
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func baseContent(for title: String, summary: String?, year: Int?) -> some View {
        if let year {
            metaLine("Year", String(year))
        }
        if let summary, !summary.isEmpty {
            Text(summary)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func enrichedMetadata(_ detail: PlexMediaDetail) -> some View {
        if let fraction = detail.watchProgressFraction {
            VStack(alignment: .leading, spacing: 4) {
                Text("Watch progress")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: fraction)
            }
        }
        if let rating = detail.rating {
            metaLine("Critic rating", String(format: "%.1f", rating))
        }
        if let audience = detail.audienceRating {
            metaLine("Audience", String(format: "%.1f", audience))
        }
        if let contentRating = detail.contentRating {
            metaLine("Content rating", contentRating)
        }
        if let studio = detail.studio {
            metaLine("Studio", studio)
        }
        if !detail.genres.isEmpty {
            metaLine("Genres", detail.genres.joined(separator: ", "))
        }
        if !detail.directors.isEmpty {
            metaLine("Director", detail.directors.joined(separator: ", "))
        }
        if !detail.cast.isEmpty {
            metaLine("Cast", detail.cast.prefix(8).joined(separator: ", "))
        }
    }

    private var canResumePlayback: Bool {
        guard let detail else { return false }
        if detail.isWatched { return false }
        if detail.watchProgressFraction != nil { return true }
        if let ratingKey = playbackRatingKey,
           let localMs = PlaybackPositionStore.load(serverId: plexServer.id, ratingKey: ratingKey),
           localMs > 5_000 {
            return true
        }
        return false
    }

    @ViewBuilder
    private func offlineFileActions(record: OfflineDownloadRecord) -> some View {
        HStack(spacing: 12) {
            if let origin = originPlexServer {
                playButton(
                    request: .downloadedPlexItem(
                        server: origin,
                        ratingKey: record.ratingKey,
                        title: detailTitle
                    ),
                    label: "Play",
                    isProminent: true
                )
            }
            Button("Remove download", role: .destructive) {
                downloadManager.delete(id: record.id)
            }
        }
    }

    @ViewBuilder
    private var watchControls: some View {
        if node.supportsVideoPlayback, let ratingKey = playbackRatingKey {
            if plexServer.isDownloadsServer {
                EmptyView()
            } else if plexServer.usesLivePlexAPI {
                HStack(spacing: 12) {
                    if canResumePlayback {
                        watchNavigationLink(ratingKey: ratingKey, label: "Resume", isProminent: true)
#if os(tvOS)
                            .focused($tvDetailFocus, equals: .resume)
#endif
                    }
                    watchNavigationLink(
                        ratingKey: ratingKey,
                        label: canResumePlayback ? "Play from start" : "Watch",
                        isProminent: !canResumePlayback
                    )
#if os(tvOS)
                    .focused($tvDetailFocus, equals: .watch)
#endif
                    if detail != nil {
                        Button {
                            Task { await toggleWatched(ratingKey: ratingKey) }
                        } label: {
                            if isUpdatingWatchState {
                                ProgressView()
                            } else if detail?.isWatched == true {
                                Label("Mark unwatched", systemImage: "eye.slash")
                            } else {
                                Label("Mark watched", systemImage: "checkmark.circle")
                            }
                        }
                        .disabled(isUpdatingWatchState)
                    }
                }
#if os(tvOS)
                .tvBrowseFocusSection(.detailActions)
                .onAppear {
                    tvDetailFocus = canResumePlayback ? .resume : .watch
                }
#endif
            } else {
                Text("Add a reachable server URL and Plex token to play this item.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

    private var episodePlayContext: EpisodePlayContext? {
        guard library.sectionType == .show else { return nil }
        let episode: PlexEpisodeSummary?
        if case .episode(let e) = node {
            episode = e
        } else if case .episode(let e) = detail?.node {
            episode = e
        } else {
            episode = nil
        }
        guard let episode else { return nil }
        let showKey = episode.showRatingKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let showKey, !showKey.isEmpty else { return nil }
        return EpisodePlayContext(
            serverId: plexServer.id,
            librarySectionID: library.sectionID,
            showRatingKey: showKey
        )
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    @ViewBuilder
    private func watchNavigationLink(
        ratingKey: String,
        label: String,
        isProminent: Bool
    ) -> some View {
        playButton(
            request: .plex(
                server: plexServer,
                ratingKey: ratingKey,
                title: detailTitle,
                episodeContext: episodePlayContext
            ),
            label: label,
            isProminent: isProminent
        )
    }

    @ViewBuilder
    private func playButton(request: PlaybackRequest, label: String, isProminent: Bool) -> some View {
#if os(iOS) || os(tvOS)
        Button {
            dismissBrowseMenu?.dismiss()
            fullscreenPlayback = PlaybackPresentationItem(request: request)
        } label: {
            Label(label, systemImage: "play.circle.fill")
        }
        .modifier(WatchLinkButtonStyle(isProminent: isProminent))
        .accessibilityIdentifier("watchButton")
#elseif os(macOS)
        NavigationLink {
            ContentView(request: request)
                .environmentObject(focusCoordinator)
                .onAppear { dismissBrowseMenu?.dismiss() }
        } label: {
            Label(label, systemImage: "play.circle.fill")
        }
        .modifier(WatchLinkButtonStyle(isProminent: isProminent))
        .accessibilityIdentifier("watchButton")
#endif
    }

    @MainActor
    private func loadDetail() async {
        guard !plexServer.isDownloadsServer,
              plexServer.usesLivePlexAPI,
              let ratingKey = playbackRatingKey else { return }
        isLoadingDetail = true
        detailError = nil
        defer { isLoadingDetail = false }
        do {
            let client = try PlexMediaServerClient(server: plexServer)
            detail = try await client.fetchMediaDetail(ratingKey: ratingKey)
            extras = (try? await client.fetchExtras(ratingKey: ratingKey)) ?? []
            relatedShelves = (try? await client.fetchRelatedHubShelves(ratingKey: ratingKey, library: library)) ?? []
        } catch {
            detailError = error.localizedDescription
        }
    }

    @MainActor
    private func toggleWatched(ratingKey: String) async {
        guard let detail else { return }
        isUpdatingWatchState = true
        defer { isUpdatingWatchState = false }
        do {
            let client = try PlexMediaServerClient(server: plexServer)
            if detail.isWatched {
                try await client.markItemUnwatched(ratingKey: ratingKey)
            } else {
                try await client.markItemPlayed(ratingKey: ratingKey, durationMs: detail.durationMs)
            }
            self.detail = try await client.fetchMediaDetail(ratingKey: ratingKey)
        } catch {
            detailError = error.localizedDescription
        }
    }
}

private struct WatchLinkButtonStyle: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        if isProminent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

#Preview("Movie detail") {
    NavigationStack {
        let server = PlexSampleData.servers[0]
        let lib = PlexSampleData.libraries(for: server.id)[0]
        let node = PlexSampleData.catalogNodes(for: lib, parent: .root).first!
        MediaDetailView(plexServer: server, library: lib, node: node)
    }
    .environmentObject(OfflineDownloadManager())
    .environmentObject(KeyboardFocusCoordinator())
}
