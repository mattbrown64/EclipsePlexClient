//
//  PlexServerRegistry+Admin.swift
//  EclipsePlexClient
//

import Foundation

extension PlexServerRegistry {
    /// Probes whether this token can view sessions and manage libraries.
    func refreshAdminCapabilities(for server: PlexServer) async {
        guard server.usesLivePlexAPI else {
            setAdminCapabilities(.unknown, for: server.id)
            return
        }
        let owned = server.isOwnedServer == true
        var caps = PlexServerAdminCapabilities(
            canViewSessions: false,
            canManageLibraries: false,
            canManageServer: owned
        )
        do {
            let client = try PlexMediaServerClient(server: server.withTokenFromKeychain())
            _ = try await client.fetchActiveSessions()
            caps.canViewSessions = true
        } catch {
            caps.canViewSessions = false
        }
        if owned {
            caps.canManageLibraries = true
        } else if caps.canViewSessions {
            caps.canManageLibraries = true
        }
        setAdminCapabilities(caps, for: server.id)
    }

    func adminCapabilities(for serverID: UUID) -> PlexServerAdminCapabilities {
        serverAdminCapabilities[serverID] ?? .unknown
    }
}
