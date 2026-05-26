//
//  PlexAccountAPITests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PlexAccountAPITests {
    @Test func stableUUIDIsDeterministic() {
        let a = UUID.stableFromPlexResourceIdentifier("client-abc-123")
        let b = UUID.stableFromPlexResourceIdentifier("client-abc-123")
        #expect(a == b)
    }

    @Test func stableUUIDDiffersForDifferentClients() {
        let a = UUID.stableFromPlexResourceIdentifier("client-a")
        let b = UUID.stableFromPlexResourceIdentifier("client-b")
        #expect(a != b)
    }

    @Test func plexAuthPageURLEncodesClientAndCode() {
        let url = PlexAccountAPI.plexAuthPageURL(clientIdentifier: "id/with space", pinCode: "AB&12")
        #expect(url != nil)
        #expect(url?.absoluteString.contains("clientID=") == true)
        #expect(url?.absoluteString.contains("code=") == true)
    }
}
