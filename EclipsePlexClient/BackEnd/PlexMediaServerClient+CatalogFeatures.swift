//
//  PlexMediaServerClient+CatalogFeatures.swift
//  EclipsePlexClient
//
//  Catalog browsing, hubs, search, watch state, and extended playback resolution.
//

import CoreGraphics
import Foundation
import OSLog

private let plexLibraryPluginIdentifier = "com.plexapp.plugins.library"
private let catalogPageSize = 50

extension PlexMediaServerClient {

    // MARK: - Catalog listing

    func catalogNodes(
        library: PlexLibrary,
        parent: PlexCatalogParent,
        watchFilter: CatalogWatchFilter = .all,
        listFilters: CatalogListFilters = CatalogListFilters()
    ) async throws -> [PlexCatalogNode] {
        let path = catalogListPath(library: library, parent: parent)
        let query = catalogListQuery(watchFilter: watchFilter, listFilters: listFilters)
        let rows = try await fetchAllRecords(path: path, extraQuery: query)
        let nodes = catalogNodeMapper(rows)
        return applyWatchFilter(nodes, watchFilter: watchFilter)
    }

    func fetchCatalogPage(
        library: PlexLibrary,
        parent: PlexCatalogParent,
        watchFilter: CatalogWatchFilter = .all,
        listFilters: CatalogListFilters = CatalogListFilters(),
        offset: Int
    ) async throws -> CatalogPageResult {
        let path = catalogListPath(library: library, parent: parent)
        var query = catalogListQuery(watchFilter: watchFilter, listFilters: listFilters)
        query.append(URLQueryItem(name: "X-Plex-Container-Start", value: String(offset)))
        query.append(URLQueryItem(name: "X-Plex-Container-Size", value: String(catalogPageSize)))
        let body = try await fetchOnePage(path: path, query: query)
        let rows = body.records
        let nodes = applyWatchFilter(catalogNodeMapper(rows, startOrder: offset), watchFilter: watchFilter)
        let total = body.totalSize
        let nextOffset = offset + rows.count
        let hasMore: Bool
        if let total {
            hasMore = nextOffset < total
        } else {
            hasMore = rows.count >= catalogPageSize
        }
        return CatalogPageResult(nodes: nodes, totalSize: total, nextOffset: nextOffset, hasMore: hasMore)
    }

    func fetchLibraryGenres(library: PlexLibrary) async throws -> [PlexLibraryGenre] {
        let section = library.sectionID
        let rows = try await fetchAllRecords(path: "/library/sections/\(section)/genre")
        return rows.compactMap { row in
            let key = row.tag ?? row.key ?? row.ratingKey
            guard let key, !key.isEmpty else { return nil }
            return PlexLibraryGenre(filterKey: key, title: row.displayTitle)
        }
    }

    func fetchMediaDetail(ratingKey: String) async throws -> PlexMediaDetail {
        // Single-item path — paginating is wasted work. Markers come from a
        // different `Accept: application/xml` response, so fetch in parallel.
        async let jsonRecords = fetchOnePage(path: "/library/metadata/\(ratingKey)", query: [])
        async let xmlMarkers: [PlexPlaybackMarker] = {
            (try? await fetchPlaybackMarkersFromXML(ratingKey: ratingKey)) ?? []
        }()
        let body = try await jsonRecords
        guard let first = body.records.first, let detail = mediaDetail(from: first) else {
            throw PlexAPIError.decodingFailed("Could not read Plex metadata for \(ratingKey).")
        }
        let merged = PlexPlaybackMarkerParser.merged(
            xml: await xmlMarkers,
            json: detail.markers,
            durationMs: detail.durationMs
        )
        guard !merged.isEmpty else { return detail }
        return detail.replacing(markers: merged)
    }

    private static let metadataMarkerQuery: [URLQueryItem] = [
        URLQueryItem(name: "includeMarkers", value: "1"),
        URLQueryItem(name: "includeChapters", value: "1"),
    ]

