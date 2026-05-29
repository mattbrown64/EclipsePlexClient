import CoreGraphics
import Foundation

/// Identifies a Plex item for resume position persistence.
struct PlaybackResumeContext: Hashable, Sendable {
    let serverId: UUID
    let ratingKey: String
}

/// One playable URL (primary or fallback) for VLC.
struct PlaybackStreamCandidate: Sendable, Hashable {
    let url: URL
    let streamKind: PlaybackStreamKind
    let label: String
}

enum PlaybackStreamKind: Sendable {
    case localFile
    case remote
    case plexTranscode
    case plexDirect
}

/// Everything VLC needs after resolving a `PlaybackRequest`.
struct ResolvedPlayback: Sendable {
    let candidates: [PlaybackStreamCandidate]
    let httpHeaderFields: [String: String]
    let resumePositionMs: Int?
    let resumeContext: PlaybackResumeContext?
    let streamOptions: PlaybackStreamOptions
    let plexSubtitleStreams: [PlexSubtitleStream]
    let sourceVideoSize: CGSize?
    let playbackMarkers: [PlexPlaybackMarker]
    /// When true, do not read/write `PlaybackPositionStore` (Pseudo-TV tune-in).
    let suppressLocalResume: Bool

    var url: URL { candidates[0].url }
    var streamKind: PlaybackStreamKind { candidates[0].streamKind }

    /// Changes when stream URLs or transcode options change (used to restart VLC).
    var streamSignature: String {
        let urls = candidates.map(\.url.absoluteString).joined(separator: "|")
        return "\(urls)|\(streamOptions.videoResolution.rawValue)|\(streamOptions.subtitleSelection.plexTranscodeValue)"
    }

    init(
        candidates: [PlaybackStreamCandidate],
        httpHeaderFields: [String: String] = [:],
        resumePositionMs: Int? = nil,
        resumeContext: PlaybackResumeContext? = nil,
        streamOptions: PlaybackStreamOptions = .current,
        plexSubtitleStreams: [PlexSubtitleStream] = [],
        sourceVideoSize: CGSize? = nil,
        playbackMarkers: [PlexPlaybackMarker] = [],
        suppressLocalResume: Bool = false
    ) {
        precondition(!candidates.isEmpty)
        self.candidates = candidates
        self.httpHeaderFields = httpHeaderFields
        self.resumePositionMs = resumePositionMs
        self.resumeContext = resumeContext
        self.streamOptions = streamOptions
        self.plexSubtitleStreams = plexSubtitleStreams
        self.sourceVideoSize = sourceVideoSize
        self.playbackMarkers = playbackMarkers
        self.suppressLocalResume = suppressLocalResume
    }

    init(
        url: URL,
        streamKind: PlaybackStreamKind,
        httpHeaderFields: [String: String] = [:],
        resumePositionMs: Int? = nil,
        resumeContext: PlaybackResumeContext? = nil,
        label: String = "Primary"
    ) {
        self.init(
            candidates: [PlaybackStreamCandidate(url: url, streamKind: streamKind, label: label)],
            httpHeaderFields: httpHeaderFields,
            resumePositionMs: resumePositionMs,
            resumeContext: resumeContext
        )
    }

    func withResumePositionMs(_ ms: Int?) -> ResolvedPlayback {
        ResolvedPlayback(
            candidates: candidates,
            httpHeaderFields: httpHeaderFields,
            resumePositionMs: ms,
            resumeContext: resumeContext,
            streamOptions: streamOptions,
            plexSubtitleStreams: plexSubtitleStreams,
            sourceVideoSize: sourceVideoSize,
            playbackMarkers: playbackMarkers,
            suppressLocalResume: suppressLocalResume
        )
    }
}
