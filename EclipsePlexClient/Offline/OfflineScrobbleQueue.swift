//
//  OfflineScrobbleQueue.swift
//  EclipsePlexClient
//

import Foundation

/// Plex watch-state updates queued while offline or when the server is unreachable.
enum OfflineScrobbleQueue {
    private static let fileName = "offlineScrobbleQueue.v1.json"

    struct Entry: Codable, Hashable, Sendable {
        let serverId: UUID
        let ratingKey: String
        let positionMs: Int
        let durationMs: Int
        let markPlayed: Bool
        let createdAt: Date
    }

    /// Whether queued entries can be sent to this Plex server.
    nonisolated static func canFlush(to server: PlexServer) -> Bool {
        guard !server.isDownloadsServer else { return false }
        return (try? PlexMediaServerClient(server: server)) != nil
    }

    static func enqueue(
        serverId: UUID,
        ratingKey: String,
        positionMs: Int,
        durationMs: Int,
        markPlayed: Bool
    ) {
        var entries = load()
        entries.removeAll {
            $0.serverId == serverId && $0.ratingKey == ratingKey
        }
        entries.append(
            Entry(
                serverId: serverId,
                ratingKey: ratingKey,
                positionMs: positionMs,
                durationMs: durationMs,
                markPlayed: markPlayed,
                createdAt: Date()
            )
        )
        save(entries)
        AppLog.offlineDebug("Queued offline scrobble ratingKey=\(ratingKey)")
    }

    @MainActor
    static func flush(servers: [PlexServer]) async {
        var entries = load()
        guard !entries.isEmpty else { return }

        var remaining: [Entry] = []
        for entry in entries {
            guard let server = servers.first(where: { $0.id == entry.serverId }),
                  canFlush(to: server)
            else {
                remaining.append(entry)
                continue
            }
            do {
                let client = try PlexMediaServerClient(server: server)
                if entry.markPlayed {
                    try await client.markItemPlayed(
                        ratingKey: entry.ratingKey,
                        durationMs: entry.durationMs > 0 ? entry.durationMs : nil
                    )
                } else if entry.positionMs > 5_000 {
                    try await client.reportPlaybackProgress(
                        ratingKey: entry.ratingKey,
                        timeMs: entry.positionMs
                    )
                }
                AppLog.offlineDebug("Flushed offline scrobble ratingKey=\(entry.ratingKey)")
            } catch {
                AppLog.offline("Offline scrobble flush failed: \(error.localizedDescription)")
                remaining.append(entry)
            }
        }
        save(remaining)
    }

    private static func load() -> [Entry] {
        let url = storeURL
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return decoded
    }

    private static func save(_ entries: [Entry]) {
        let url = storeURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static var storeURL: URL {
        OfflineDownloadStore.downloadsDirectory.appendingPathComponent(fileName)
    }
}
