//
//  ShowDetailView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Overview for a TV show: summary, continue/resume, and season list.
struct ShowDetailView: View {
    let plexServer: PlexServer
    let library: PlexLibrary
    let show: PlexShowSummary

    @Environment(\.offlineDownloads) private var downloadManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissBrowseMenu) private var dismissBrowseMenu
    @EnvironmentObject private var plexRegistry: PlexServerRegistry

    @State private var detail: PlexMediaDetail?
    @State private var seasons: [PlexSeasonSummary] = []
    @State private var resumeEpisode: PlexCatalogNode?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var metadataAdminState = MediaMetadataAdminState()

    private var childSectionTitle: String {
        library.sectionType == .music ? "Albums" : "Seasons"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                if let summary = detail?.summary ?? show.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                if let year = detail?.year ?? show.year {
                    metaLine("Year", String(year))
                }
                playActions
                MediaMetadataAdminSection(
                    plexServer: plexServer,
                    ratingKey: show.ratingKey,
                    title: show.title,
                    summary: detail?.summary ?? show.summary,
                    year: detail?.year ?? show.year,
                    sectionType: library.sectionType,
                    state: $metadataAdminState,
                    onMetadataUpdated: {
                        await load()
                    },
                    onItemDeleted: {
                        dismiss()
                    }
                )
                .environmentObject(plexRegistry)
                if isLoading, seasons.isEmpty {
                    ProgressView("Loading seasons…")
                }
                if let loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if !seasons.isEmpty {
                    Text(childSectionTitle)
                        .font(.headline)
                    ForEach(seasons) { season in
                        NavigationLink(
                            value: CatalogNavigationRoute.browse(
                                library: library,
                                parent: .season(ratingKey: season.ratingKey),
                                navigationTitle: "\(show.title) · \(season.title)"
                            )
                        ) {
                            HStack(spacing: 12) {
                                CatalogArtworkImage(
                                    plexServer: plexServer,
                                    thumbPath: season.thumbPath,
                                    style: .list,
                                    showsDownloadedBadge: false
                                )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(season.title)
                                        .foregroundStyle(.primary)
                                    Text(season.showTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .contextMenu {
                            if let downloadManager {
                                ForEach(PlaybackVideoResolution.allCases) { quality in
                                    Button("Download season (\(quality.menuTitle))") {
                                        Task {
                                            try? await downloadManager.enqueueSeason(
                                                server: plexServer,
                                                library: library,
                                                seasonRatingKey: season.ratingKey,
                                                quality: quality
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                metaLine("Library", library.title)
                metaLine("Server", plexServer.name)
            }
            .padding()
        }
        .navigationTitle(show.title)
        .task(id: taskKey) {
            await load()
        }
    }

    private var taskKey: String {
        "\(plexServer.id)|\(show.ratingKey)"
    }

    @ViewBuilder
    private var hero: some View {
        HStack {
            Spacer(minLength: 0)
            CatalogArtworkImage(
                plexServer: plexServer,
                thumbPath: detail?.thumbPath ?? show.thumbPath,
                style: .detailHero
            )
            .mediaMetadataAdmin(
                plexServer: plexServer,
                ratingKey: show.ratingKey,
                title: show.title,
                summary: detail?.summary ?? show.summary,
                year: detail?.year ?? show.year,
                state: $metadataAdminState,
                sectionType: library.sectionType,
                includesPresentation: false,
                includesContextMenu: true,
                onMetadataUpdated: {
                    await load()
                },
                onItemDeleted: {
                    dismiss()
                }
            )
            .environmentObject(plexRegistry)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var playActions: some View {
        if plexServer.usesLivePlexAPI {
            HStack(spacing: 12) {
                if let resumeEpisode {
                    resumeLink(for: resumeEpisode)
                }
                NavigationLink(
                    value: CatalogNavigationRoute.browse(
                        library: library,
                        parent: .show(ratingKey: show.ratingKey),
                        navigationTitle: show.title
                    )
                ) {
                    Label("Browse all seasons", systemImage: "list.bullet")
                }
                .buttonStyle(.pressableBordered)
                if let downloadManager {
                    ShowDownloadControls(
                        plexServer: plexServer,
                        library: library,
                        showRatingKey: show.ratingKey,
                        showTitle: show.title
                    )
                    .offlineDownloads(downloadManager)
                }
            }
        }
    }

    @ViewBuilder
    private func resumeLink(for node: PlexCatalogNode) -> some View {
        if case .episode(let episode) = node {
            let hasProgress = node.watchProgressFraction != nil
            NavigationLink {
                ContentView(
                    request: .plex(
                        server: plexServer,
                        ratingKey: episode.ratingKey,
                        title: "\(show.title) · \(episode.title)",
                        episodeContext: EpisodePlayContext(
                            serverId: plexServer.id,
                            librarySectionID: library.sectionID,
                            showRatingKey: show.ratingKey
                        )
                    )
                )
                .onAppear { dismissBrowseMenu?.dismiss() }
            } label: {
                Label(
                    hasProgress ? "Continue S\(episode.seasonNumber) E\(episode.episodeNumber)" : "Play S\(episode.seasonNumber) E\(episode.episodeNumber)",
                    systemImage: "play.circle.fill"
                )
            }
            .buttonStyle(.pressableBorderedProminent)
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

    @MainActor
    private func load() async {
        guard plexServer.usesLivePlexAPI else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let client = try PlexMediaServerClient(server: plexServer)
            let fetchedDetail = try await client.fetchMediaDetail(ratingKey: show.ratingKey)
            guard !Task.isCancelled else { return }
            detail = fetchedDetail
            let seasonNodes = try await client.catalogNodes(
                library: library,
                parent: .show(ratingKey: show.ratingKey),
                watchFilter: .all
            )
            guard !Task.isCancelled else { return }
            seasons = seasonNodes.compactMap { node in
                if case .season(let season) = node { return season }
                return nil
            }
            .sorted { $0.seasonNumber < $1.seasonNumber }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error.localizedDescription
            return
        }

        // Resume lookup walks every season; runs inline so it inherits this
        // task's cancellation when the view pops. Previously this spawned an
        // unstructured `Task { }` that outlived `.task(id:)` and could write
        // `resumeEpisode` on a dismantled view, abort-killing the process
        // with a heap "freed pointer was not the last allocation" panic.
        await loadResumeEpisode()
    }

    @MainActor
    private func loadResumeEpisode() async {
        guard !Task.isCancelled, resumeEpisode == nil else { return }
        do {
            let client = try PlexMediaServerClient(server: plexServer)
            if let episode = try await client.fetchResumeEpisode(
                library: library,
                showRatingKey: show.ratingKey
            ) {
                guard !Task.isCancelled else { return }
                resumeEpisode = .episode(episode)
            }
        } catch is CancellationError {
            return
        } catch {
            AppLog.ui("Resume episode lookup failed: \(error.localizedDescription)")
        }
    }
}

#Preview {
    NavigationStack {
        let server = PlexSampleData.servers[0]
        let lib = PlexSampleData.libraries(for: server.id)[1]
        let show = PlexSampleData.catalogNodes(for: lib, parent: .root)
            .compactMap { node -> PlexShowSummary? in
                if case .show(let s) = node { return s }
                return nil
            }
            .first!
        ShowDetailView(plexServer: server, library: lib, show: show)
    }
}