    private func fetchPlaybackMarkersFromXML(ratingKey: String) async throws -> [PlexPlaybackMarker] {
        var request = try makeRequest(
            path: "/library/metadata/\(ratingKey)",
            query: Self.metadataMarkerQuery
        )
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
              let xml = String(data: data, encoding: .utf8)
        else { return [] }
        return PlexPlaybackXMLParser.parseMarkers(xml)
    }

    // MARK: - Hubs & search

    func fetchOnDeckHits(libraries: [PlexLibrary]) async throws -> [PlexCatalogSearchHit] {
        try await fetchHubHits(path: "/library/onDeck", libraries: libraries)
    }

    func fetchRecentlyAddedHits(libraries: [PlexLibrary]) async throws -> [PlexCatalogSearchHit] {
        try await fetchHubHits(path: "/library/recentlyAdded", libraries: libraries)
    }

    func searchCatalog(query: String, libraries: [PlexLibrary]) async throws -> [PlexCatalogSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let body = try await fetchOnePage(
            path: "/search",
            query: [
                URLQueryItem(name: "query", value: trimmed),
                URLQueryItem(name: "limit", value: "40"),
            ]
        )
        return body.records.compactMap { record in
            guard let library = libraryMatching(record: record, libraries: libraries),
                  let node = catalogNodeForRecord(record, libraryOrder: 0)
            else { return nil }
            return PlexCatalogSearchHit(library: library, node: node)
        }
    }

    // MARK: - TV episode order

    func orderedEpisodesInShow(library: PlexLibrary, showRatingKey: String) async throws -> [PlexEpisodeSummary] {
        let seasonNodes = try await catalogNodes(
            library: library,
            parent: .show(ratingKey: showRatingKey),
            watchFilter: .all
        )
        var episodes: [PlexEpisodeSummary] = []
        for node in seasonNodes {
            guard case .season(let season) = node else { continue }
            let epNodes = try await catalogNodes(
                library: library,
                parent: .season(ratingKey: season.ratingKey),
                watchFilter: .all
            )
            for epNode in epNodes {
                if case .episode(let ep) = epNode {
                    episodes.append(ep)
                }
            }
        }
        return episodes.sorted {
            if $0.seasonNumber != $1.seasonNumber { return $0.seasonNumber < $1.seasonNumber }
            return $0.episodeNumber < $1.episodeNumber
        }
    }

    func fetchNextEpisode(
        library: PlexLibrary,
        showRatingKey: String,
        episodeRatingKey: String
    ) async throws -> PlexEpisodeSummary? {
        let ordered = try await orderedEpisodesInShow(library: library, showRatingKey: showRatingKey)
        guard let index = ordered.firstIndex(where: { $0.ratingKey == episodeRatingKey }),
              index + 1 < ordered.count
        else { return nil }
        return ordered[index + 1]
    }

    func fetchPreviousEpisode(
        library: PlexLibrary,
        showRatingKey: String,
        episodeRatingKey: String
    ) async throws -> PlexEpisodeSummary? {
        let ordered = try await orderedEpisodesInShow(library: library, showRatingKey: showRatingKey)
        guard let index = ordered.firstIndex(where: { $0.ratingKey == episodeRatingKey }),
              index > 0
        else { return nil }
        return ordered[index - 1]
    }

    func fetchResumeEpisode(library: PlexLibrary, showRatingKey: String) async throws -> PlexEpisodeSummary? {
        let ordered = try await orderedEpisodesInShow(library: library, showRatingKey: showRatingKey)
        let inProgress = ordered.filter { episode in
            guard let offset = episode.viewOffsetMs, offset > 0 else { return false }
            guard let duration = episode.durationMs, duration > 0 else { return true }
            return offset < duration - 30_000
        }
        return inProgress.last
    }

    // MARK: - Playlists & collections

