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

    private var activeRecords: [OfflineDownloadRecord] {
        downloadManager.records.filter {
            $0.state == .pending || $0.state == .downloading || $0.state == .failed
        }
        .sorted { $0.createdAt > $1.createdAt }
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
                Stepper("Storage cap: \(storageCapGB) GB", value: $storageCapGB, in: 5 ... 500, step: 5)
                    .onChange(of: storageCapGB) { _, value in
                        OfflineDownloadPreferences.storageCapGB = value
                    }
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

            if !activeRecords.isEmpty {
                Section("Active downloads") {
                    ForEach(activeRecords) { record in
                        DownloadQueueRowView(record: record)
                    }
                }
            }
        }
        .navigationTitle("Downloads")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .browseMenuToolbar()
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
            DownloadTransferStatusView(
                record: record,
                speedBytesPerSecond: downloadManager.transferSpeed(for: record.id)
            )
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
