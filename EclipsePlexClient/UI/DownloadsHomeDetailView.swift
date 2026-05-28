//
//  DownloadsHomeDetailView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Home column when the virtual Downloads server is selected (settings + active transfers).
struct DownloadsHomeDetailView: View {
    @EnvironmentObject private var downloadManager: OfflineDownloadManager

    @State private var wifiOnly = OfflineDownloadPreferences.wifiOnly
    @State private var storageCapGB = OfflineDownloadPreferences.storageCapGB
    @State private var pruneWatched = OfflineDownloadPreferences.pruneWatchedWhenOverCap
    @State private var pendingDeleteShowGroupKey: String?
    @State private var pendingDeleteShowTitle = ""
    @State private var showDeleteShowConfirm = false

    private var downloadedShows: [(groupKey: String, title: String, episodeCount: Int)] {
        let episodes = downloadManager.records.filter {
            $0.resolvedMediaKind == .episode
        }
        let grouped = Dictionary(grouping: episodes, by: \.showGroupKey)
        return grouped.compactMap { groupKey, items -> (String, String, Int)? in
            guard let first = items.first else { return nil }
            return (groupKey, first.resolvedShowTitle, items.count)
        }
        .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    private var activeRecords: [OfflineDownloadRecord] {
        downloadManager.records.filter {
            $0.state == .pending || $0.state == .downloading || $0.state == .failed
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private var deleteShowConfirmMessage: String {
        let name = pendingDeleteShowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return "Removes all downloaded episodes for this show from this device."
        }
        return "Removes all downloaded episodes for “\(name)” from this device."
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer(minLength: 0)
                    EclipsePlexBrandingHeader(layout: .compact)
                    Spacer(minLength: 0)
                }
                .listRowBackground(Color.clear)

                Text("Choose **Movies** or **TV Shows** in the sidebar to browse what you’ve saved for offline playback.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
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

            if !downloadedShows.isEmpty {
                Section("Downloaded TV shows") {
                    ForEach(downloadedShows, id: \.groupKey) { show in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(show.title)
                                    .font(.headline)
                                Text("\(show.episodeCount) episode\(show.episodeCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button("Delete show", role: .destructive) {
                                pendingDeleteShowGroupKey = show.groupKey
                                pendingDeleteShowTitle = show.title
                                showDeleteShowConfirm = true
                            }
                            .buttonStyle(.pressableBordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            if !activeRecords.isEmpty {
                Section("Active downloads") {
                    ForEach(activeRecords) { record in
                        DownloadQueueRowView(record: record)
                    }
                }
            }
        }
        .navigationTitle("Downloads")
        .confirmDestructive(
            title: "Delete show?",
            message: deleteShowConfirmMessage,
            confirmLabel: "Delete",
            isPresented: $showDeleteShowConfirm
        ) {
            if let key = pendingDeleteShowGroupKey {
                downloadManager.deleteShow(groupKey: key)
            }
            pendingDeleteShowGroupKey = nil
            pendingDeleteShowTitle = ""
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct DownloadQueueRowView: View {
    @EnvironmentObject private var downloadManager: OfflineDownloadManager
    let record: OfflineDownloadRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DownloadRecordArtwork(record: record)
            VStack(alignment: .leading, spacing: 6) {
            Text(record.title)
                .font(.headline)
                .lineLimit(2)
            Text("From \(record.serverName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            DownloadTransferStatusView(record: record)
            if let error = record.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                if record.state == .failed {
                    Button("Retry") { downloadManager.retry(id: record.id) }
                }
                if record.state == .pending || record.state == .downloading {
                    Button("Cancel", role: .cancel) { downloadManager.cancel(id: record.id) }
                }
                if record.state != .downloading {
                    Button("Delete", role: .destructive) { downloadManager.delete(id: record.id) }
                }
            }
            .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
