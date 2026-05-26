//
//  DownloadsListView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Lists offline downloads, progress, and storage settings.
/// Pushes offline playback from the downloads list without nesting `NavigationLink` in a list row.
private struct DownloadPlaybackRoute: Hashable {
    let server: PlexServer
    let ratingKey: String
    let title: String
}

struct DownloadsListView: View {
    @EnvironmentObject private var downloadManager: OfflineDownloadManager
    @EnvironmentObject private var plexRegistry: PlexServerRegistry
    @State private var playbackRoute: DownloadPlaybackRoute?
    @State private var wifiOnly = OfflineDownloadPreferences.wifiOnly
    @State private var storageCapGB = OfflineDownloadPreferences.storageCapGB
    @State private var pruneWatched = OfflineDownloadPreferences.pruneWatchedWhenOverCap

    private var sortedRecords: [OfflineDownloadRecord] {
        downloadManager.records.sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }

    var body: some View {
        List {
            Section("Settings") {
                Toggle("Wi‑Fi only", isOn: $wifiOnly)
                    .onChange(of: wifiOnly) { _, value in
                        OfflineDownloadPreferences.wifiOnly = value
                        Task { await downloadManager.pumpQueueIfAllowed() }
                    }
#if os(tvOS)
                Picker("Storage cap", selection: $storageCapGB) {
                    ForEach([5, 10, 25, 50, 100, 200, 500], id: \.self) { gb in
                        Text("\(gb) GB").tag(gb)
                    }
                }
                .onChange(of: storageCapGB) { _, value in
                    OfflineDownloadPreferences.storageCapGB = value
                }
#else
                Stepper("Storage cap: \(storageCapGB) GB", value: $storageCapGB, in: 5 ... 500, step: 5)
                    .onChange(of: storageCapGB) { _, value in
                        OfflineDownloadPreferences.storageCapGB = value
                    }
#endif
                Toggle("Prune watched when over cap", isOn: $pruneWatched)
                    .onChange(of: pruneWatched) { _, value in
                        OfflineDownloadPreferences.pruneWatchedWhenOverCap = value
                    }
                LabeledContent("Used") {
                    Text(byteCount(downloadManager.totalDownloadedBytes))
                }
                if OfflineDownloadPreferences.wifiOnly, !downloadManager.isOnWiFi {
                    Text("Waiting for Wi‑Fi to start pending downloads.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Downloads") {
                if sortedRecords.isEmpty {
                    ContentUnavailableView {
                        Label("No downloads", systemImage: "arrow.down.circle")
                    } description: {
                        Text("Download movies or episodes from their detail page.")
                    }
                } else {
                    ForEach(sortedRecords) { record in
                        DownloadRowView(record: record, onPlay: openPlayback)
                    }
                }
            }
        }
        .navigationTitle("Downloads")
        .navigationDestination(item: $playbackRoute) { route in
            ContentView(
                request: .downloadedPlexItem(
                    server: route.server,
                    ratingKey: route.ratingKey,
                    title: route.title
                )
            )
            .environment(\.offlineDownloads, downloadManager)
            .environmentObject(downloadManager)
        }
    }

    private func openPlayback(server: PlexServer, ratingKey: String, title: String) {
        playbackRoute = DownloadPlaybackRoute(server: server, ratingKey: ratingKey, title: title)
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct DownloadRowView: View {
    @EnvironmentObject private var downloadManager: OfflineDownloadManager

    let record: OfflineDownloadRecord
    let onPlay: (PlexServer, String, String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DownloadRecordArtwork(record: record)
            VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                stateLabel
            }
            Text("\(record.serverName) · \(record.quality.menuTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if record.state == .pending || record.state == .downloading || record.state == .completed {
                DownloadTransferStatusView(
                    record: record,
                    speedBytesPerSecond: downloadManager.transferSpeed(for: record.id)
                )
            }

            if let error = record.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                if record.isPlayable,
                   downloadManager.localFileURL(for: record) != nil,
                   let server = downloadManager.server(for: record) {
                    Button {
                        onPlay(server, record.ratingKey, record.title)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                if record.state == .failed {
                    Button("Retry") {
                        downloadManager.retry(id: record.id)
                    }
                }
                if record.state == .pending || record.state == .downloading {
                    Button("Cancel", role: .cancel) {
                        downloadManager.cancel(id: record.id)
                    }
                }
                if record.state != .downloading {
                    Button("Delete", role: .destructive) {
                        downloadManager.delete(id: record.id)
                    }
                }
            }
            .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch record.state {
        case .pending:
            Text("Queued").font(.caption).foregroundStyle(.secondary)
        case .downloading:
            Text("Downloading").font(.caption).foregroundStyle(.tint)
        case .completed:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Text("Failed").font(.caption).foregroundStyle(.red)
        case .cancelled:
            Text("Cancelled").font(.caption).foregroundStyle(.secondary)
        }
    }
}
