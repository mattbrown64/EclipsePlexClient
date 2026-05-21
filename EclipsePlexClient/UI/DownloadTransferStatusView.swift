//
//  DownloadTransferStatusView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Progress, speed, and byte counts for an active offline download row.
struct DownloadTransferStatusView: View {
    let record: OfflineDownloadRecord
    var speedBytesPerSecond: Double?

    var body: some View {
        switch record.state {
        case .pending:
            Text("Queued — waiting to start")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloading:
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: min(1, max(0, record.progress)))
                Text(
                    OfflineDownloadProgressFormatter.progressLine(
                        progress: record.progress,
                        bytesWritten: record.bytesWritten,
                        expectedBytes: record.expectedBytes,
                        speedBytesPerSecond: speedBytesPerSecond
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
}
