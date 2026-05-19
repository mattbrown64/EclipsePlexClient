//
//  PlexServer+CatalogArtwork.swift
//  EclipsePlexClient
//

import Foundation

extension PlexServer {

    /// Scheme + host + port only, for joining Plex-relative art paths (`/library/metadata/...`).
    nonisolated var plexOriginURL: URL? {
        let raw = hostDescription.trimmingCharacters(in: .whitespacesAndNewlines)
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
    nonisolated func catalogArtworkURL(relativeThumbPath: String?) -> URL? {
        guard let thumb = relativeThumbPath?.trimmingCharacters(in: .whitespacesAndNewlines), !thumb.isEmpty,
              let origin = plexOriginURL else { return nil }

        let path = thumb.hasPrefix("/") ? thumb : "/" + thumb
        guard let absolute = URL(string: path, relativeTo: origin)?.absoluteURL else { return nil }

        guard var components = URLComponents(url: absolute, resolvingAgainstBaseURL: false) else {
            return absolute
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
}
