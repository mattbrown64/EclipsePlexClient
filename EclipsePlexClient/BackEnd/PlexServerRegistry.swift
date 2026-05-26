//
//  PlexServerRegistry.swift
//  EclipsePlexClient
//

import Combine
import Foundation

/// Persisted user-added Plex servers and cached `/library/sections` for live (token + URL) servers.
@MainActor
final class PlexServerRegistry: ObservableObject {
    struct ReachabilitySnapshot: Codable {
        var lastOnlineAt: Date?
        var lastOfflineAt: Date?
    }

    @Published private(set) var customServers: [PlexServer] = []
    @Published private(set) var librariesByServerID: [UUID: [PlexLibrary]] = [:]
    @Published var librariesLoadError: String?
    @Published var librariesLoadErrorServerID: UUID?
    @Published private(set) var librariesLoadingServerID: UUID?
    /// Last reachability probe per server (`nil` = unknown).
    @Published private(set) var serverReachable: [UUID: Bool] = [:]
    @Published private(set) var serverReachabilityHistory: [UUID: ReachabilitySnapshot] = [:]
    @Published private(set) var serverAdminCapabilities: [UUID: PlexServerAdminCapabilities] = [:]

    func setServerReachable(_ reachable: Bool?, for serverID: UUID) {
        serverReachable[serverID] = reachable
        guard let reachable else { return }
        var snapshot = serverReachabilityHistory[serverID] ?? ReachabilitySnapshot()
        if reachable {
            snapshot.lastOnlineAt = Date()
        } else {
            snapshot.lastOfflineAt = Date()
        }
        serverReachabilityHistory[serverID] = snapshot
        saveReachabilityHistory()
    }

    func lastOnlineAt(for serverID: UUID) -> Date? {
        serverReachabilityHistory[serverID]?.lastOnlineAt
    }

    func setAdminCapabilities(_ capabilities: PlexServerAdminCapabilities, for serverID: UUID) {
        serverAdminCapabilities[serverID] = capabilities
    }

    func clearAdminCapabilities(for serverID: UUID) {
        serverAdminCapabilities[serverID] = nil
    }

    /// Plex.tv account token (PIN sign-in). Used only to refresh the server list, not for PMS calls.
    @Published private(set) var plexAccountAuthToken: String?

    private let userDefaultsKey = "plexCustomServers.v1"
    private let reachabilityHistoryKey = "plexServerReachabilityHistory.v1"

    /// Per-server timestamps used to skip redundant probes when the UI re-runs
    /// `.task` blocks during normal navigation. Force-refresh bypasses these.
    private var lastReachabilityProbeAt: [UUID: Date] = [:]
    private var lastLibraryRefreshAt: [UUID: Date] = [:]
    static let reachabilityTTL: TimeInterval = 60
    static let libraryTTL: TimeInterval = 120

    func reachabilityCacheIsFresh(for serverID: UUID) -> Bool {
        guard let last = lastReachabilityProbeAt[serverID] else { return false }
        return Date().timeIntervalSince(last) < Self.reachabilityTTL
    }

    func recordReachabilityProbe(for serverID: UUID) {
        lastReachabilityProbeAt[serverID] = Date()
    }

    func libraryCacheIsFresh(for serverID: UUID) -> Bool {
        guard let last = lastLibraryRefreshAt[serverID] else { return false }
        return Date().timeIntervalSince(last) < Self.libraryTTL
    }

    func recordLibraryRefresh(for serverID: UUID) {
        lastLibraryRefreshAt[serverID] = Date()
    }

    func invalidateLibraryCache(for serverID: UUID? = nil) {
        if let serverID {
            lastLibraryRefreshAt[serverID] = nil
        } else {
            lastLibraryRefreshAt.removeAll()
        }
    }

    init() {
        KeychainStore.migrateFromUserDefaultsIfNeeded()
        plexAccountAuthToken = KeychainStore.loadPlexAccountToken()
        loadFromDisk()
        loadReachabilityHistory()
        applyUITestLaunchArgumentsIfNeeded()
    }

