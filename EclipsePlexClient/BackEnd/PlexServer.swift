//
//  PlexServer.swift
//  EclipsePlexClient
//

import Foundation

/// A Plex Media Server the user can connect to.
/// `nonisolated`: module default actor isolation is MainActor.
nonisolated struct PlexServer: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    var name: String
    /// Connection target (URL, host:port, etc.); filled in when networking exists.
    var hostDescription: String
    /// When set, included as `X-Plex-Token` on artwork URLs built from `thumbPath` / `compositePath`.
    var accessToken: String?
    /// Plex.tv resource id from account discovery; used to dedupe when re-adding the same server.
    var plexResourceClientIdentifier: String?
    /// When discovered via Plex account, whether this server is owned by the signed-in user.
    var isOwnedServer: Bool?

    init(
        id: UUID = UUID(),
        name: String,
        hostDescription: String,
        accessToken: String? = nil,
        plexResourceClientIdentifier: String? = nil,
        isOwnedServer: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.hostDescription = hostDescription
        self.accessToken = accessToken
        self.plexResourceClientIdentifier = plexResourceClientIdentifier
        self.isOwnedServer = isOwnedServer
    }

    /// Live Plex Media Server JSON API when we have an origin URL and a non-empty token.
    var usesLivePlexAPI: Bool {
        let t = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return plexOriginURL != nil && !t.isEmpty
    }
}
