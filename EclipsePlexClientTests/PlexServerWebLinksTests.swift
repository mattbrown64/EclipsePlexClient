//
//  PlexServerWebLinksTests.swift
//  EclipsePlexClientTests
//

import Testing
@testable import EclipsePlexClient

struct PlexServerWebLinksTests {
    @Test func plexWebMetadataURLEncodesKey() {
        let server = PlexServer(
            name: "NAS",
            hostDescription: "http://192.168.1.5:32400",
            plexResourceClientIdentifier: "abc-123"
        )
        let url = server.plexWebMetadataURL(ratingKey: "42")
        #expect(url?.absoluteString.contains("abc-123") == true)
        #expect(url?.absoluteString.contains("%2Flibrary%2Fmetadata%2F42") == true)
    }

    @Test func localWebMetadataURLUsesOrigin() {
        let server = PlexServer(
            name: "NAS",
            hostDescription: "http://192.168.1.5:32400"
        )
        let url = server.localWebMetadataURL(ratingKey: "/library/metadata/99")
        #expect(url?.absoluteString.contains("192.168.1.5:32400") == true)
        #expect(url?.absoluteString.contains("metadata%2F99") == true)
    }
}
