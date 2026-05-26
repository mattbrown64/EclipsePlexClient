//
//  PlexServerAdmin.swift
//  EclipsePlexClient
//

import Foundation

/// One active playback session on a Plex Media Server (`/status/sessions`).
nonisolated struct PlexActiveSession: Identifiable, Hashable, Sendable {
    let id: String
    /// Value for `sessionId` on `/status/sessions/terminate`.
    let terminateSessionId: String
    let title: String
    let subtitle: String?
    let userName: String?
    let player: String?
    let state: String?
    let viewOffsetMs: Int?
    let durationMs: Int?

    var progress: Double? {
        guard let viewOffsetMs, let durationMs, durationMs > 0 else { return nil }
        return min(1, max(0, Double(viewOffsetMs) / Double(durationMs)))
    }
}

/// Cached admin capability probe for a server.
nonisolated struct PlexServerAdminCapabilities: Sendable, Equatable {
    var canViewSessions: Bool
    var canManageLibraries: Bool
    var canManageServer: Bool

    static let unknown = PlexServerAdminCapabilities(
        canViewSessions: false,
        canManageLibraries: false,
        canManageServer: false
    )

    var canTerminateSessions: Bool { canViewSessions && canManageServer }
}

/// Read-only server status from `GET /:/prefs` and `GET /identity`.
nonisolated struct PlexServerStatusInfo: Sendable, Equatable {
    var friendlyName: String?
    var version: String?
    var platform: String?
    var publishToPlex: Bool?
    var secureConnections: String?
    var relayEnabled: Bool?
    var manualPortMapping: Bool?
}

/// Plex home user from `GET /accounts`.
nonisolated struct PlexServerUser: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let thumbPath: String?
    let isAdmin: Bool
    let isManaged: Bool
}

/// Fields editable via `PUT /library/metadata/{id}`.
nonisolated struct PlexMetadataEditRequest: Sendable, Equatable {
    var title: String?
    var summary: String?
    var year: Int?
    var lockTitle: Bool = false
    var lockSummary: Bool = false
    var lockYear: Bool = false
}

/// Query hints for `GET /library/metadata/{id}/matches` (Plex “Search options”).
nonisolated struct FixMatchSearchHints: Sendable, Equatable {
    var title: String?
    var year: Int?
    /// TV episode: series title (`grandparentTitle`).
    var showTitle: String?
    /// TV episode / season: season label (`parentTitle`).
    var seasonTitle: String?
    var manual: Bool = true

    var trimmedTitle: String? {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    var trimmedShowTitle: String? {
        let t = showTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    var trimmedSeasonTitle: String? {
        let t = seasonTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }
}

/// A possible metadata match returned by Plex for fix-match flows.
nonisolated struct PlexMetadataMatchCandidate: Identifiable, Hashable, Sendable {
    let guid: String
    let title: String
    let year: Int?
    let summary: String?
    let thumbPath: String?

    var id: String { guid }
}
