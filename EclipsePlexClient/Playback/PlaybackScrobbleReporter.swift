import Foundation

/// Reports Plex watch state during playback and when the session ends.
@MainActor
enum PlaybackScrobbleReporter {
    private static var reportedSessionEndKeys = Set<String>()
    private static var periodicTask: Task<Void, Never>?
    private static let periodicIntervalNanoseconds: UInt64 = 45_000_000_000

    static func resetSession() {
        stopPeriodicReporting()
        reportedSessionEndKeys.removeAll()
    }

    /// Begin reporting progress and "playing" timeline to Plex every ~45s while the player is visible.
    static func startPeriodicReporting(
        request: PlaybackRequest?,
        positionMs: @escaping () -> Int,
        durationMs: @escaping () -> Int
    ) {
        stopPeriodicReporting()
        guard request?.scrobbleServerAndRatingKey != nil else { return }

        periodicTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: periodicIntervalNanoseconds)
                guard !Task.isCancelled else { break }
                await reportProgress(
                    request: request,
                    positionMs: positionMs(),
                    durationMs: durationMs(),
                    isSessionEnd: false
                )
                await reportPlayingTimeline(
                    request: request,
                    positionMs: positionMs(),
                    durationMs: durationMs()
                )
            }
        }
    }

    static func stopPeriodicReporting() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    /// Call when the user leaves the player or playback ends.
    static func reportSessionEnd(
        request: PlaybackRequest?,
        positionMs: Int,
        durationMs: Int
    ) async {
        stopPeriodicReporting()
        await reportTimelineStopped(request: request, positionMs: positionMs, durationMs: durationMs)
        await reportProgress(
            request: request,
            positionMs: positionMs,
            durationMs: durationMs,
            isSessionEnd: true
        )
    }

    private static func reportPlayingTimeline(
        request: PlaybackRequest?,
        positionMs: Int,
        durationMs: Int
    ) async {
        guard let (server, ratingKey) = request?.scrobbleServerAndRatingKey,
              server.usesLivePlexAPI,
              positionMs > 0
        else { return }
        do {
            let client = try PlexMediaServerClient(server: server)
            try await client.reportTimeline(
                ratingKey: ratingKey,
                state: "playing",
                timeMs: positionMs,
                durationMs: durationMs
            )
        } catch {
            NSLog("[EclipsePlex] Plex timeline playing failed: %@", error.localizedDescription)
        }
    }

    private static func reportTimelineStopped(
        request: PlaybackRequest?,
        positionMs: Int,
        durationMs: Int
    ) async {
        guard let (server, ratingKey) = request?.scrobbleServerAndRatingKey,
              server.usesLivePlexAPI
        else { return }
        do {
            let client = try PlexMediaServerClient(server: server)
            try await client.reportTimeline(
                ratingKey: ratingKey,
                state: "stopped",
                timeMs: positionMs,
                durationMs: durationMs
            )
        } catch {
            NSLog("[EclipsePlex] Plex timeline stopped failed: %@", error.localizedDescription)
        }
    }

    private static func reportProgress(
        request: PlaybackRequest?,
        positionMs: Int,
        durationMs: Int,
        isSessionEnd: Bool
    ) async {
        guard let (server, ratingKey) = request?.scrobbleServerAndRatingKey,
              server.usesLivePlexAPI
        else { return }

        let sessionKey = "\(server.id.uuidString)|\(ratingKey)"
        if isSessionEnd, reportedSessionEndKeys.contains(sessionKey) {
            return
        }

        let safeDuration = max(durationMs, 0)
        let safePosition = max(positionMs, 0)
        let nearEnd = safeDuration > 0 && (
            safePosition >= safeDuration - 30_000
                || Double(safePosition) >= Double(safeDuration) * 0.9
        )

        do {
            let client = try PlexMediaServerClient(server: server)
            if nearEnd {
                try await client.markItemPlayed(ratingKey: ratingKey, durationMs: safeDuration)
            } else if safePosition > 5_000 {
                try await client.reportPlaybackProgress(ratingKey: ratingKey, timeMs: safePosition)
            } else {
                return
            }
            if isSessionEnd {
                reportedSessionEndKeys.insert(sessionKey)
            }
            NSLog(
                "[EclipsePlex] Plex progress %@ (nearEnd=%d pos=%d)",
                isSessionEnd ? "sessionEnd" : "periodic",
                nearEnd ? 1 : 0,
                safePosition
            )
        } catch {
            NSLog("[EclipsePlex] Plex watch report failed: %@", error.localizedDescription)
            if !isSessionEnd {
                AppToastCenter.show("Couldn’t sync watch progress to Plex.")
            }
            OfflineScrobbleQueue.enqueue(
                serverId: server.id,
                ratingKey: ratingKey,
                positionMs: safePosition,
                durationMs: safeDuration,
                markPlayed: nearEnd
            )
        }
    }
}
