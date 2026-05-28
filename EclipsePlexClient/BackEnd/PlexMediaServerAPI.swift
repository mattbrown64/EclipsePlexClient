//
//  PlexMediaServerAPI.swift
//  EclipsePlexClient
//
//  Minimal Plex Media Server JSON client: sections, library metadata, children.
//

import Foundation
import OSLog

// MARK: - Errors

nonisolated enum PlexAPIError: LocalizedError, Sendable {
    case serverNotConfiguredForLiveAPI
    case invalidURL
    case httpStatus(code: Int, bodySnippet: String?)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .serverNotConfiguredForLiveAPI:
            return "This server needs a reachable URL and Plex token."
        case .invalidURL:
            return "Could not build a request URL for the Plex server."
        case .httpStatus(let code, _):
            return "Plex server returned HTTP \(code)."
        case .decodingFailed(let message):
            return message
        }
    }
}

// MARK: - HTTP helpers

nonisolated enum PlexHTTPConstants {
    static var clientIdentifier: String {
        UserDefaults.standard.string(forKey: "plexClientIdentifier") ?? {
            let uuid = UUID().uuidString
            UserDefaults.standard.set(uuid, forKey: "plexClientIdentifier")
            return uuid
        }()
    }

    static let productName = "EclipsePlexClient"
    static var productVersion: String { AppVersion.marketingVersion }
}

// MARK: - JSON DTOs

nonisolated struct PlexMediaRoot: Decodable {
    let MediaContainer: PlexMediaContainerDecoded
}

nonisolated struct PlexMediaContainerDecoded: Decodable {
    let size: Int?
    let totalSize: Int?
    let offset: Int?
    let friendlyName: String?
    private let Metadata: PlexRecordList?
    private let Directory: PlexRecordList?

    var records: [PlexRecordDTO] {
        (Metadata?.values ?? []) + (Directory?.values ?? [])
    }
}

/// Plex sometimes returns a single object or an array for `Metadata` / `Directory`.
nonisolated struct PlexRecordList: Decodable {
    let values: [PlexRecordDTO]

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var out: [PlexRecordDTO] = []
            while !unkeyed.isAtEnd {
                out.append(try unkeyed.decode(PlexRecordDTO.self))
            }
            self.values = out
            return
        }
        self.values = [try PlexRecordDTO(from: decoder)]
    }
}

nonisolated enum PlexTypeField: Decodable, Hashable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) {
            self = .int(i)
            return
        }
        if let s = try? c.decode(String.self) {
            self = .string(s)
            return
        }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected Int or String for Plex type")
    }
}

nonisolated enum PlexKind: Hashable {
    case movie, show, season, episode
    case artist, album, track
    case photo
    case unknown

    static func fromInt(_ code: Int) -> PlexKind {
        switch code {
        case 1: return .movie
        case 2: return .show
        case 3: return .season
        case 4: return .episode
        case 8: return .artist
        case 9: return .album
        case 10: return .track
        case 11, 12, 13: return .photo
        default: return .unknown
        }
    }

    init(plexTypeField: PlexTypeField?) {
        guard let plexTypeField else {
            self = .unknown
            return
        }
        switch plexTypeField {
        case .int(let i): self = Self.fromInt(i)
        case .string(let s):
            switch s.lowercased() {
            case "movie": self = .movie
            case "show", "series": self = .show
            case "season": self = .season
            case "episode": self = .episode
            case "artist": self = .artist
            case "album": self = .album
            case "track": self = .track
            case "photo": self = .photo
            case "collection": self = .show
            case "playlist": self = .unknown
            default: self = .unknown
            }
        }
    }
}

nonisolated struct PlexTagDTO: Decodable {
    let tag: String?
    let key: String?
}

nonisolated struct PlexTagList: Decodable {
    let values: [PlexTagDTO]

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var out: [PlexTagDTO] = []
            while !unkeyed.isAtEnd {
                out.append(try unkeyed.decode(PlexTagDTO.self))
            }
            self.values = out
            return
        }
        self.values = [try PlexTagDTO(from: decoder)]
    }
}

