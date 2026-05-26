//
//  ContentViewPlaybackLoader.swift
//  EclipsePlexClient
//

import Foundation

/// Resolves `PlaybackRequest` into `ResolvedPlayback` for the player shell.
enum ContentViewPlaybackLoader {
    static func resolveOfflineFileURL(
        for request: PlaybackRequest,
        downloadManager: OfflineDownloadManager
    ) -> URL? {
        guard case .downloadedPlexItem(let server, let ratingKey, _) = request else {
            return nil
        }
        guard let record = downloadManager.playableRecord(serverId: server.id, ratingKey: ratingKey),
              let url = downloadManager.localFileURL(for: record)
        else {
            AppLog.offline("Offline file missing server=\(server.id.uuidString) ratingKey=\(ratingKey)")
            return nil
        }
        return url
    }

    @MainActor
    static func resolvePlayback(
        request: PlaybackRequest,
        downloadManager: OfflineDownloadManager
    ) async throws -> ResolvedPlayback {
        AppLog.playbackDebug("ContentView preparing playback")
        let offlineFileURL = resolveOfflineFileURL(for: request, downloadManager: downloadManager)
        let resolved = try await PlaybackResolver.resolve(request, offlineFileURL: offlineFileURL)
        AppLog.playbackDebug("ContentView playback URL ready")
        return resolved
    }
}