    func fetchPlaylists() async throws -> [PlexPlaylistSummary] {
        let rows = try await fetchAllRecords(path: "/playlists/all")
        return rows.enumerated().compactMap { index, row in
            mapPlaylist(row, libraryOrder: index)
        }
    }

    func fetchLibraryCollections(library: PlexLibrary) async throws -> [PlexCollectionSummary] {
        let section = library.sectionID
        let rows = try await fetchAllRecords(path: "/library/sections/\(section)/collections")
        return rows.enumerated().compactMap { index, row in
            mapCollection(row, libraryOrder: index)
        }
    }

    // MARK: - Watch state / scrobble

    func markItemPlayed(ratingKey: String, durationMs: Int?) async throws {
        var query = scrobbleQuery(ratingKey: ratingKey)
        if let durationMs, durationMs > 0 {
            query.append(URLQueryItem(name: "duration", value: String(durationMs)))
        }
        try await performScrobbleCommand(path: "/:/scrobble", query: query)
    }

    func markItemUnwatched(ratingKey: String) async throws {
        try await performScrobbleCommand(path: "/:/unscrobble", query: scrobbleQuery(ratingKey: ratingKey))
    }

    func reportPlaybackProgress(ratingKey: String, timeMs: Int) async throws {
        var query = scrobbleQuery(ratingKey: ratingKey)
        query.append(URLQueryItem(name: "time", value: String(max(0, timeMs))))
        query.append(URLQueryItem(name: "state", value: "playing"))
        try await performScrobbleCommand(path: "/:/progress", query: query)
    }

    func reportTimeline(
        ratingKey: String,
        state: String,
        timeMs: Int,
        durationMs: Int
    ) async throws {
        var query = scrobbleQuery(ratingKey: ratingKey)
        query.append(URLQueryItem(name: "ratingKey", value: ratingKey))
        query.append(URLQueryItem(name: "state", value: state))
        query.append(URLQueryItem(name: "time", value: String(max(0, timeMs))))
        query.append(URLQueryItem(name: "duration", value: String(max(0, durationMs))))
        try await performScrobbleCommand(path: "/:/timeline", query: query)
    }

    // MARK: - Playback & downloads

    nonisolated struct PlexPlaybackStreamCandidate: Sendable {
        let url: URL
        let delivery: PlexPlaybackDelivery
        let httpHeaderFields: [String: String]
        let label: String
    }

    nonisolated struct PlexPlaybackStreamResolution: Sendable {
        let streams: [PlexPlaybackStreamCandidate]
        let subtitleStreams: [PlexSubtitleStream]
        let sourceVideoSize: CGSize?
        let playbackMarkers: [PlexPlaybackMarker]
    }

