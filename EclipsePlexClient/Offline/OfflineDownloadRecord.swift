//
//  OfflineDownloadRecord.swift
//  EclipsePlexClient
//

import Foundation

/// One offline movie/episode download on disk.
struct OfflineDownloadRecord: Identifiable, Codable, Hashable, Sendable {
    enum MediaKind: String, Codable, Sendable {
        case movie
        case episode
        case unknown
    }

    enum State: String, Codable, Sendable {
        case pending
        case downloading
        case completed
        case failed
        case cancelled
    }

    let id: UUID
    let serverId: UUID
    let serverName: String
    let ratingKey: String
    let title: String
    var thumbPath: String?
    /// Show poster for TV episodes (Plex `grandparentThumb`), separate from episode `thumbPath`.
    var showThumbPath: String?
    var mediaKind: MediaKind
    var showTitle: String?
    var showRatingKey: String?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var episodeTitle: String?
    let quality: PlaybackVideoResolution
    var state: State
    var progress: Double
    var bytesWritten: Int64
    var expectedBytes: Int64?
    /// Path relative to the app downloads directory.
    var relativeFilePath: String?
    var errorMessage: String?
    let createdAt: Date
    var completedAt: Date?

    var isPlayable: Bool {
        state == .completed && relativeFilePath != nil
    }

    var displayTitle: String {
        if mediaKind == .episode, let episodeTitle, !episodeTitle.isEmpty {
            return episodeTitle
        }
        return title
    }

    var episodeDisplayTitle: String {
        if let episodeTitle, !episodeTitle.isEmpty { return episodeTitle }
        if let seasonNumber, let episodeNumber {
            return "Episode \(episodeNumber)"
        }
        return title
    }

    var resolvedMediaKind: MediaKind {
        if mediaKind != .unknown { return mediaKind }
        if let inferred = Self.inferKind(fromTitle: title) {
            return inferred.kind
        }
        return .movie
    }

    var resolvedShowTitle: String {
        if let showTitle, !showTitle.isEmpty { return showTitle }
        if let parsed = Self.inferKind(fromTitle: title) {
            return parsed.showTitle ?? title
        }
        return title
    }

    var resolvedSeasonNumber: Int? {
        seasonNumber ?? Self.inferKind(fromTitle: title)?.season
    }

    var resolvedEpisodeNumber: Int? {
        episodeNumber ?? Self.inferKind(fromTitle: title)?.episode
    }

    /// Groups episodes in the offline TV library (per origin server + show title).
    var showGroupKey: String {
        "\(serverId.uuidString)|\(resolvedShowTitle.lowercased())"
    }

    init(
        id: UUID,
        serverId: UUID,
        serverName: String,
        ratingKey: String,
        title: String,
        thumbPath: String?,
        showThumbPath: String? = nil,
        mediaKind: MediaKind,
        showTitle: String?,
        showRatingKey: String?,
        seasonNumber: Int?,
        episodeNumber: Int?,
        episodeTitle: String?,
        quality: PlaybackVideoResolution,
        state: State,
        progress: Double,
        bytesWritten: Int64,
        expectedBytes: Int64?,
        relativeFilePath: String?,
        errorMessage: String?,
        createdAt: Date,
        completedAt: Date?
    ) {
        self.id = id
        self.serverId = serverId
        self.serverName = serverName
        self.ratingKey = ratingKey
        self.title = title
        self.thumbPath = thumbPath
        self.showThumbPath = showThumbPath
        self.mediaKind = mediaKind
        self.showTitle = showTitle
        self.showRatingKey = showRatingKey
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
        self.quality = quality
        self.state = state
        self.progress = progress
        self.bytesWritten = bytesWritten
        self.expectedBytes = expectedBytes
        self.relativeFilePath = relativeFilePath
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    static func new(
        server: PlexServer,
        ratingKey: String,
        title: String,
        thumbPath: String?,
        showThumbPath: String? = nil,
        quality: PlaybackVideoResolution,
        mediaKind: MediaKind = .unknown,
        showTitle: String? = nil,
        showRatingKey: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil
    ) -> OfflineDownloadRecord {
        OfflineDownloadRecord(
            id: UUID(),
            serverId: server.id,
            serverName: server.name,
            ratingKey: ratingKey,
            title: title,
            thumbPath: thumbPath,
            showThumbPath: showThumbPath,
            mediaKind: mediaKind,
            showTitle: showTitle,
            showRatingKey: showRatingKey,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            episodeTitle: episodeTitle,
            quality: quality,
            state: .pending,
            progress: 0,
            bytesWritten: 0,
            expectedBytes: nil,
            relativeFilePath: nil,
            errorMessage: nil,
            createdAt: Date(),
            completedAt: nil
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, serverId, serverName, ratingKey, title, thumbPath, showThumbPath
        case mediaKind, showTitle, showRatingKey, seasonNumber, episodeNumber, episodeTitle
        case quality, state, progress, bytesWritten, expectedBytes, relativeFilePath
        case errorMessage, createdAt, completedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        serverId = try c.decode(UUID.self, forKey: .serverId)
        serverName = try c.decode(String.self, forKey: .serverName)
        ratingKey = try c.decode(String.self, forKey: .ratingKey)
        title = try c.decode(String.self, forKey: .title)
        thumbPath = try c.decodeIfPresent(String.self, forKey: .thumbPath)
        showThumbPath = try c.decodeIfPresent(String.self, forKey: .showThumbPath)
        mediaKind = try c.decodeIfPresent(MediaKind.self, forKey: .mediaKind) ?? .unknown
        showTitle = try c.decodeIfPresent(String.self, forKey: .showTitle)
        showRatingKey = try c.decodeIfPresent(String.self, forKey: .showRatingKey)
        seasonNumber = try c.decodeIfPresent(Int.self, forKey: .seasonNumber)
        episodeNumber = try c.decodeIfPresent(Int.self, forKey: .episodeNumber)
        episodeTitle = try c.decodeIfPresent(String.self, forKey: .episodeTitle)
        quality = try c.decode(PlaybackVideoResolution.self, forKey: .quality)
        state = try c.decode(State.self, forKey: .state)
        progress = try c.decode(Double.self, forKey: .progress)
        bytesWritten = try c.decode(Int64.self, forKey: .bytesWritten)
        expectedBytes = try c.decodeIfPresent(Int64.self, forKey: .expectedBytes)
        relativeFilePath = try c.decodeIfPresent(String.self, forKey: .relativeFilePath)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }

    /// Legacy titles from batch enqueue: `"Show Name · S1E2"`.
    static func inferKindForMigration(title: String) -> (kind: MediaKind, showTitle: String?, season: Int?, episode: Int?)? {
        inferKind(fromTitle: title)
    }

    private static func inferKind(fromTitle title: String) -> (kind: MediaKind, showTitle: String?, season: Int?, episode: Int?)? {
        let pattern = #"^(.+?) · S(\d+)E(\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let showRange = Range(match.range(at: 1), in: title),
              let seasonRange = Range(match.range(at: 2), in: title),
              let episodeRange = Range(match.range(at: 3), in: title)
        else { return nil }
        let show = String(title[showRange])
        let season = Int(title[seasonRange])
        let episode = Int(title[episodeRange])
        return (.episode, show, season, episode)
    }
}
