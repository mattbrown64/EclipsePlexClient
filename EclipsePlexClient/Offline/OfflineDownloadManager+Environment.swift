//
//  OfflineDownloadManager+Environment.swift
//  EclipsePlexClient
//

import SwiftUI

private struct OfflineDownloadManagerKey: EnvironmentKey {
    static let defaultValue: OfflineDownloadManager? = nil
}

extension EnvironmentValues {
    var offlineDownloads: OfflineDownloadManager? {
        get { self[OfflineDownloadManagerKey.self] }
        set { self[OfflineDownloadManagerKey.self] = newValue }
    }
}

extension View {
    func offlineDownloads(_ manager: OfflineDownloadManager) -> some View {
        environment(\.offlineDownloads, manager)
            .environmentObject(manager)
    }
}