    func resolvePlaybackStreamCandidates(
        ratingKey: String,
        server: PlexServer,
        options: PlaybackStreamOptions
    ) async throws -> PlexPlaybackStreamResolution {
        let state = AppSignposts.signposter.beginInterval("plex.resolveCandidates", "\(ratingKey, privacy: .public)")
        defer { AppSignposts.signposter.endInterval("plex.resolveCandidates", state) }

        let xml = try await fetchMetadataXML(ratingKey: ratingKey)
        let extras = PlexPlaybackXMLParser.parseMetadataExtras(xml)
        // Parse Sources from the same XML we just fetched — `resolvePlaybackStream`
        // and the forced-transcode branch would otherwise refetch this URL twice.
        let sharedSources = PlexPlaybackXMLParser.parse(xml, ratingKey: ratingKey)
        var candidates: [PlexPlaybackStreamCandidate] = []

        let direct = try await resolvePlaybackStream(
            ratingKey: ratingKey,
            server: server,
            cachedSources: sharedSources
        )
        candidates.append(
            PlexPlaybackStreamCandidate(
                url: direct.url,
                delivery: direct.delivery,
                httpHeaderFields: direct.httpHeaderFields,
                label: direct.delivery == .directPlay ? "Direct play" : "Transcode"
            )
        )

        if options.videoResolution.forcesTranscode, direct.delivery == .directPlay {
            let sources: PlexPlaybackXMLParser.Sources
            if let sharedSources {
                sources = sharedSources
            } else {
                sources = try await fetchPlaybackSources(ratingKey: ratingKey)
            }
            let sessionID = UUID().uuidString
            let vlcHeaders = server.vlcHTTPHeaderFields
            var transcodeQuery = server.plexTranscodeQueryItems(
                sessionID: sessionID,
                metadataPath: sources.metadataPath,
                mediaIndex: sources.mediaIndex,
                partIndex: sources.partIndex,
                protocol: "http",
                directPlay: "0",
                directStream: "1"
            )
            transcodeQuery = transcodeQuery.map { item in
                if item.name == "videoResolution" {
                    return URLQueryItem(name: "videoResolution", value: options.videoResolution.plexVideoResolution)
                }
                return item
            }
            if !transcodeQuery.contains(where: { $0.name == "videoResolution" }) {
                transcodeQuery.append(
                    URLQueryItem(name: "videoResolution", value: options.videoResolution.plexVideoResolution)
                )
            }
            transcodeQuery.append(
                URLQueryItem(name: "subtitles", value: options.subtitleSelection.plexTranscodeValue)
            )
            let transcode = try makeTranscodeStream(
                endpoint: "/video/:/transcode/universal/start.mkv",
                query: transcodeQuery,
                vlcHeaders: vlcHeaders,
                label: "Transcode (\(options.videoResolution.menuTitle))",
                delivery: .transcodeHTTP
            )
            candidates.append(
                PlexPlaybackStreamCandidate(
                    url: transcode.url,
                    delivery: transcode.delivery,
                    httpHeaderFields: transcode.httpHeaderFields,
                    label: "Transcode (\(options.videoResolution.menuTitle))"
                )
            )
        }

        let markers = PlexPlaybackMarkerParser.normalize(
            PlexPlaybackXMLParser.parseMarkers(xml),
            durationMs: nil
        )
        return PlexPlaybackStreamResolution(
            streams: candidates,
            subtitleStreams: extras.subtitleStreams,
            sourceVideoSize: extras.sourceVideoSize,
            playbackMarkers: markers
        )
    }

    nonisolated struct PlexDownloadSource: Sendable {
        let url: URL
        let httpHeaderFields: [String: String]
        let suggestedFilename: String
    }

    func resolveDownloadSource(
        ratingKey: String,
        server: PlexServer,
        quality: PlaybackVideoResolution
    ) async throws -> PlexDownloadSource {
        let title = (try? await fetchMediaDetail(ratingKey: ratingKey).title) ?? "download"
        let safe = title
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = quality == .original ? "mkv" : "mp4"
        let vlcHeaders = server.vlcHTTPHeaderFields

        let stream: PlexPlaybackStream
        if quality == .original {
            stream = try await resolvePlaybackStream(ratingKey: ratingKey, server: server)
        } else {
            let sources = try await fetchPlaybackSources(ratingKey: ratingKey)
            let sessionID = UUID().uuidString
            var transcodeQuery = server.plexTranscodeQueryItems(
                sessionID: sessionID,
                metadataPath: sources.metadataPath,
                mediaIndex: sources.mediaIndex,
                partIndex: sources.partIndex,
                protocol: "http",
                directPlay: "0",
                directStream: "1"
            )
            transcodeQuery = transcodeQuery.map { item in
                if item.name == "videoResolution" {
                    return URLQueryItem(name: "videoResolution", value: quality.plexVideoResolution)
                }
                return item
            }
            if !transcodeQuery.contains(where: { $0.name == "videoResolution" }) {
                transcodeQuery.append(
                    URLQueryItem(name: "videoResolution", value: quality.plexVideoResolution)
                )
            }
            stream = try makeTranscodeStream(
                endpoint: "/video/:/transcode/universal/start.mp4",
                query: transcodeQuery,
                vlcHeaders: vlcHeaders,
                label: "Download (\(quality.menuTitle))",
                delivery: .transcodeHTTP
            )
        }

        return PlexDownloadSource(
            url: stream.url,
            httpHeaderFields: stream.httpHeaderFields,
            suggestedFilename: "\(safe.isEmpty ? ratingKey : safe).\(ext)"
        )
    }

