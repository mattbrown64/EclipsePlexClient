//
//  PlexServerConnectionStatusTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PlexServerConnectionStatusTests {
    @Test func missingTokenWhenKeychainEmpty() {
        let serverID = UUID()
        let server = PlexServer(
            id: serverID,
            name: "NAS",
            hostDescription: "http://127.0.0.1:32400"
        )
        KeychainStore.setToken(nil, forServerID: serverID)
        let issue = PlexServer.connectionIssue(
            for: server,
            reachable: true,
            librariesLoadError: nil,
            librariesLoadErrorServerID: nil
        )
        #expect(issue == .missingToken)
    }

    @Test func configurationErrorMessageMentionsToken() {
        let server = PlexServer(name: "NAS", hostDescription: "http://127.0.0.1:32400")
        let message = PlexServer.configurationLibrariesError(for: server)
        #expect(message.localizedCaseInsensitiveContains("token"))
    }
}
