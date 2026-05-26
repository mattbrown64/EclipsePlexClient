//
//  PlexServerRegistry+Reachability.swift
//  EclipsePlexClient
//

import Foundation

extension PlexServerRegistry {
    /// Probes `/identity` for each live server and updates `serverReachable`.
    ///
    /// Bounded parallel fan-out so app launch isn't gated on the slowest server,
    /// with a short TTL so navigating between tabs doesn't re-probe constantly.
    /// Pass `force = true` from pull-to-refresh / network change handlers.
    func refreshAllReachability(force: Bool = false) async {
        let servers = customServers.filter(\.usesLivePlexAPI)
        guard !servers.isEmpty else { return }
        let maxConcurrency = 4

        await withTaskGroup(of: Void.self) { group in
            var iterator = servers.makeIterator()
            for _ in 0 ..< min(maxConcurrency, servers.count) {
                guard let next = iterator.next() else { break }
                group.addTask { await self.refreshReachability(for: next, force: force) }
            }
            while await group.next() != nil {
                guard let next = iterator.next() else { continue }
                group.addTask { await self.refreshReachability(for: next, force: force) }
            }
        }
    }

    func refreshReachability(for server: PlexServer, force: Bool = false) async {
        guard server.usesLivePlexAPI else {
            setServerReachable(nil, for: server.id)
            return
        }
        if !force, reachabilityCacheIsFresh(for: server.id) {
            return
        }
        let active = server.withActiveConnection()
        do {
            let client = try PlexMediaServerClient(server: active)
            try await client.verifyReachable()
            setServerReachable(true, for: server.id)
        } catch {
            setServerReachable(false, for: server.id)
        }
        recordReachabilityProbe(for: server.id)
    }
}
