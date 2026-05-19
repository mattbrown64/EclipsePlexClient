import Foundation

/// What to play — Plex stream, local file, or bundled demo (previews).
nonisolated enum PlaybackRequest: Hashable, Sendable {
    case plex(server: PlexServer, ratingKey: String, title: String?)
    case remoteStream(URL)
    case localFile(URL)
    case bundledDemo

    var displayTitle: String? {
        switch self {
        case .plex(_, _, let title): return title
        case .remoteStream: return nil
        case .localFile(let url): return url.lastPathComponent
        case .bundledDemo: return "Savior.mkv"
        }
    }
}

enum PlaybackResolver {
    private static let bundledResource = (name: "Savior", ext: "mkv")

    /// Resolves a `PlaybackRequest` for VLC (remote Plex URL or sandbox-safe local path).
    static func resolve(_ request: PlaybackRequest) async throws -> ResolvedPlayback {
        NSLog("[EclipsePlex] PlaybackResolver.resolve start")
        switch request {
        case .plex(let server, let ratingKey, _):
            guard server.usesLivePlexAPI else {
                throw PlexAPIError.serverNotConfiguredForLiveAPI
            }
            let client = try PlexMediaServerClient(server: server)
            let stream = try await client.resolvePlaybackStream(ratingKey: ratingKey, server: server)
            let kind: PlaybackStreamKind = switch stream.delivery {
            case .transcodeHLS, .transcodeHTTP: .plexTranscode
            case .directPlay: .plexDirect
            }
            return ResolvedPlayback(
                url: stream.url,
                streamKind: kind,
                httpHeaderFields: stream.httpHeaderFields
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

    var errorDescription: String? {
        switch self {
        case .bundledFileMissing(let name):
            return "\(name) was not found in the app bundle."
        }
    }
}
