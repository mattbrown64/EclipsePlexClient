//
//  PlexServer+Connections.swift
//  EclipsePlexClient
//

import Foundation

extension PlexServer {
    /// Alternate PMS base URLs (LAN, relay, plex.direct) discovered from Plex.tv resources.
    var connectionCandidates: [String] {
        get {
            PlexServerConnectionStore.candidates(for: id)
        }
        set {
            PlexServerConnectionStore.setCandidates(newValue, for: id)
        }
    }

    /// User-selected connection index into `connectionCandidates`, or active `hostDescription`.
    var activeHostDescription: String {
        PlexServerConnectionStore.activeHost(for: id) ?? hostDescription
    }

    /// Server copy using the active connection URL.
    func withActiveConnection() -> PlexServer {
        var copy = self
        let host = activeHostDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.isEmpty { copy.hostDescription = host }
        return copy
    }

    var isRelayConnection: Bool {
        let host = activeHostDescription.lowercased()
        return host.contains("plex.tv/api/servers") || host.contains(".plex.direct") && host.contains("relay")
    }
}

/// Persists discovered connection URLs and user preference per server.
enum PlexServerConnectionStore {
    private static let candidatesPrefix = "plexServer.connections."
    private static let activePrefix = "plexServer.activeConnection."

    static func candidates(for serverId: UUID) -> [String] {
        UserDefaults.standard.stringArray(forKey: candidatesPrefix + serverId.uuidString) ?? []
    }

    static func setCandidates(_ urls: [String], for serverId: UUID) {
        let trimmed = urls.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        UserDefaults.standard.set(trimmed, forKey: candidatesPrefix + serverId.uuidString)
    }

    static func activeHost(for serverId: UUID) -> String? {
        let key = activePrefix + serverId.uuidString
        let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    static func setActiveHost(_ url: String?, for serverId: UUID) {
        let key = activePrefix + serverId.uuidString
        if let url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.set(url, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
