//
//  PlexMediaServerAPI.swift
//  EclipsePlexClient
//
//  Minimal Plex Media Server JSON client: sections, library metadata, children.
//

import Foundation

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
    static let productVersion = "1.0"
}

// MARK: - JSON DTOs

private nonisolated struct PlexMediaRoot: Decodable {
    let MediaContainer: PlexMediaContainerDecoded
}

private nonisolated struct PlexMediaContainerDecoded: Decodable {
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
private nonisolated struct PlexRecordList: Decodable {
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

private nonisolated enum PlexTypeField: Decodable, Hashable {
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

private nonisolated enum PlexKind: Hashable {
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
            default: self = .unknown
            }
        }
    }
}

private nonisolated struct PlexRecordDTO: Decodable {
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
    let grandparentTitle: String?
    let index: Int?
    let parentIndex: Int?
    let duration: Int?

    enum CodingKeys: String, CodingKey {
        case ratingKey, key, title, name, type, year, summary, thumb
        case parentRatingKey, parentTitle, grandparentTitle, index, parentIndex, duration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let rk = try? c.decode(String.self, forKey: .ratingKey) {
            ratingKey = rk
        } else if let rk = try? c.decode(Int.self, forKey: .ratingKey) {
            ratingKey = String(rk)
        } else {
            ratingKey = nil
        }
        if c.contains(.key) {
            if let ks = try? c.decode(String.self, forKey: .key) {
                key = ks
            } else if let ki = try? c.decode(Int.self, forKey: .key) {
                key = String(ki)
            } else {
                key = nil
            }
        } else {
            key = nil
        }
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        type = try? c.decodeIfPresent(PlexTypeField.self, forKey: .type)
        year = try? c.decodeIfPresent(Int.self, forKey: .year)
        summary = try? c.decodeIfPresent(String.self, forKey: .summary)
        thumb = try? c.decodeIfPresent(String.self, forKey: .thumb)

        if let prk = try? c.decode(String.self, forKey: .parentRatingKey) {
            parentRatingKey = prk
        } else if let prk = try? c.decode(Int.self, forKey: .parentRatingKey) {
            parentRatingKey = String(prk)
        } else {
            parentRatingKey = nil
        }

        parentTitle = try? c.decodeIfPresent(String.self, forKey: .parentTitle)
        grandparentTitle = try? c.decodeIfPresent(String.self, forKey: .grandparentTitle)
        index = try? c.decodeIfPresent(Int.self, forKey: .index)
        parentIndex = try? c.decodeIfPresent(Int.self, forKey: .parentIndex)
        duration = try? c.decodeIfPresent(Int.self, forKey: .duration)
    }

    var displayTitle: String {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !t.isEmpty { return t }
        let n = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !n.isEmpty { return n }
        return "Untitled"
    }

    var kind: PlexKind { PlexKind(plexTypeField: type) }
}

// MARK: - Client