nonisolated struct PlexRecordDTO: Decodable {
    let ratingKey: String?
    let key: String?
    let title: String?
    let name: String?
    let type: PlexTypeField?
    let year: Int?
    let summary: String?
    let thumb: String?
    let parentRatingKey: String?
    let parentTitle: String?
    let parentThumb: String?
    let grandparentRatingKey: String?
    let grandparentTitle: String?
    let grandparentThumb: String?
    let index: Int?
    let parentIndex: Int?
    let duration: Int?
    let addedAt: Int?
    let originallyAvailableAt: Int?
    let viewOffset: Int?
    let viewCount: Int?
    let lastViewedAt: Int?
    let librarySectionID: String?
    let sort: String?
    let tag: String?
    let contentRating: String?
    let studio: String?
    let rating: Double?
    let audienceRating: Double?
    let genres: [String]
    let directors: [String]
    let cast: [String]
    let markers: [PlexMarkerRecord]

    enum CodingKeys: String, CodingKey {
        case ratingKey, key, title, name, type, year, summary, thumb
        case parentRatingKey, parentTitle, parentThumb
        case grandparentRatingKey, grandparentTitle, grandparentThumb
        case index, parentIndex, duration
        case addedAt, originallyAvailableAt, viewOffset, viewCount, lastViewedAt
        case librarySectionID, sort, tag
        case contentRating, studio, rating, audienceRating
        case Genre, Director, Role, Marker
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ratingKey = Self.decodeFlexString(c, key: .ratingKey)
        key = Self.decodeFlexString(c, key: .key)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        type = try? c.decodeIfPresent(PlexTypeField.self, forKey: .type)
        year = Self.decodeFlexInt(c, key: .year)
        summary = try? c.decodeIfPresent(String.self, forKey: .summary)
        thumb = try? c.decodeIfPresent(String.self, forKey: .thumb)
        parentRatingKey = Self.decodeFlexString(c, key: .parentRatingKey)
        parentTitle = try? c.decodeIfPresent(String.self, forKey: .parentTitle)
        parentThumb = try? c.decodeIfPresent(String.self, forKey: .parentThumb)
        grandparentRatingKey = Self.decodeFlexString(c, key: .grandparentRatingKey)
        grandparentTitle = try? c.decodeIfPresent(String.self, forKey: .grandparentTitle)
        grandparentThumb = try? c.decodeIfPresent(String.self, forKey: .grandparentThumb)
        index = Self.decodeFlexInt(c, key: .index)
        parentIndex = Self.decodeFlexInt(c, key: .parentIndex)
        duration = Self.decodeFlexInt(c, key: .duration)
        addedAt = Self.decodeUnixTimestamp(c, key: .addedAt)
        originallyAvailableAt = Self.decodeUnixTimestamp(c, key: .originallyAvailableAt)
        viewOffset = Self.decodeFlexInt(c, key: .viewOffset)
        viewCount = Self.decodeFlexInt(c, key: .viewCount)
        lastViewedAt = Self.decodeUnixTimestamp(c, key: .lastViewedAt)
        librarySectionID = Self.decodeFlexString(c, key: .librarySectionID)
        sort = try? c.decodeIfPresent(String.self, forKey: .sort)
        tag = try? c.decodeIfPresent(String.self, forKey: .tag)
        contentRating = try? c.decodeIfPresent(String.self, forKey: .contentRating)
        studio = try? c.decodeIfPresent(String.self, forKey: .studio)
        rating = Self.decodeFlexDouble(c, key: .rating)
        audienceRating = Self.decodeFlexDouble(c, key: .audienceRating)
        genres = Self.decodeTags(c, key: .Genre)
        directors = Self.decodeTags(c, key: .Director)
        cast = Self.decodeTags(c, key: .Role)
        markers = Self.decodeMarkers(from: c)
    }

    private static func decodeMarkers(from c: KeyedDecodingContainer<CodingKeys>) -> [PlexMarkerRecord] {
        guard c.contains(.Marker) else { return [] }
        if var unkeyed = try? c.nestedUnkeyedContainer(forKey: .Marker) {
            var out: [PlexMarkerRecord] = []
            while !unkeyed.isAtEnd {
                if let m = try? unkeyed.decode(PlexMarkerRecord.self) {
                    out.append(m)
                }
            }
            return out
        }
        if let single = try? c.decode(PlexMarkerRecord.self, forKey: .Marker) {
            return [single]
        }
        return []
    }

    var displayTitle: String {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !t.isEmpty { return t }
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !n.isEmpty { return n }
        let g = tag?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !g.isEmpty { return g }
        return "Untitled"
    }

    var kind: PlexKind { PlexKind(plexTypeField: type) }

    var isWatchedByViewCount: Bool {
        guard let viewCount, viewCount > 0 else { return false }
        guard let duration, duration > 0, let viewOffset else { return true }
        return viewOffset >= duration - 30_000
    }

    private static func decodeFlexString(
        _ c: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> String? {
        if let value = try? c.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? c.decode(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    private static func decodeFlexInt(
        _ c: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Int? {
        if let value = try? c.decode(Int.self, forKey: key) { return value }
        if let text = try? c.decode(String.self, forKey: key) {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func decodeFlexDouble(
        _ c: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Double? {
        if let value = try? c.decode(Double.self, forKey: key) { return value }
        if let value = try? c.decode(Int.self, forKey: key) { return Double(value) }
        if let text = try? c.decode(String.self, forKey: key) {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func decodeUnixTimestamp(
        _ c: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Int? {
        decodeFlexInt(c, key: key)
    }

    private static func decodeTags(
        _ c: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> [String] {
        guard let tags = try? c.decode(PlexTagList.self, forKey: key) else { return [] }
        return tags.values.compactMap { $0.tag ?? $0.key }.filter { !$0.isEmpty }
    }
}

// MARK: - Client

nonisolated struct PlexMediaServerClient: Sendable {
    let origin: URL
    let token: String
    let session: URLSession

    init(server: PlexServer, session: URLSession = PlexNetworking.session) throws {
        guard server.usesLivePlexAPI,
              let origin = server.plexOriginURL,
              let raw = server.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            throw PlexAPIError.serverNotConfiguredForLiveAPI
        }
        self.origin = origin
        self.token = raw
        self.session = session
    }

    func verifyReachable() async throws {
        _ = try await fetchOnePage(path: "/identity", query: [])
    }

    func fetchFriendlyName() async throws -> String {
        let container = try await fetchOnePage(path: "/identity", query: [])
        if let n = container.friendlyName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        let first = container.records.first
        let name = first?.title ?? first?.displayTitle ?? first?.name
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return "Plex Server"
    }

    func fetchLibraries(serverId: UUID) async throws -> [PlexLibrary] {
        let root = try await fetchAllRecords(path: "/library/sections")
        return
            root
            .compactMap { record -> PlexLibrary? in
                guard let key = record.key ?? record.ratingKey else { return nil }
                let title = record.displayTitle
                let typeCode = plexSectionTypeCode(for: record)
                return PlexLibrary(
                    serverId: serverId,
                    sectionKey: PlexLibrary.normalizeSectionKey(key),
                    title: title,
                    type: typeCode,
                    thumbPath: record.thumb,
                    compositePath: nil,
                    uuid: record.ratingKey,
                    agent: nil,
                    scanner: nil,
                    language: nil,
                    plexDefaultSortKey: record.sort
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Mapping

    func catalogNodeMapper(_ rows: [PlexRecordDTO], startOrder: Int = 0) -> [PlexCatalogNode] {
        rows.enumerated().compactMap { index, row in
            catalogNodeForRecord(row, libraryOrder: startOrder + index)
        }
    }

    func catalogNodeForRecord(_ r: PlexRecordDTO, libraryOrder: Int) -> PlexCatalogNode? {
        switch r.kind {
        case .movie:
            return mapMovie(r, libraryOrder: libraryOrder)
        case .photo:
            return mapPhoto(r, libraryOrder: libraryOrder)
        case .show, .artist:
            return mapShow(r, libraryOrder: libraryOrder)
        case .season:
            return mapSeason(r, libraryOrder: libraryOrder)
        case .episode:
            return mapEpisode(r, libraryOrder: libraryOrder)
        case .album:
            return mapSeasonFromAlbum(r, artistName: r.grandparentTitle ?? r.parentTitle, libraryOrder: libraryOrder)
        case .track:
            return mapMusicTrack(r, libraryOrder: libraryOrder)
        case .unknown:
            if let node = mapMovie(r, libraryOrder: libraryOrder) { return node }
            if let node = mapShow(r, libraryOrder: libraryOrder) { return node }
            return nil
        }
    }

    func mapPhoto(_ r: PlexRecordDTO, libraryOrder: Int = 0) -> PlexCatalogNode? {
        guard let rk = r.ratingKey, r.kind == .photo else { return nil }
        var summary = PlexPhotoSummary(
            ratingKey: rk,
            title: r.displayTitle,
            thumbPath: r.thumb
        )
        summary.libraryOrder = libraryOrder
        summary.addedAt = r.addedAt
        return .photo(summary)
    }

    func mapMovie(_ r: PlexRecordDTO, libraryOrder: Int = 0) -> PlexCatalogNode? {
        guard let rk = r.ratingKey, r.kind == .movie || r.kind == .unknown else { return nil }
        if r.kind == .show || r.kind == .season || r.kind == .episode { return nil }
        var summary = PlexMovieSummary(
            ratingKey: rk,
            title: r.displayTitle,
            year: r.year,
            summary: r.summary,
            thumbPath: r.thumb
        )
        summary.libraryOrder = libraryOrder
        summary.addedAt = r.addedAt
        summary.originallyAvailableAt = r.originallyAvailableAt
        summary.viewOffsetMs = r.viewOffset
        summary.durationMs = r.duration
        summary.viewCount = r.viewCount
        return .movie(summary)
    }

    func mapShow(_ r: PlexRecordDTO, libraryOrder: Int = 0) -> PlexCatalogNode? {
        guard let rk = r.ratingKey, r.kind == .show || r.kind == .artist else { return nil }
        var summary = PlexShowSummary(
            ratingKey: rk,
            title: r.displayTitle,
            year: r.year,
            summary: r.summary,
            thumbPath: r.thumb
        )
        summary.libraryOrder = libraryOrder
        summary.addedAt = r.addedAt
        summary.originallyAvailableAt = r.originallyAvailableAt
        return .show(summary)
    }

    func mapSeason(_ r: PlexRecordDTO, libraryOrder: Int = 0) -> PlexCatalogNode? {
        guard let rk = r.ratingKey, r.kind == .season else { return nil }
        let seasonNum = r.index ?? r.parentIndex ?? 0
        let showTitle = r.grandparentTitle ?? r.parentTitle ?? ""
        let prk = r.parentRatingKey ?? r.grandparentRatingKey ?? ""
        let label = r.displayTitle.contains("Season") ? r.displayTitle : "Season \(seasonNum)"
        var summary = PlexSeasonSummary(
            ratingKey: rk,
            parentRatingKey: prk,
            showTitle: showTitle,
            seasonNumber: seasonNum,
            title: label,
            thumbPath: r.thumb
        )
        summary.libraryOrder = libraryOrder
        return .season(summary)
    }

    func mapSeasonFromAlbum(
        _ r: PlexRecordDTO,
        artistName: String?,
        libraryOrder: Int = 0
    ) -> PlexCatalogNode? {
        guard let rk = r.ratingKey, r.kind == .album else { return nil }
        let artist = artistName ?? r.parentTitle ?? r.grandparentTitle ?? ""
        let prk = r.parentRatingKey ?? ""
        let disc = r.parentIndex ?? r.index ?? 0
        var summary = PlexSeasonSummary(
            ratingKey: rk,
            parentRatingKey: prk,
            showTitle: artist,
            seasonNumber: disc,
            title: r.displayTitle,
            thumbPath: r.thumb
        )
        summary.libraryOrder = libraryOrder
        return .season(summary)
    }

    func mapEpisode(_ r: PlexRecordDTO, libraryOrder: Int = 0) -> PlexCatalogNode? {
        guard let rk = r.ratingKey, r.kind == .episode else { return nil }
        let seasonNum = r.parentIndex ?? r.index ?? 0
        let epNum = r.index ?? 0
        let showTitle = r.grandparentTitle ?? r.parentTitle ?? ""
        let prk = r.parentRatingKey ?? ""
        var summary = PlexEpisodeSummary(
            ratingKey: rk,
            parentRatingKey: prk,
            showRatingKey: r.grandparentRatingKey,
            showTitle: showTitle,
            seasonNumber: seasonNum,
            episodeNumber: epNum,
            title: r.displayTitle,
            summary: r.summary,
            durationSeconds: r.duration.map { $0 / 1000 },
            thumbPath: r.thumb
        )
        summary.libraryOrder = libraryOrder
        summary.showThumbPath = r.grandparentThumb
        summary.viewOffsetMs = r.viewOffset
        summary.durationMs = r.duration
        summary.viewCount = r.viewCount
        return .episode(summary)
    }

    func mapMusicTrack(_ r: PlexRecordDTO, libraryOrder: Int = 0) -> PlexCatalogNode? {
        guard let rk = r.ratingKey, r.kind == .track else { return nil }
        var summary = PlexMusicTrackSummary(
            ratingKey: rk,
            title: r.displayTitle,
            album: r.parentTitle,
            artist: r.grandparentTitle,
            thumbPath: r.thumb
        )
        summary.libraryOrder = libraryOrder
        return .musicTrack(summary)
    }

    func mapPlaylist(_ r: PlexRecordDTO, libraryOrder: Int = 0) -> PlexPlaylistSummary? {
        guard let rk = r.ratingKey else { return nil }
        var summary = PlexPlaylistSummary(
            ratingKey: rk,
            title: r.displayTitle,
            summary: r.summary,
            thumbPath: r.thumb
        )
        summary.libraryOrder = libraryOrder
        return summary
    }

    func mapCollection(_ r: PlexRecordDTO, libraryOrder: Int = 0) -> PlexCollectionSummary? {
        guard let rk = r.ratingKey else { return nil }
        var summary = PlexCollectionSummary(
            ratingKey: rk,
            title: r.displayTitle,
            summary: r.summary,
            thumbPath: r.thumb
        )
        summary.libraryOrder = libraryOrder
        return summary
    }

    func mediaDetail(from r: PlexRecordDTO) -> PlexMediaDetail? {
        guard let rk = r.ratingKey else { return nil }
        return PlexMediaDetail(
            ratingKey: rk,
            title: r.displayTitle,
            summary: r.summary,
            year: r.year,
            thumbPath: r.thumb,
            durationMs: r.duration,
            viewOffsetMs: r.viewOffset,
            viewCount: r.viewCount,
            contentRating: r.contentRating,
            studio: r.studio,
            rating: r.rating,
            audienceRating: r.audienceRating,
            genres: r.genres,
            directors: r.directors,
            cast: r.cast,
            markers: PlexPlaybackMarkerParser.markers(from: r.markers),
            node: catalogNodeForRecord(r, libraryOrder: 0)
        )
    }

    func plexSectionTypeCode(for record: PlexRecordDTO) -> Int {
        switch record.kind {
        case .movie: return 1
        case .show: return 2
        case .artist, .album, .track: return 8
        case .photo: return 13
        case .season, .episode: return 2
        case .unknown:
            guard let t = record.type else { return 1 }
            switch t {
            case .int(let i): return i
            case .string(let s):
                switch s.lowercased() {
                case "movie": return 1
                case "show": return 2
                case "artist", "album", "track": return 8
                case "photo": return 13
                default: return 1
                }
            }
        }
    }

    // MARK: - Network

    func fetchAllRecords(path: String, extraQuery: [URLQueryItem] = []) async throws -> [PlexRecordDTO] {
        var all: [PlexRecordDTO] = []
        var start = 0
        let pageSize = 200
        var total: Int?
        while true {
            try Task.checkCancellation()
            var q = extraQuery
            q.append(URLQueryItem(name: "X-Plex-Container-Start", value: String(start)))
            q.append(URLQueryItem(name: "X-Plex-Container-Size", value: String(pageSize)))
            let body = try await fetchOnePage(path: path, query: q)
            let batch = body.records
            all.append(contentsOf: batch)
            total = body.totalSize ?? total
            if batch.count < pageSize { break }
            start += pageSize
            if let total, all.count >= total { break }
            if batch.isEmpty { break }
        }
        return all
    }

    /// One HTTP request (one page).
    func fetchOnePage(path: String, query: [URLQueryItem], method: String = "GET") async throws -> PlexMediaContainerDecoded {
        let state = AppSignposts.signposter.beginInterval("plex.fetchOnePage", "\(path, privacy: .public)")
        defer { AppSignposts.signposter.endInterval("plex.fetchOnePage", state) }
        var req = try makeRequest(path: path, query: query)
        req.httpMethod = method
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw PlexAPIError.decodingFailed("Invalid response.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8).map { String($0.prefix(280)) }
            throw PlexAPIError.httpStatus(code: http.statusCode, bodySnippet: snippet)
        }
        do {
            let root = try PlexNetworking.jsonDecoder.decode(PlexMediaRoot.self, from: data)
            return root.MediaContainer
        } catch {
            throw PlexAPIError.decodingFailed("Could not read Plex JSON (\(error.localizedDescription)).")
        }
    }

    /// Plex command endpoints can return an empty 200 response body.
    /// Treat any 2xx as success and skip JSON decoding.
    func performScrobbleCommand(path: String, query: [URLQueryItem], method: String = "GET") async throws {
        let state = AppSignposts.signposter.beginInterval("plex.command", "\(path, privacy: .public)")
        defer { AppSignposts.signposter.endInterval("plex.command", state) }
        var req = try makeRequest(path: path, query: query)
        req.httpMethod = method
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw PlexAPIError.decodingFailed("Invalid response.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8).map { String($0.prefix(280)) }
            throw PlexAPIError.httpStatus(code: http.statusCode, bodySnippet: snippet)
        }
    }

    func makeRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        // Plex command routes (`/:/progress`, `/:/scrobble`) must keep the leading slash;
        // resolving `:/progress` drops the host and produces invalid `:/progress?...` URLs.
        let relativePath: String
        if trimmed.hasPrefix("/:/") {
            relativePath = trimmed
        } else if trimmed.hasPrefix("/") {
            relativePath = String(trimmed.dropFirst())
        } else {
            relativePath = trimmed
        }
        guard let url = URL(string: relativePath, relativeTo: origin)?.absoluteURL else {
            throw PlexAPIError.invalidURL
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidURL
        }
        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name == "X-Plex-Token" }) {
            items.append(URLQueryItem(name: "X-Plex-Token", value: token))
        }
        for q in query where q.name != "X-Plex-Token" {
            items.append(q)
        }
        components.queryItems = items
        guard let finalURL = components.url else { throw PlexAPIError.invalidURL }
        var request = URLRequest(url: finalURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(PlexHTTPConstants.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue(PlexHTTPConstants.productName, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(PlexHTTPConstants.productVersion, forHTTPHeaderField: "X-Plex-Product-Version")
        return request
    }
}

