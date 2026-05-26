//
//  PlexMediaServerClient+PlaybackResolution.swift
//  EclipsePlexClient
//

import Foundation

extension PlexMediaServerClient {
    // MARK: - Playback

    /// Resolved stream location for VLC / AVFoundation.
    nonisolated struct PlexPlaybackStream: Sendable {
        let url: URL
        let delivery: PlexPlaybackDelivery
        let httpHeaderFields: [String: String]
    }

    nonisolated enum PlexPlaybackDelivery: String, Sendable {
        case directPlay
        case transcodeHLS
        case transcodeHTTP
    }

    /// Resolves a playable URL for VLC. Avoids blocking on transcode/decision endpoints (they can take minutes).
    ///
    /// Pass `cachedSources` when the caller has already parsed `/library/metadata/{ratingKey}`
    /// (e.g. `resolvePlaybackStreamCandidates`) to avoid a redundant HTTP round trip.
    func resolvePlaybackStream(
        ratingKey: String,
        server: PlexServer,
        cachedSources: PlexPlaybackXMLParser.Sources? = nil
    ) async throws -> PlexPlaybackStream {
        AppLog.networkDebug("Plex resolve start ratingKey=\(ratingKey)")
        let sources: PlexPlaybackXMLParser.Sources
        if let cachedSources {
            sources = cachedSources
        } else {
            sources = try await fetchPlaybackSources(ratingKey: ratingKey)
        }
        let sessionID = UUID().uuidString
        let vlcHeaders = server.vlcHTTPHeaderFields

        AppLog.networkDebug(
            "Plex metadata path=\(sources.metadataPath) part=\(sources.partKey ?? "(none)") indirect=\(sources.isIndirect) mediaIndex=\(sources.mediaIndex)"
        )

        if !sources.isIndirect, let partPath = sources.partKey {
            AppLog.networkDebug("Plex direct play path=\(partPath)")
            let request = try makeStreamRequest(path: partPath, query: [])
            return PlexPlaybackStream(
                url: request.url!,
                delivery: .directPlay,
                httpHeaderFields: vlcHeaders
            )
        }

        AppLog.networkDebug("Plex building MKV transcode URL")
        let mkvQuery = server.plexTranscodeQueryItems(
            sessionID: sessionID,
            metadataPath: sources.metadataPath,
            mediaIndex: sources.mediaIndex,
            partIndex: sources.partIndex,
            protocol: "http",
            directPlay: "0",
            directStream: "1"
        )
        return try makeTranscodeStream(
            endpoint: "/video/:/transcode/universal/start.mkv",
            query: mkvQuery,
            vlcHeaders: vlcHeaders,
            label: "MKV remux",
            delivery: .transcodeHTTP
        )
    }

    func makeTranscodeStream(
        endpoint: String,
        query: [URLQueryItem],
        vlcHeaders: [String: String],
        label: String,
        delivery: PlexPlaybackDelivery
    ) throws -> PlexPlaybackStream {
        let request = try makeStreamRequest(path: endpoint, query: query)
        if let url = request.url {
            AppLog.networkDebug("\(label) → \(redactedPlaybackURL(url))")
        }
        return PlexPlaybackStream(url: request.url!, delivery: delivery, httpHeaderFields: vlcHeaders)
    }

    func makeStreamRequest(
        path: String,
        query: [URLQueryItem],
        accept: String = "*/*"
    ) throws -> URLRequest {
        var request = try makeRequest(path: path, query: query)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return request
    }

    func fetchPlaybackSources(ratingKey: String) async throws -> PlexPlaybackXMLParser.Sources {
        AppLog.networkDebug("Plex fetching metadata")
        var request = try makeRequest(path: "/library/metadata/\(ratingKey)", query: [])
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

        guard let xml = String(data: data, encoding: .utf8),
              let sources = PlexPlaybackXMLParser.parse(xml, ratingKey: ratingKey)
        else {
            throw PlexAPIError.decodingFailed("Could not read Plex media parts for playback.")
        }
        return sources
    }

    private func redactedPlaybackURL(_ url: URL?) -> String {
        AppLog.redactURL(url) ?? "(invalid url)"
    }
}