nonisolated struct PlexMediaServerClient: Sendable {
    private let origin: URL
    private let token: String
    private let session: URLSession

    init(server: PlexServer, session: URLSession = .shared) throws {
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
                    sectionKey: key,
                    title: title,
                    type: typeCode,
                    thumbPath: record.thumb,
                    compositePath: nil,
                    uuid: record.ratingKey,
                    agent: nil,
                    scanner: nil,
                    language: nil
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func catalogNodes(library: PlexLibrary, parent: PlexCatalogParent) async throws -> [PlexCatalogNode] {
        switch library.sectionType {
        case .movie:
            guard case .root = parent else { return [] }
            let rows = try await fetchAllRecords(path: "/library/sections/\(library.sectionKey)/all")
            return rows.compactMap { mapMovie($0) }
        case .photo:
            guard case .root = parent else { return [] }
            let rows = try await fetchAllRecords(path: "/library/sections/\(library.sectionKey)/all")
            return rows.compactMap { row in
                if row.kind == .photo || row.kind == .movie { return mapMovie(row) }
                return mapMovie(row)
            }
        case .show:
            return try await tvNodes(library: library, parent: parent)
        case .music:
            return try await musicNodes(library: library, parent: parent)
        case .other:
            guard case .root = parent else { return [] }
            let rows = try await fetchAllRecords(path: "/library/sections/\(library.sectionKey)/all")
            var out: [PlexCatalogNode] = []
            out.append(contentsOf: rows.compactMap { mapMovie($0) })
            out.append(contentsOf: rows.compactMap { mapShow($0) })
            return out
        }
    }

    // MARK: - TV

    private func tvNodes(library: PlexLibrary, parent: PlexCatalogParent) async throws -> [PlexCatalogNode] {
        switch parent {
        case .root:
            let rows = try await fetchAllRecords(path: "/library/sections/\(library.sectionKey)/all")
            return rows.filter { $0.kind == .show }.compactMap { mapShow($0) }
        case .show(let ratingKey):
            let rows = try await fetchAllRecords(path: "/library/metadata/\(ratingKey)/children")
            if rows.contains(where: { $0.kind == .episode }) {
                return rows.filter { $0.kind == .episode }.compactMap { mapEpisode($0) }
            }
            return rows.filter { $0.kind == .season }.compactMap { mapSeason($0) }
        case .season(let ratingKey):
            let rows = try await fetchAllRecords(path: "/library/metadata/\(ratingKey)/children")
            return rows.filter { $0.kind == .episode }.compactMap { mapEpisode($0) }
        }
    }

    // MARK: - Music (artist → album → track)

    private func musicNodes(library: PlexLibrary, parent: PlexCatalogParent) async throws -> [PlexCatalogNode] {
        switch parent {
        case .root:
            let rows = try await fetchAllRecords(path: "/library/sections/\(library.sectionKey)/all")
            if rows.contains(where: { $0.kind == .artist }) {
                return rows.filter { $0.kind == .artist }.compactMap { mapShow($0) }
            }
            if rows.contains(where: { $0.kind == .album }) {
                return rows.filter { $0.kind == .album }.compactMap { mapSeasonFromAlbum($0, artistName: nil) }
            }
            return rows.filter { $0.kind == .track }.compactMap { mapMusicTrack($0) }
        case .show(let artistKey):
            let rows = try await fetchAllRecords(path: "/library/metadata/\(artistKey)/children")
            let artistName = rows.compactMap(\.parentTitle).first
            if rows.contains(where: { $0.kind == .track }) {
                return rows.filter { $0.kind == .track }.compactMap { mapMusicTrack($0) }
            }
            return rows.filter { $0.kind == .album }.compactMap { mapSeasonFromAlbum($0, artistName: artistName) }
        case .season(let albumKey):
            let rows = try await fetchAllRecords(path: "/library/metadata/\(albumKey)/children")
            return rows.filter { $0.kind == .track }.compactMap { mapMusicTrack($0) }
        }
    }

    // MARK: - Mapping

    private func mapMovie(_ r: PlexRecordDTO) -> PlexCatalogNode? {
        guard let rk = r.ratingKey, r.kind == .movie || r.kind == .photo || r.kind == .unknown else { return nil }
        if r.kind == .show || r.kind == .season || r.kind == .episode { return nil }
        return .movie(
            PlexMovieSummary(
                ratingKey: rk,
                title: r.displayTitle,
                year: r.year,
                summary: r.summary,
                thumbPath: r.thumb
            )
        )
    }

    private func mapShow(_ r: PlexRecordDTO) -> PlexCatalogNode? {
        guard let rk = r.ratingKey, r.kind == .show || r.kind == .artist else { return nil }
        return .show(
            PlexShowSummary(
                ratingKey: rk,
                title: r.displayTitle,
                year: r.year,
                summary: r.summary,
                thumbPath: r.thumb
            )
        )
    }

    private func mapSeason(_ r: PlexRecordDTO) -> PlexCatalogNode? {
        guard let rk = r.ratingKey, r.kind == .season else { return nil }
        let seasonNum = r.index ?? r.parentIndex ?? 0
        let showTitle = r.grandparentTitle ?? r.parentTitle ?? ""
        let prk = r.parentRatingKey ?? ""
        let label = r.displayTitle.contains("Season") ? r.displayTitle : "Season \(seasonNum)"
        return .season(
            PlexSeasonSummary(
                ratingKey: rk,
                parentRatingKey: prk,
                showTitle: showTitle,
                seasonNumber: seasonNum,
                title: label,
                thumbPath: r.thumb
            )
        )
    }

    private func mapSeasonFromAlbum(_ r: PlexRecordDTO, artistName: String?) -> PlexCatalogNode? {
        guard let rk = r.ratingKey, r.kind == .album else { return nil }
        let artist = artistName ?? r.parentTitle ?? r.grandparentTitle ?? ""
        let prk = r.parentRatingKey ?? ""
        let disc = r.parentIndex ?? r.index ?? 0
        return .season(
            PlexSeasonSummary(
                ratingKey: rk,
                parentRatingKey: prk,
                showTitle: artist,
                seasonNumber: disc,
                title: r.displayTitle,
                thumbPath: r.thumb
            )
        )
    }

    private func mapEpisode(_ r: PlexRecordDTO) -> PlexCatalogNode? {
        guard let rk = r.ratingKey, r.kind == .episode else { return nil }
        let seasonNum = r.parentIndex ?? r.index ?? 0
        let epNum = r.index ?? 0
        let showTitle = r.grandparentTitle ?? ""
        let prk = r.parentRatingKey ?? ""
        return .episode(
            PlexEpisodeSummary(
                ratingKey: rk,
                parentRatingKey: prk,
                showTitle: showTitle,
                seasonNumber: seasonNum,
                episodeNumber: epNum,
                title: r.displayTitle,
                summary: r.summary,
                durationSeconds: r.duration.map { $0 / 1000 },
                thumbPath: r.thumb
            )
        )
    }

    private func mapMusicTrack(_ r: PlexRecordDTO) -> PlexCatalogNode? {
        guard let rk = r.ratingKey, r.kind == .track else { return nil }
        return .musicTrack(
            PlexMusicTrackSummary(
                ratingKey: rk,
                title: r.displayTitle,
                album: r.parentTitle,
                artist: r.grandparentTitle,
                thumbPath: r.thumb
            )
        )
    }

    private func plexSectionTypeCode(for record: PlexRecordDTO) -> Int {
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

    private func fetchAllRecords(path: String, extraQuery: [URLQueryItem] = []) async throws -> [PlexRecordDTO] {
        var all: [PlexRecordDTO] = []
        var start = 0
        let pageSize = 200
        var total: Int?
        while true {
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
    private func fetchOnePage(path: String, query: [URLQueryItem]) async throws -> PlexMediaContainerDecoded {
        let req = try makeRequest(path: path, query: query)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw PlexAPIError.decodingFailed("Invalid response.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8).map { String($0.prefix(280)) }
            throw PlexAPIError.httpStatus(code: http.statusCode, bodySnippet: snippet)
        }
        do {
            let root = try JSONDecoder().decode(PlexMediaRoot.self, from: data)
            return root.MediaContainer
        } catch {
            throw PlexAPIError.decodingFailed("Could not read Plex JSON (\(error.localizedDescription)).")
        }
    }

    private func makeRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let relativePath = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
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
