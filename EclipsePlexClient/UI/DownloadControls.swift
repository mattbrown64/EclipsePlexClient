//
//  DownloadControls.swift
//  EclipsePlexClient
//

import SwiftUI

/// Download / play-offline actions for media detail screens.
struct DownloadControls: View {
    let plexServer: PlexServer
    let ratingKey: String
    let title: String
    let thumbPath: String?

    @Environment(\.offlineDownloads) private var downloadManager
    @Environment(\.dismissBrowseMenu) private var dismissBrowseMenu
    @EnvironmentObject private var focusCoordinator: KeyboardFocusCoordinator
    @EnvironmentObject private var plexRegistry: PlexServerRegistry

    @State private var isEnqueueing = false
    @State private var batchError: String?
#if os(iOS)
    @State private var fullscreenPlayback: PlaybackPresentationItem?
#endif

    var body: some View {
        if let downloadManager {
            downloadBody(downloadManager)
#if os(iOS)
                .eclipsePlexFullscreenPlayback(
                    item: $fullscreenPlayback,
                    dependencies: PlaybackCoverDependencies(
                        downloadManager: downloadManager,
                        focusCoordinator: focusCoordinator,
                        plexRegistry: plexRegistry
                    )
                )
#endif
        }
    }

    @ViewBuilder
    private func downloadBody(_ downloadManager: OfflineDownloadManager) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let record = downloadManager.playableRecord(
                    serverId: plexServer.id,
                    ratingKey: ratingKey
                ), downloadManager.localFileURL(for: record) != nil {
                    offlinePlayLink(downloadManager: downloadManager, label: "Play offline")
                }

                Menu {
                    ForEach(PlaybackVideoResolution.allCases) { quality in
                        Button {
                            Task { await enqueue(quality: quality) }
                        } label: {
                            if downloadManager.record(
                                serverId: plexServer.id,
                                ratingKey: ratingKey,
                                quality: quality
                            ) != nil {
                                Label(quality.menuTitle, systemImage: "checkmark")
                            } else {
                                Text(quality.menuTitle)
                            }
                        }
                    }
                } label: {
                    if isEnqueueing {
                        ProgressView()
                    } else {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
                .disabled(isEnqueueing || !plexServer.usesLivePlexAPI)

                if let active = downloadManager.records.first(where: {
                    $0.serverId == plexServer.id
                        && $0.ratingKey == ratingKey
                        && ($0.state == .pending || $0.state == .downloading)
                }) {
                    Text(active.state == .downloading ? "Downloading…" : "Queued")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Saves the original file from your Plex server. Transcode options use the same file on disk.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let batchError {
                Text(batchError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func offlinePlayLink(downloadManager: OfflineDownloadManager, label: String) -> some View {
        let request = PlaybackRequest.downloadedPlexItem(
            server: plexServer,
            ratingKey: ratingKey,
            title: title
        )
#if os(iOS)
        Button {
            dismissBrowseMenu?.dismiss()
            fullscreenPlayback = PlaybackPresentationItem(request: request)
        } label: {
            Label(label, systemImage: "play.circle")
        }
        .buttonStyle(.pressableBorderedProminent)
#else
        NavigationLink {
            ContentView(request: request)
                .offlineDownloads(downloadManager)
                .onAppear { dismissBrowseMenu?.dismiss() }
        } label: {
            Label(label, systemImage: "play.circle")
        }
        .buttonStyle(.pressableBorderedProminent)
#endif
    }

    @MainActor
    private func enqueue(quality: PlaybackVideoResolution) async {
        guard let downloadManager else { return }
        isEnqueueing = true
        batchError = nil
        defer { isEnqueueing = false }
        await downloadManager.enqueue(
            server: plexServer,
            ratingKey: ratingKey,
            title: title,
            thumbPath: thumbPath,
            quality: quality
        )
    }
}

/// Batch download actions for TV show / season screens.
struct ShowDownloadControls: View {
    let plexServer: PlexServer
    let library: PlexLibrary
    let showRatingKey: String
    let showTitle: String
    var seasonRatingKey: String?
    var seasonTitle: String?

    @Environment(\.offlineDownloads) private var downloadManager

    @State private var isEnqueueing = false
    @State private var errorMessage: String?

    var body: some View {
        if let downloadManager {
            Menu {
                ForEach(PlaybackVideoResolution.allCases) { quality in
                    Button {
                        Task { await enqueue(quality: quality, downloadManager: downloadManager) }
                    } label: {
                        Text("Download (\(quality.menuTitle))")
                    }
                }
            } label: {
                if isEnqueueing {
                    ProgressView()
                } else {
                    Label(menuTitle, systemImage: "arrow.down.circle")
                }
            }
            .disabled(isEnqueueing || !plexServer.usesLivePlexAPI)
        }
    }

    private var menuTitle: String {
        if seasonRatingKey != nil { "Download season" }
        else { "Download all episodes" }
    }

    @MainActor
    private func enqueue(
        quality: PlaybackVideoResolution,
        downloadManager: OfflineDownloadManager
    ) async {
        isEnqueueing = true
        errorMessage = nil
        defer { isEnqueueing = false }
        do {
            if let seasonRatingKey {
                try await downloadManager.enqueueSeason(
                    server: plexServer,
                    library: library,
                    seasonRatingKey: seasonRatingKey,
                    quality: quality
                )
            } else {
                try await downloadManager.enqueueShow(
                    server: plexServer,
                    library: library,
                    showRatingKey: showRatingKey,
                    quality: quality
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
