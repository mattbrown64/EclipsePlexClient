import Foundation

/// URL handed to VLC after resolving a `PlaybackRequest`.
struct ResolvedPlayback: Sendable {
    let url: URL
    let streamKind: PlaybackStreamKind
    /// Plex auth headers for VLC segment requests (`http-extra-headers`).
    let httpHeaderFields: [String: String]

    init(url: URL, streamKind: PlaybackStreamKind, httpHeaderFields: [String: String] = [:]) {
        self.url = url
        self.streamKind = streamKind
        self.httpHeaderFields = httpHeaderFields
    }
}

enum PlaybackStreamKind: Sendable {
    case localFile
    case remote
    case plexTranscode
    case plexDirect
}
