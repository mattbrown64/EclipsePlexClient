//
//  PlexServer+Secrets.swift
//  EclipsePlexClient
//

import Foundation

extension PlexServer {
    /// Server row for persistence (no access token in UserDefaults JSON).
    var persistedWithoutToken: PlexServer {
        var copy = self
        copy.accessToken = nil
        return copy
    }

    func withTokenFromKeychain() -> PlexServer {
        var copy = self
        if let token = KeychainStore.token(forServerID: id) {
            copy.accessToken = token
        }
        return copy
    }
}
