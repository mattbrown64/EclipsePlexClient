//
//  PlexServer+CatalogArtwork.swift
//  EclipsePlexClient
//

import Foundation

extension PlexServer {

    /// Scheme + host + port only, for joining Plex-relative art paths (`/library/metadata/...`).
    nonisolated var plexOriginURL: URL? {
        let raw = activeHostDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let withScheme: String
        if raw.contains("://") {
            withScheme = raw
        } else {
            withScheme = "http://\(raw)"
        }

        guard let parsed = URL(string: withScheme),
              var components = URLComponents(url: parsed, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// Absolute URL for a metadata thumb/composite path from Plex (e.g. `thumb` on a `Video` / `Directory`).
    ///
    /// When `targetPixelSize` is provided, the URL is wrapped via the Plex
    /// `/photo/:/transcode` endpoint so the server resizes the image before
    /// sending it. This avoids hauling multi-MB posters down for 48×72 list
    /// cells.
    nonisolated func catalogArtworkURL(
        relativeThumbPath: String?,
        targetPixelSize: CGSize? = nil
    ) -> URL? {
        guard let thumb = relativeThumbPath?.trimmingCharacters(in: .whitespacesAndNewlines), !thumb.isEmpty,
              let origin = plexOriginURL else { return nil }

        let path = thumb.hasPrefix("/") ? thumb : "/" + thumb
        guard let absolute = URL(string: path, relativeTo: origin)?.absoluteURL else { return nil }

        let baseURL = appendingTokenIfNeeded(absolute)

        guard let target = targetPixelSize,
              target.width > 0,
              target.height > 0,
              let baseURL,
              var transcode = URLComponents(url: origin.appendingPathComponent("/photo/:/transcode"), resolvingAgainstBaseURL: false)
        else {
            return baseURL
        }

        var items: [URLQueryItem] = [
            URLQueryItem(name: "url", value: baseURL.absoluteString),
            URLQueryItem(name: "width", value: String(Int(target.width.rounded()))),
            URLQueryItem(name: "height", value: String(Int(target.height.rounded()))),
            URLQueryItem(name: "minSize", value: "1"),
            URLQueryItem(name: "upscale", value: "1"),
        ]
        if let token = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            items.append(URLQueryItem(name: "X-Plex-Token", value: token))
        }
        transcode.queryItems = items
        return transcode.url ?? baseURL
    }

    private nonisolated func appendingTokenIfNeeded(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        if let token = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            var items = components.queryItems ?? []
            if !items.contains(where: { $0.name == "X-Plex-Token" }) {
                items.append(URLQueryItem(name: "X-Plex-Token", value: token))
            }
            components.queryItems = items
        }
        return components.url
    }

    /// Query parameters Plex expects on playback/transcode URLs opened by external players (VLC).
    nonisolated var plexPlaybackQueryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let token = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            items.append(URLQueryItem(name: "X-Plex-Token", value: token))
        }
        items.append(URLQueryItem(name: "X-Plex-Client-Identifier", value: PlexHTTPConstants.clientIdentifier))
        items.append(URLQueryItem(name: "X-Plex-Product", value: PlexHTTPConstants.productName))
        items.append(URLQueryItem(name: "X-Plex-Version", value: PlexHTTPConstants.productVersion))
        items.append(URLQueryItem(name: "X-Plex-Platform", value: "macOS"))
        items.append(URLQueryItem(name: "X-Plex-Device", value: "EclipsePlexClient"))
        return items
    }

    /// Absolute URL for a Plex-relative API path (metadata, parts, transcode, etc.).
    nonisolated func plexResourceURL(
        relativePath: String,
        extraQueryItems: [URLQueryItem] = []
    ) -> URL? {
        guard let origin = plexOriginURL else { return nil }

        let path = relativePath.hasPrefix("/") ? relativePath : "/" + relativePath
        guard let absolute = URL(string: path, relativeTo: origin)?.absoluteURL else { return nil }
        guard var components = URLComponents(url: absolute, resolvingAgainstBaseURL: false) else {
            return absolute
        }

        var items = components.queryItems ?? []
        if let token = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            if !items.contains(where: { $0.name == "X-Plex-Token" }) {
                items.append(URLQueryItem(name: "X-Plex-Token", value: token))
            }
        }
        for query in extraQueryItems where !items.contains(where: { $0.name == query.name }) {
            items.append(query)
        }
        components.queryItems = items
        return components.url
    }
}
