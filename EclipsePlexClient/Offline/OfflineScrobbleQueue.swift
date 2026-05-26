//
//  OfflineScrobbleQueue.swift
//  EclipsePlexClient
//

import Foundation

/// Plex watch-state updates queued while offline or when the server is unreachable.
enum OfflineScrobbleQueue {
    private static let fileName = "offlineScrobbleQueue.v1.json"

    /// Coalesces flush work so scene-active / launch doesn't stack multiple
    /// main-thread-blocking passes over the queue.
    private actor FlushCoordinator {
        static let shared = FlushCoordinator()
        private var isRunning = false

        func schedule(servers: [PlexServer]) {
            guard !isRunning else { return }
            isRunning = true
            let snapshot = servers
            Task.detached(priority: .utility) {
                await OfflineScrobbleQueue.performFlush(servers: snapshot)
                await FlushCoordinator.shared.markFinished()
            }
        }

        func markFinished() {
            isRunning = false
        }
    }

    /// Cap retries so a permanently-broken entry stops spamming the network
    /// on every navigation-triggered flush. After this many failures the
    /// entry is dropped.
    private static let maxAttempts = 5

    /// Exponential backoff schedule (seconds) indexed by `attempts`. The last
    /// value sticks for any further retries up to `maxAttempts`. Tuned so the
    /// flush settles quickly on transient errors but doesn't hammer a server
    /// that's down: 30s → 2m → 10m → 1h → 6h.
    private static let backoffSchedule: [TimeInterval] = [30, 120, 600, 3_600, 21_600]

    /// Bound how much work one flush pass does so a large backlog can't run for
    /// minutes of sequential 30s URLSession timeouts while the user navigates.
    private static let maxEntriesPerPass = 8

    struct Entry: Codable, Hashable, Sendable {
        let serverId: UUID
        let ratingKey: String
        let positionMs: Int
        let durationMs: Int
        let markPlayed: Bool
        let createdAt: Date
        /// Decoded as 0 for legacy entries that don't have this field.
        var attempts: Int = 0
        /// When this entry is eligible to be retried; `nil` means "now".
        var nextRetryAt: Date?

        init(
            serverId: UUID,
            ratingKey: String,
            positionMs: Int,
            durationMs: Int,
            markPlayed: Bool,
            createdAt: Date,
            attempts: Int = 0,
            nextRetryAt: Date? = nil
        ) {
            self.serverId = serverId
            self.ratingKey = ratingKey
            self.positionMs = positionMs
            self.durationMs = durationMs
            self.markPlayed = markPlayed
            self.createdAt = createdAt
            self.attempts = attempts
            self.nextRetryAt = nextRetryAt
        }

        /// Custom decoder so legacy queue entries (saved before retry tracking
        /// was added) decode cleanly. Swift's synthesized `Decodable` does not
        /// apply property defaults when a key is missing, so we need to spell
        /// out `decodeIfPresent` for the new fields.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.serverId = try container.decode(UUID.self, forKey: .serverId)
            self.ratingKey = try container.decode(String.self, forKey: .ratingKey)
            self.positionMs = try container.decode(Int.self, forKey: .positionMs)
            self.durationMs = try container.decode(Int.self, forKey: .durationMs)
            self.markPlayed = try container.decode(Bool.self, forKey: .markPlayed)
            self.createdAt = try container.decode(Date.self, forKey: .createdAt)
            self.attempts = try container.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
            self.nextRetryAt = try container.decodeIfPresent(Date.self, forKey: .nextRetryAt)
        }
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

    /// Fire-and-forget flush on a background priority. Never blocks the main
    /// actor — a previous `@MainActor flush` could monopolize the UI thread
    /// while URLSession timed out on failed scrobbles, making sidebar taps
    /// (including library selection) appear dead with no press feedback.
    static func scheduleFlush(servers: [PlexServer]) {
        Task {
            await FlushCoordinator.shared.schedule(servers: servers)
        }
    }

    /// Awaitable flush for tests and tooling. Prefer `scheduleFlush` at UI
    /// boundaries so navigation stays responsive.
    static func flush(servers: [PlexServer]) async {
        await performFlush(servers: servers)
    }

    static func performFlush(servers: [PlexServer]) async {
        let entries = load()
        guard !entries.isEmpty else { return }
        let now = Date()

        // Reuse a single `PlexMediaServerClient` per server across all of its
        // queued entries; previously the loop spun up a fresh client (and
        // therefore re-resolved the active connection) for every scrobble.
        var clientsByServer: [UUID: PlexMediaServerClient] = [:]
        var remaining: [Entry] = []
        var networkAttempts = 0
        for (index, entry) in entries.enumerated() {
            if Task.isCancelled {
                remaining.append(contentsOf: entries[index...])
                break
            }
            if networkAttempts >= maxEntriesPerPass {
                remaining.append(entry)
                continue
            }
            // Honor the backoff schedule so failing entries don't hammer the
            // network on every navigation that triggers a flush.
            if let nextRetry = entry.nextRetryAt, nextRetry > now {
                remaining.append(entry)
                continue
            }
            guard let server = servers.first(where: { $0.id == entry.serverId }),
                  canFlush(to: server)
            else {
                remaining.append(entry)
                continue
            }
            let client: PlexMediaServerClient
            if let cached = clientsByServer[server.id] {
                client = cached
            } else if let made = try? PlexMediaServerClient(server: server) {
                clientsByServer[server.id] = made
                client = made
            } else {
                remaining.append(entry)
                continue
            }
            do {
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
                networkAttempts += 1
            } catch {
                networkAttempts += 1
                let disposition = retryDisposition(for: error, currentAttempts: entry.attempts)
                switch disposition {
                case .drop(let reason):
                    AppLog.offline("Dropping offline scrobble ratingKey=\(entry.ratingKey): \(reason)")
                case .reschedule(let nextAttempt, let delay):
                    var updated = entry
                    updated.attempts = nextAttempt
                    updated.nextRetryAt = Date().addingTimeInterval(delay)
                    AppLog.offline(
                        "Offline scrobble flush failed (\(error.localizedDescription)); attempts=\(nextAttempt) retry in \(Int(delay))s"
                    )
                    remaining.append(updated)
                }
            }
        }
        save(remaining)
    }

    /// Inspect a flush error and decide whether to drop or reschedule.
    private static func retryDisposition(
        for error: Error,
        currentAttempts: Int
    ) -> RetryDisposition {
        // Permanent 4xx (except 408 timeout / 429 rate-limit) are not going to
        // recover; drop them rather than re-flush forever.
        if let api = error as? PlexAPIError, case .httpStatus(let code, _) = api {
            if (400 ... 499).contains(code), code != 408, code != 429 {
                return .drop(reason: "HTTP \(code) is non-recoverable")
            }
        }
        let nextAttempts = currentAttempts + 1
        if nextAttempts >= maxAttempts {
            return .drop(reason: "exceeded max retry attempts")
        }
        let delay = backoffSchedule[min(currentAttempts, backoffSchedule.count - 1)]
        return .reschedule(nextAttempts: nextAttempts, delay: delay)
    }

    private enum RetryDisposition {
        case drop(reason: String)
        case reschedule(nextAttempts: Int, delay: TimeInterval)
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
