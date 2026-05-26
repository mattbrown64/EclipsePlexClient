//
//  DownloadTransferStatusView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Progress, speed, and byte counts for an active offline download row.
///
/// Reads its live values from `DownloadProgressStore` (an `@EnvironmentObject`)
/// so it can update at the high frequency of byte-chunk callbacks without
/// re-rendering its parent screen.
struct DownloadTransferStatusView: View {
    @EnvironmentObject private var progressStore: DownloadProgressStore
    let record: OfflineDownloadRecord

    var body: some View {
        switch record.state {
        case .pending:
            Text("Queued — waiting to start")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloading:
            let snapshot = liveSnapshot
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: min(1, max(0, snapshot.progress)))
                Text(
                    OfflineDownloadProgressFormatter.progressLine(
                        progress: snapshot.progress,
                        bytesWritten: snapshot.bytesWritten,
                        expectedBytes: snapshot.expectedBytes,
                        speedBytesPerSecond: snapshot.speedBytesPerSecond > 0
                            ? snapshot.speedBytesPerSecond
                            : nil
                    )
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        case .completed:
            if record.bytesWritten > 0 {
                Text("Downloaded \(OfflineDownloadProgressFormatter.bytes(record.bytesWritten))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed, .cancelled:
            EmptyView()
        }
    }

    private var liveSnapshot: DownloadProgressStore.Snapshot {
        if let live = progressStore.snapshot(for: record.id) {
            return live
        }
        return DownloadProgressStore.Snapshot(
            bytesWritten: record.bytesWritten,
            expectedBytes: record.expectedBytes,
            progress: record.progress,
            speedBytesPerSecond: 0
        )
    }
}
