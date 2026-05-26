//
//  PlexMediaServerURLTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PlexMediaServerURLTests {
    @Test func makeRequestResolvesPlexCommandPathsWithHost() throws {
        let server = PlexServer(
            name: "Home",
            hostDescription: "http://192.168.1.10:32400",
            accessToken: "test-token"
        )
        let client = try PlexMediaServerClient(server: server)
        let request = try client.makeRequest(
            path: "/:/progress",
            query: [URLQueryItem(name: "key", value: "/library/metadata/1")]
        )
        let url = try #require(request.url)
        #expect(url.scheme == "http")
        #expect(url.host == "192.168.1.10")
        #expect(url.port == 32400)
        #expect(url.path == "/:/progress")
        #expect(url.absoluteString.hasPrefix("http://192.168.1.10:32400/:/progress"))
    }
}
