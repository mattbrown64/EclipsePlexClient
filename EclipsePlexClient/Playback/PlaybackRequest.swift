import Foundation

/// How tune-in position is chosen for Plex items.
nonisolated enum PlaybackTuneInMode: Hashable, Sendable {
    case normal
    /// Virtual channel offset only; ignores personal resume stores.
    case pseudoTVLive
}

/// What to play — Plex stream, local file, or bundled demo (previews).
nonisolated enum PlaybackRequest: Hashable, Sendable {
    case plex(
        server: PlexServer,
        ratingKey: String,
        title: String?,
        episodeContext: EpisodePlayContext? = nil,
        startFromBeginning: Bool = false,
        plexResumePositionMs: Int? = nil,
        tuneInMode: PlaybackTuneInMode = .normal
    )
    /// Offline Plex item — resolve the file on disk at playback time via `OfflineDownloadManager`.
    case downloadedPlexItem(server: PlexServer, ratingKey: String, title: String?)
    case remoteStream(URL)
    case localFile(URL)
    case bundledDemo

    var displayTitle: String? {
        switch self {
        case .plex(_, _, let title, _, _, _, _): return title
        case .downloadedPlexItem(_, _, let title): return title
        case .remoteStream: return nil
        case .localFile(let url): return url.lastPathComponent
        case .bundledDemo: return "Savior.mkv"
        }
    }

    var scrobbleServerAndRatingKey: (PlexServer, String)? {
        switch self {
        case .plex(let server, let ratingKey, _, _, _, _, _): return (server, ratingKey)
        case .downloadedPlexItem(let server, let ratingKey, _): return (server, ratingKey)
        default: return nil
        }
    }
}

enum PlaybackResolver {
    private static let bundledResource = (name: "Savior", ext: "mkv")

    /// Resolves a `PlaybackRequest` for VLC (remote Plex URL or sandbox-safe local path).
    static func resolve(
        _ request: PlaybackRequest,
        offlineFileURL: URL? = nil,
        options: PlaybackStreamOptions = .current
    ) async throws -> ResolvedPlayback {
        AppLog.playbackDebug("PlaybackResolver.resolve start")
        switch request {
        case .plex(let server, let ratingKey, _, _, let startFromBeginning, let plexResumePositionMs, let tuneInMode):
            guard server.usesLivePlexAPI else {
                throw PlexAPIError.serverNotConfiguredForLiveAPI
            }
            let client = try PlexMediaServerClient(server: server)
            let resolution = try await client.resolvePlaybackStreamCandidates(
                ratingKey: ratingKey,
                server: server,
                options: options
            )
            let candidates = resolution.streams.map { stream in
                let kind: PlaybackStreamKind = switch stream.delivery {
                case .transcodeHTTP, .transcodeHLS: .plexTranscode
                case .directPlay: .plexDirect
                }
                return PlaybackStreamCandidate(
                    url: stream.url,
                    streamKind: kind,
                    label: stream.label
                )
            }
            let resumeMs = Self.resolveResumePositionMs(
                serverId: server.id,
                ratingKey: ratingKey,
                startFromBeginning: startFromBeginning,
                plexResumePositionMs: plexResumePositionMs,
                tuneInMode: tuneInMode
            )
            return ResolvedPlayback(
                candidates: candidates,
                httpHeaderFields: resolution.streams[0].httpHeaderFields,
                resumePositionMs: resumeMs,
                resumeContext: PlaybackResumeContext(serverId: server.id, ratingKey: ratingKey),
                streamOptions: options,
                plexSubtitleStreams: resolution.subtitleStreams,
                sourceVideoSize: resolution.sourceVideoSize,
                playbackMarkers: resolution.playbackMarkers,
                suppressLocalResume: tuneInMode == .pseudoTVLive
            )

        case .downloadedPlexItem(let server, let ratingKey, _):
            guard let fileURL = offlineFileURL else {
                throw PlaybackResolverError.offlineFileMissing
            }
            AppLog.playbackDebug("Offline playback file: \(fileURL.lastPathComponent)")
            let resumeMs = PlaybackPositionStore.load(serverId: server.id, ratingKey: ratingKey)
            return ResolvedPlayback(
                url: try LocalMediaURL.forPlayback(fileURL),
                streamKind: .localFile,
                resumePositionMs: resumeMs,
                resumeContext: PlaybackResumeContext(serverId: server.id, ratingKey: ratingKey)
            )

        case .remoteStream(let url):
            return ResolvedPlayback(url: url, streamKind: .remote)

        case .localFile(let url):
            return ResolvedPlayback(
                url: try LocalMediaURL.forPlayback(url),
                streamKind: .localFile
            )

        case .bundledDemo:
            guard let bundleURL = Bundle.main.url(
                forResource: bundledResource.name,
                withExtension: bundledResource.ext
            ) else {
                throw PlaybackResolverError.bundledFileMissing(
                    "\(bundledResource.name).\(bundledResource.ext)"
                )
            }
            return ResolvedPlayback(
                url: try LocalMediaURL.forPlayback(bundleURL),
                streamKind: .localFile
            )
        }
    }

    private static func resolveResumePositionMs(
        serverId: UUID,
        ratingKey: String,
        startFromBeginning: Bool,
        plexResumePositionMs: Int?,
        tuneInMode: PlaybackTuneInMode
    ) -> Int? {
        if tuneInMode == .pseudoTVLive {
            if let ms = plexResumePositionMs, ms > 0 { return ms }
            return nil
        }
        if startFromBeginning {
            PlaybackPositionStore.clear(serverId: serverId, ratingKey: ratingKey)
            return nil
        }
        let localMs = PlaybackPositionStore.load(serverId: serverId, ratingKey: ratingKey)
        let candidates = [localMs, plexResumePositionMs].compactMap { $0 }.filter { $0 > 5_000 }
        guard !candidates.isEmpty else { return nil }
        let best = candidates.max()!
        if PlaybackPreferences.alwaysResumeWhereLeftOff {
            return best
        }
        // Explicit resume paths pass plex/local offsets; generic Watch without resume uses nil at call site.
        return plexResumePositionMs != nil || localMs != nil ? best : nil
    }
}

enum PlaybackResolverError: LocalizedError {
    case bundledFileMissing(String)
    case offlineFileMissing

    var errorDescription: String? {
        switch self {
        case .bundledFileMissing(let name):
            return "\(name) was not found in the app bundle."
        case .offlineFileMissing:
            return "The offline download file is missing. Open Downloads and try downloading again."
        }
    }
}