    /// Seeds sample servers/libraries when UI tests pass `-UITestSeedSampleData`.
    func applyUITestLaunchArgumentsIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-UITestSeedSampleData") else { return }
        customServers = []
        librariesByServerID = [:]
        for server in PlexSampleData.servers {
            addCustomServer(server)
            librariesByServerID[server.id] = PlexSampleData.libraries(for: server.id)
        }
    }

    func setPlexAccountToken(_ token: String?) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            plexAccountAuthToken = trimmed
            KeychainStore.savePlexAccountToken(trimmed)
        } else {
            plexAccountAuthToken = nil
            KeychainStore.savePlexAccountToken(nil)
        }
    }

    var allServers: [PlexServer] {
        customServers.map { $0.withTokenFromKeychain() }
    }

    func isUserAddedServer(id: UUID) -> Bool {
        customServers.contains { $0.id == id }
    }

    func updateCustomServer(_ server: PlexServer) {
        guard let idx = customServers.firstIndex(where: { $0.id == server.id }) else { return }
        persistToken(server.accessToken, for: server.id)
        customServers[idx] = server.persistedWithoutToken
        saveToDisk()
    }

    func addCustomServer(_ server: PlexServer) {
        if let rid = server.plexResourceClientIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !rid.isEmpty {
            customServers.removeAll { $0.plexResourceClientIdentifier == rid }
        }
        persistToken(server.accessToken, for: server.id)
        customServers.append(server.persistedWithoutToken)
        librariesByServerID[server.id] = nil
        saveToDisk()
    }

    func removeCustomServer(id: UUID) {
        customServers.removeAll { $0.id == id }
        KeychainStore.setToken(nil, forServerID: id)
        librariesByServerID[id] = nil
        serverReachable[id] = nil
        serverReachabilityHistory[id] = nil
        clearAdminCapabilities(for: id)
        if librariesLoadErrorServerID == id {
            librariesLoadError = nil
            librariesLoadErrorServerID = nil
        }
        saveToDisk()
        saveReachabilityHistory()
    }

    func refreshLibraries(for server: PlexServer, force: Bool = false) async {
        let server = server.withTokenFromKeychain()
        guard server.usesLivePlexAPI else {
            librariesByServerID[server.id] = nil
            if librariesLoadErrorServerID == server.id {
                librariesLoadError = nil
                librariesLoadErrorServerID = nil
            }
            return
        }
        if !force,
           libraryCacheIsFresh(for: server.id),
           let existing = librariesByServerID[server.id],
           !existing.isEmpty {
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
            recordLibraryRefresh(for: server.id)
        } catch let firstError {
            if let repaired = await refreshDiscoveredServerConnection(serverId: server.id) {
                do {
                    let client = try PlexMediaServerClient(server: repaired)
                    let libs = try await client.fetchLibraries(serverId: repaired.id)
                    librariesByServerID[repaired.id] = libs
                    recordLibraryRefresh(for: repaired.id)
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
        }
    }

    /// Refreshes multiple servers' library lists in parallel with bounded
    /// concurrency. Used by aggregate home / root shell launch paths to avoid
    /// the serial N-server wait the audit flagged.
    func refreshLibraries(for servers: [PlexServer], force: Bool = false) async {
        let live = servers.filter(\.usesLivePlexAPI)
        guard !live.isEmpty else { return }
        let maxConcurrency = 4

        await withTaskGroup(of: Void.self) { group in
            var iterator = live.makeIterator()
            for _ in 0 ..< min(maxConcurrency, live.count) {
                guard let next = iterator.next() else { break }
                group.addTask { await self.refreshLibraries(for: next, force: force) }
            }
            while await group.next() != nil {
                guard let next = iterator.next() else { continue }
                group.addTask { await self.refreshLibraries(for: next, force: force) }
            }
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
            persistToken(match.accessToken, for: customServers[idx].id)
            if !match.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                customServers[idx].name = match.name
            }
            if let owned = match.isOwnedServer {
                customServers[idx].isOwnedServer = owned
            }
            saveToDisk()
            return customServers[idx].withTokenFromKeychain()
        } catch {
            return nil
        }
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([PlexServer].self, from: data) else { return }
        customServers = decoded.map { $0.persistedWithoutToken }
        if decoded.contains(where: { ($0.accessToken?.isEmpty == false) }) {
            saveToDisk()
        }
    }

    private func saveToDisk() {
        let stripped = customServers.map { $0.persistedWithoutToken }
        guard let data = try? JSONEncoder().encode(stripped) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private func persistToken(_ token: String?, for serverID: UUID) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            KeychainStore.setToken(trimmed, forServerID: serverID)
        } else {
            KeychainStore.setToken(nil, forServerID: serverID)
        }
    }

    private func loadReachabilityHistory() {
        guard let data = UserDefaults.standard.data(forKey: reachabilityHistoryKey),
              let decoded = try? JSONDecoder().decode([UUID: ReachabilitySnapshot].self, from: data)
        else { return }
        serverReachabilityHistory = decoded
    }

    private func saveReachabilityHistory() {
        guard let data = try? JSONEncoder().encode(serverReachabilityHistory) else { return }
        UserDefaults.standard.set(data, forKey: reachabilityHistoryKey)
    }
}
