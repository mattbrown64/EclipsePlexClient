//
//  PlexServer+WebLinks.swift
//  EclipsePlexClient
//

import Foundation

extension PlexServer {
    /// Plex Web App deep link for a library metadata item.
    nonisolated func plexWebMetadataURL(ratingKey: String) -> URL? {
        guard let clientID = plexResourceClientIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !clientID.isEmpty
        else { return nil }
        let key = Self.metadataKeyPath(ratingKey: ratingKey)
        guard let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://app.plex.tv/desktop/#!/server/\(clientID)/details?key=\(encoded)")
    }

    /// Local Plex Web (`/web`) detail URL when the server origin is known.
    nonisolated func localWebMetadataURL(ratingKey: String) -> URL? {
        guard let origin = plexOriginURL else { return nil }
        let key = Self.metadataKeyPath(ratingKey: ratingKey)
        guard let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "\(origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/web/index.html#!/server/details?key=\(encoded)")
    }

    nonisolated private static func metadataKeyPath(ratingKey: String) -> String {
        let trimmed = ratingKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/library/metadata/") { return trimmed }
        let id = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        return "/library/metadata/\(id)"
    }
}
