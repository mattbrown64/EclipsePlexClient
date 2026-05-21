//
//  PlexServerRegistry.swift
//  EclipsePlexClient
//

import Combine
import Foundation

/// Persisted user-added Plex servers and cached `/library/sections` for live (token + URL) servers.
@MainActor
final class PlexServerRegistry: ObservableObject {
    @Published private(set) var customServers: [PlexServer] = []
    @Published private(set) var librariesByServerID: [UUID: [PlexLibrary]] = [:]
    @Published var librariesLoadError: String?
    @Published var librariesLoadErrorServerID: UUID?
    @Published private(set) var librariesLoadingServerID: UUID?
    /// Last reachability probe per server (`nil` = unknown).
    @Published private(set) var serverReachable: [UUID: Bool] = [:]

    /// Plex.tv account token (PIN sign-in). Used only to refresh the server list, not for PMS calls.
    @Published private(set) var plexAccountAuthToken: String?

    private let userDefaultsKey = "plexCustomServers.v1"
    private let accountTokenKey = "plexAccountAuthToken.v1"

    init() {
        plexAccountAuthToken = UserDefaults.standard.string(forKey: accountTokenKey)
        loadFromDisk()
    }

    func setPlexAccountToken(_ token: String?) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            plexAccountAuthToken = trimmed
            UserDefaults.standard.set(trimmed, forKey: accountTokenKey)
        } else {
            plexAccountAuthToken = nil
            UserDefaults.standard.removeObject(forKey: accountTokenKey)
        }
    }

    var allServers: [PlexServer] {
        customServers
    }

    func isUserAddedServer(id: UUID) -> Bool {
        customServers.contains { $0.id == id }
    }

    func updateCustomServer(_ server: PlexServer) {
        guard let idx = customServers.firstIndex(where: { $0.id == server.id }) else { return }
        customServers[idx] = server
        saveToDisk()
    }

    func addCustomServer(_ server: PlexServer) {
        if let rid = server.plexResourceClientIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !rid.isEmpty {
            customServers.removeAll { $0.plexResourceClientIdentifier == rid }
        }
        customServers.append(server)
        librariesByServerID[server.id] = nil
        saveToDisk()
    }

    func removeCustomServer(id: UUID) {
        customServers.removeAll { $0.id == id }
        librariesByServerID[id] = nil
        if librariesLoadErrorServerID == id {
            librariesLoadError = nil
            librariesLoadErrorServerID = nil
        }
        saveToDisk()
    }

    func refreshLibraries(for server: PlexServer) async {
        guard server.usesLivePlexAPI else {
            librariesByServerID[server.id] = nil
            if librariesLoadErrorServerID == server.id {
                librariesLoadError = nil
                librariesLoadErrorServerID = nil
            }
            return
        }
        librariesLoadingServerID = server.id
        librariesLoadError = nil
        librariesLoadErrorServerID = nil
        defer { librariesLoadingServerID = nil }
        do {
            let client = try PlexMediaServerClient(server: server)
            let libs = try await client.fetchLibraries(serverId: server.id)
            librariesByServerID[server.id] = libs
        } catch let firstError {
            if let repaired = await refreshDiscoveredServerConnection(serverId: server.id) {
                do {
                    let client = try PlexMediaServerClient(server: repaired)
                    let libs = try await client.fetchLibraries(serverId: repaired.id)
                    librariesByServerID[repaired.id] = libs
                    librariesLoadError = nil
                    librariesLoadErrorServerID = nil
                    return
                } catch {
                    librariesByServerID[server.id] = nil
                    librariesLoadError = error.localizedDescription
                    librariesLoadErrorServerID = server.id
                    return
                }
            }
            librariesByServerID[server.id] = nil
            librariesLoadError = firstError.localizedDescription
            librariesLoadErrorServerID = server.id
            librariesLoadError = firstError.localizedDescription
            librariesLoadErrorServerID = server.id
        }
    }

    /// For servers added via Plex account, try resources again to get a working URL (fixes bad DNS / stale connection).
    func refreshDiscoveredServerConnection(serverId: UUID) async -> PlexServer? {
        guard let token = plexAccountAuthToken, !token.isEmpty else { return nil }
        guard let idx = customServers.firstIndex(where: { $0.id == serverId }),
              let rid = customServers[idx].plexResourceClientIdentifier,
              !rid.isEmpty else { return nil }
        do {
            let servers = try await PlexAccountAPI.fetchMediaServers(accountToken: token)
            guard let match = servers.first(where: { $0.plexResourceClientIdentifier == rid }) else { return nil }
            customServers[idx].hostDescription = match.hostDescription
            customServers[idx].accessToken = match.accessToken
            if !match.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                customServers[idx].name = match.name
            }
            saveToDisk()
            return customServers[idx]
        } catch {
            return nil
        }
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([PlexServer].self, from: data) else { return }
        customServers = decoded
    }

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(customServers) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
