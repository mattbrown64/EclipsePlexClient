import Foundation

/// Reports Plex watch state during playback and when the session ends.
@MainActor
enum PlaybackScrobbleReporter {
    private static var reportedSessionEndKeys = Set<String>()
    private static var toastThrottleKeys = Set<String>()
    private static var periodicTask: Task<Void, Never>?
    private static let periodicIntervalNanoseconds: UInt64 = 45_000_000_000

    static func resetSession() {
        stopPeriodicReporting()
        reportedSessionEndKeys.removeAll()
        toastThrottleKeys.removeAll()
    }

    /// Begin reporting progress and "playing" timeline to Plex every ~45s while the player is visible.
    static func startPeriodicReporting(
        request: PlaybackRequest?,
        positionMs: @escaping () -> Int,
        durationMs: @escaping () -> Int
    ) {
        stopPeriodicReporting()
        guard request?.scrobbleServerAndRatingKey != nil else { return }

        Task {
            await reportPlayingTimeline(
                request: request,
                positionMs: positionMs(),
                durationMs: durationMs()
            )
        }

        periodicTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: periodicIntervalNanoseconds)
                guard !Task.isCancelled else { break }
                await reportPeriodic(
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
        let timelineOk = await reportTimelineStopped(request: request, positionMs: positionMs, durationMs: durationMs)
        if timelineOk {
            guard let (server, ratingKey) = request?.scrobbleServerAndRatingKey else { return }
            reportedSessionEndKeys.insert("\(server.id.uuidString)|\(ratingKey)")
            return
        }
        await reportProgressFallback(
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
    ) async -> Bool {
        guard let (server, ratingKey) = request?.scrobbleServerAndRatingKey,
              server.usesLivePlexAPI
        else { return false }
        do {
            let client = try PlexMediaServerClient(server: server)
            try await client.reportTimeline(
                ratingKey: ratingKey,
                state: "playing",
                timeMs: positionMs,
                durationMs: durationMs
            )
            return true
        } catch {
            AppLog.network("Plex timeline playing failed: \(error.localizedDescription)")
            OfflineScrobbleQueue.enqueue(
                serverId: server.id,
                ratingKey: ratingKey,
                positionMs: max(positionMs, 0),
                durationMs: max(durationMs, 0),
                markPlayed: false
            )
            return false
        }
    }

    private static func reportTimelineStopped(
        request: PlaybackRequest?,
        positionMs: Int,
        durationMs: Int
    ) async -> Bool {
        guard let (server, ratingKey) = request?.scrobbleServerAndRatingKey,
              server.usesLivePlexAPI
        else { return false }
        do {
            let client = try PlexMediaServerClient(server: server)
            try await client.reportTimeline(
                ratingKey: ratingKey,
                state: "stopped",
                timeMs: positionMs,
                durationMs: durationMs
            )
            return true
        } catch {
            AppLog.network("Plex timeline stopped failed: \(error.localizedDescription)")
            OfflineScrobbleQueue.enqueue(
                serverId: server.id,
                ratingKey: ratingKey,
                positionMs: max(positionMs, 0),
                durationMs: max(durationMs, 0),
                markPlayed: true
            )
            return false
        }
    }

    private static func reportPeriodic(
        request: PlaybackRequest?,
        positionMs: Int,
        durationMs: Int
    ) async {
        let timelineOk = await reportPlayingTimeline(
            request: request,
            positionMs: positionMs,
            durationMs: durationMs
        )
        guard !timelineOk else { return }
        await reportProgressFallback(
            request: request,
            positionMs: positionMs,
            durationMs: durationMs,
            isSessionEnd: false
        )
    }

    private static func reportProgressFallback(
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
            } else {
                try await client.reportPlaybackProgress(ratingKey: ratingKey, timeMs: safePosition)
            }
            if isSessionEnd {
                reportedSessionEndKeys.insert(sessionKey)
            }
            AppLog.networkDebug(
                "Plex progress \(isSessionEnd ? "sessionEnd" : "periodic") nearEnd=\(nearEnd) pos=\(safePosition)"
            )
        } catch {
            AppLog.network("Plex watch report failed: \(error.localizedDescription)")
            if !isSessionEnd {
                let toastKey = "\(server.id.uuidString)|\(ratingKey)"
                if !toastThrottleKeys.contains(toastKey) {
                    toastThrottleKeys.insert(toastKey)
                    AppToastCenter.show("Couldn’t sync watch progress to Plex.")
                }
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
