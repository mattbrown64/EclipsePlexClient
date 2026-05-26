//
//  PlexServerRegistry+Reachability.swift
//  EclipsePlexClient
//

import Foundation

extension PlexServerRegistry {
    /// Probes `/identity` for each live server and updates `serverReachable`.
    func refreshAllReachability() async {
        for server in customServers where server.usesLivePlexAPI {
            await refreshReachability(for: server)
        }
    }

    func refreshReachability(for server: PlexServer) async {
        guard server.usesLivePlexAPI else {
            setServerReachable(nil, for: server.id)
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
    }
}
