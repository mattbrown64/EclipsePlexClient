//
//  PlexServerWebLinksTests.swift
//  EclipsePlexClientTests
//

import Foundation
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
        #expect(url != nil)
        let absolute = url!.absoluteString
        #expect(absolute.contains("abc-123"))
        #expect(absolute.contains("/library/metadata/42"))
    }

    @Test func localWebMetadataURLUsesOrigin() {
        let server = PlexServer(
            name: "NAS",
            hostDescription: "http://192.168.1.5:32400"
        )
        let url = server.localWebMetadataURL(ratingKey: "/library/metadata/99")
        #expect(url != nil)
        let absolute = url!.absoluteString
        #expect(absolute.contains("192.168.1.5:32400"))
        #expect(absolute.contains("/library/metadata/99"))
    }
}
