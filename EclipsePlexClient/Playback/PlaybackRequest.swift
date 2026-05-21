import Foundation

/// What to play — Plex stream, local file, or bundled demo (previews).
nonisolated enum PlaybackRequest: Hashable, Sendable {
    case plex(server: PlexServer, ratingKey: String, title: String?, episodeContext: EpisodePlayContext? = nil)
    /// Offline Plex item — resolve the file on disk at playback time via `OfflineDownloadManager`.
    case downloadedPlexItem(server: PlexServer, ratingKey: String, title: String?)
    case remoteStream(URL)
    case localFile(URL)
    case bundledDemo

    var displayTitle: String? {
        switch self {
        case .plex(_, _, let title, _): return title
        case .downloadedPlexItem(_, _, let title): return title
        case .remoteStream: return nil
        case .localFile(let url): return url.lastPathComponent
        case .bundledDemo: return "Savior.mkv"
        }
    }

    var scrobbleServerAndRatingKey: (PlexServer, String)? {
        switch self {
        case .plex(let server, let ratingKey, _, _): return (server, ratingKey)
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
        NSLog("[EclipsePlex] PlaybackResolver.resolve start")
        switch request {
        case .plex(let server, let ratingKey, _, _):
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
            let resumeMs = PlaybackPositionStore.load(serverId: server.id, ratingKey: ratingKey)
            return ResolvedPlayback(
                candidates: candidates,
                httpHeaderFields: resolution.streams[0].httpHeaderFields,
                resumePositionMs: resumeMs,
                resumeContext: PlaybackResumeContext(serverId: server.id, ratingKey: ratingKey),
                streamOptions: options,
                plexSubtitleStreams: resolution.subtitleStreams,
                sourceVideoSize: resolution.sourceVideoSize,
                playbackMarkers: resolution.playbackMarkers
            )

        case .downloadedPlexItem(let server, let ratingKey, _):
            guard let fileURL = offlineFileURL else {
                throw PlaybackResolverError.offlineFileMissing
            }
            NSLog("[EclipsePlex] Offline playback file: %@", fileURL.path)
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
