//
//  DownloadProgressStore.swift
//  EclipsePlexClient
//
//  High-frequency download progress kept off of `OfflineDownloadManager` so that
//  per-byte progress ticks don't republish the entire `records` array and force
//  every screen that observes the download manager (catalog, home, detail, etc.)
//  to re-render its body during a download.
//

import Combine
import Foundation
import SwiftUI

/// Live, per-download progress for the UI.
///
/// `OfflineDownloadManager` writes here on every byte chunk; views that need
/// live progress (download row, transfer status) observe this object directly,
/// so churn is scoped to those views.
@MainActor
final class DownloadProgressStore: ObservableObject {
    struct Snapshot: Equatable {
        var bytesWritten: Int64
        var expectedBytes: Int64?
        var progress: Double
        var speedBytesPerSecond: Double
    }

    @Published private(set) var byID: [UUID: Snapshot] = [:]

    func update(id: UUID, snapshot: Snapshot) {
        byID[id] = snapshot
    }

    func remove(id: UUID) {
        byID.removeValue(forKey: id)
    }

    func snapshot(for id: UUID) -> Snapshot? {
        byID[id]
    }

    func speed(for id: UUID) -> Double? {
        byID[id]?.speedBytesPerSecond
    }
}
