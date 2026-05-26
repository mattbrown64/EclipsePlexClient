import CoreGraphics
import Foundation

/// Target transcode / playback quality (Plex `videoResolution` when transcoding).
enum PlaybackVideoResolution: String, CaseIterable, Identifiable, Codable, Sendable {
    case original
    case p1080
    case p720
    case p480

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .original: "Original"
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        }
    }

    /// When true, the transcode fallback uses this resolution (direct play is still attempted first).
    var forcesTranscode: Bool { self != .original }

    var plexVideoResolution: String {
        switch self {
        case .original, .p720: return "1280x720"
        case .p1080: return "1920x1080"
        case .p480: return "854x480"
        }
    }
}

/// Subtitle selection for Plex transcode and default VLC behavior.
enum PlaybackSubtitleSelection: Equatable, Sendable {
    case off
    case auto
    case plexStream(id: String, displayName: String)

    var menuTitle: String {
        switch self {
        case .off: "Off"
        case .auto: "Auto"
        case .plexStream(_, let displayName): displayName
        }
    }

    /// Value for Plex universal transcode `subtitles` query parameter.
    var plexTranscodeValue: String {
        switch self {
        case .off: return "none"
        case .auto: return "auto"
        case .plexStream(let id, _): return id
        }
    }

    var requiresTranscodeBurnIn: Bool {
        if case .plexStream = self { return true }
        return false
    }
}

/// Plex subtitle stream from item metadata (external/burn-in via transcode).
struct PlexSubtitleStream: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
}

/// Options passed into Plex playback resolution (also persisted for the next session).
struct PlaybackStreamOptions: Sendable, Equatable {
    var videoResolution: PlaybackVideoResolution
    var subtitleSelection: PlaybackSubtitleSelection

    static var current: PlaybackStreamOptions {
        PlaybackPreferences.load()
    }
}

/// VLC playback rate presets.
enum PlaybackSpeed: Float, CaseIterable, Identifiable, Sendable {
    case s075 = 0.75
    case normal = 1.0
    case s125 = 1.25
    case s150 = 1.5
    case s200 = 2.0

    var id: Float { rawValue }

    var menuTitle: String {
        switch self {
        case .s075: "0.75×"
        case .normal: "Normal"
        case .s125: "1.25×"
        case .s150: "1.5×"
        case .s200: "2×"
        }
    }

    static func nearest(to rate: Float) -> PlaybackSpeed {
        allCases.min(by: { abs($0.rawValue - rate) < abs($1.rawValue - rate) }) ?? .normal
    }
}

enum PlaybackPreferences {
    private static let resolutionKey = "playback.videoResolution.v1"
    private static let subtitleKey = "playback.subtitleSelection.v1"
    private static let speedKey = "playback.speed.v1"
    private static let directPlayLANKey = "playback.preferDirectPlayLAN.v1"
    private static let preferHLSKey = "playback.preferHLS.v1"

    static var preferDirectPlayOnLAN: Bool {
        get {
            if UserDefaults.standard.object(forKey: directPlayLANKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: directPlayLANKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: directPlayLANKey) }
    }

    static var preferHLSTranscode: Bool {
        get { UserDefaults.standard.bool(forKey: preferHLSKey) }
        set { UserDefaults.standard.set(newValue, forKey: preferHLSKey) }
    }

    static func load() -> PlaybackStreamOptions {
        let defaults = UserDefaults.standard
        let resolution: PlaybackVideoResolution
        if let raw = defaults.string(forKey: resolutionKey),
           let value = PlaybackVideoResolution(rawValue: raw) {
            resolution = value
        } else {
            resolution = .original
        }

        let subtitle: PlaybackSubtitleSelection
        if let data = defaults.data(forKey: subtitleKey),
           let decoded = try? JSONDecoder().decode(PlaybackSubtitleSelection.self, from: data) {
            subtitle = decoded
        } else {
            subtitle = .auto
        }

        return PlaybackStreamOptions(videoResolution: resolution, subtitleSelection: subtitle)
    }

    static func save(_ options: PlaybackStreamOptions) {
        let defaults = UserDefaults.standard
        defaults.set(options.videoResolution.rawValue, forKey: resolutionKey)
        if let data = try? JSONEncoder().encode(options.subtitleSelection) {
            defaults.set(data, forKey: subtitleKey)
        }
    }

    static func saveVideoResolution(_ resolution: PlaybackVideoResolution) {
        var options = load()
        options.videoResolution = resolution
        save(options)
    }

    static func saveSubtitleSelection(_ selection: PlaybackSubtitleSelection) {
        var options = load()
        options.subtitleSelection = selection
        save(options)
    }

    static func loadPlaybackRate() -> Float {
        let stored = UserDefaults.standard.float(forKey: speedKey)
        if stored > 0 { return stored }
        return PlaybackSpeed.normal.rawValue
    }

    static func savePlaybackRate(_ rate: Float) {
        UserDefaults.standard.set(rate, forKey: speedKey)
    }
}

extension PlaybackSubtitleSelection: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, streamID, title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "off": self = .off
        case "auto": self = .auto
        case "plex":
            let id = try container.decode(String.self, forKey: .streamID)
            let title = try container.decode(String.self, forKey: .title)
            self = .plexStream(id: id, displayName: title)
        default:
            self = .auto
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .off:
            try container.encode("off", forKey: .kind)
        case .auto:
            try container.encode("auto", forKey: .kind)
        case .plexStream(let id, let title):
            try container.encode("plex", forKey: .kind)
            try container.encode(id, forKey: .streamID)
            try container.encode(title, forKey: .title)
        }
    }
}