    // MARK: - Internals

    private func catalogListPath(library: PlexLibrary, parent: PlexCatalogParent) -> String {
        let section = library.sectionID
        switch parent {
        case .root:
            switch library.sectionType {
            case .movie, .show, .other:
                return "/library/sections/\(section)/all"
            case .photo:
                return "/library/sections/\(section)/all"
            case .music:
                return "/library/sections/\(section)/all"
            }
        case .show(let ratingKey):
            return "/library/metadata/\(ratingKey)/children"
        case .season(let ratingKey):
            return "/library/metadata/\(ratingKey)/children"
        case .collection(let ratingKey):
            return "/library/metadata/\(ratingKey)/children"
        case .playlist(let ratingKey):
            return "/playlists/\(ratingKey)/items"
        }
    }

    private func catalogListQuery(
        watchFilter: CatalogWatchFilter,
        listFilters: CatalogListFilters
    ) -> [URLQueryItem] {
        watchFilter.plexQueryItems + listFilters.plexQueryItems
    }

    private func applyWatchFilter(_ nodes: [PlexCatalogNode], watchFilter: CatalogWatchFilter) -> [PlexCatalogNode] {
        guard watchFilter.filtersClientSideByViewCount else { return nodes }
        return nodes.filter { node in
            switch node {
            case .movie(let m):
                return (m.viewCount ?? 0) > 0
            case .episode(let e):
                return (e.viewCount ?? 0) > 0
            default:
                return true
            }
        }
    }

    private func fetchHubHits(path: String, libraries: [PlexLibrary]) async throws -> [PlexCatalogSearchHit] {
        let body = try await fetchOnePage(path: path, query: [])
        return body.records.compactMap { record in
            guard let library = libraryMatching(record: record, libraries: libraries),
                  let node = catalogNodeForRecord(record, libraryOrder: 0)
            else { return nil }
            return PlexCatalogSearchHit(library: library, node: node)
        }
    }

    private func libraryMatching(record: PlexRecordDTO, libraries: [PlexLibrary]) -> PlexLibrary? {
        if let sectionID = record.librarySectionID {
            if let match = libraries.first(where: { $0.matchesLibrarySectionID(sectionID) }) {
                return match
            }
        }
        switch record.kind {
        case .movie:
            return libraries.first(where: { $0.sectionType == .movie })
        case .photo:
            return libraries.first(where: { $0.sectionType == .photo })
        case .show, .season, .episode:
            return libraries.first(where: { $0.sectionType == .show })
        case .artist, .album, .track:
            return libraries.first(where: { $0.sectionType == .music })
        case .unknown:
            return libraries.first
        }
    }

    private func scrobbleQuery(ratingKey: String) -> [URLQueryItem] {
        let metadataKey = ratingKey.hasPrefix("/library/metadata/")
            ? ratingKey
            : "/library/metadata/\(ratingKey)"
        return [
            URLQueryItem(name: "key", value: metadataKey),
            URLQueryItem(name: "identifier", value: plexLibraryPluginIdentifier),
        ]
    }

    private func fetchMetadataXML(ratingKey: String) async throws -> String {
        var request = try makeRequest(
            path: "/library/metadata/\(ratingKey)",
            query: Self.metadataMarkerQuery
        )
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlexAPIError.decodingFailed("Invalid response.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8).map { String($0.prefix(280)) }
            throw PlexAPIError.httpStatus(code: http.statusCode, bodySnippet: snippet)
        }
        guard let xml = String(data: data, encoding: .utf8) else {
            throw PlexAPIError.decodingFailed("Could not read Plex metadata XML.")
        }
        return xml
    }
}
