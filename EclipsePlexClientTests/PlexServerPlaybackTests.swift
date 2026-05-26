//
//  PlexServerPlaybackTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PlexServerPlaybackTests {
    @Test func plexOriginURLFromHostPort() {
        let server = PlexServer(name: "Home", hostDescription: "192.168.1.10:32400")
        #expect(server.plexOriginURL?.host == "192.168.1.10")
        #expect(server.plexOriginURL?.port == 32400)
    }

    @Test func plexOriginURLFromHTTPS() {
        let server = PlexServer(name: "Remote", hostDescription: "https://plex.example.com:443/path")
        #expect(server.plexOriginURL?.scheme == "https")
        #expect(server.plexOriginURL?.host == "plex.example.com")
    }

    @Test func emptyHostHasNoOrigin() {
        let server = PlexServer(name: "X", hostDescription: "   ")
        #expect(server.plexOriginURL == nil)
    }

    @Test func vlcHeadersIncludeTokenWhenPresent() {
        let server = PlexServer(
            name: "S",
            hostDescription: "http://127.0.0.1:32400",
            accessToken: "tok123"
        )
        #expect(server.vlcHTTPHeaderFields["X-Plex-Token"] == "tok123")
        #expect(server.vlcHTTPHeaderFields["X-Plex-Platform"] == "macOS")
    }

    @Test func vlcExtraHeadersOptionEndsWithCRLF() {
        let server = PlexServer(name: "S", hostDescription: "http://127.0.0.1:32400", accessToken: "t")
        let option = server.vlcHTTPExtraHeadersOption
        #expect(option?.hasSuffix("\r\n") == true)
        #expect(option?.contains("X-Plex-Token: t") == true)
    }

    @Test func transcodeQueryIncludesSessionAndPath() {
        let server = PlexServer(name: "S", hostDescription: "http://127.0.0.1:32400")
        let items = server.plexTranscodeQueryItems(
            sessionID: "sess-1",
            metadataPath: "/library/metadata/99",
            mediaIndex: 0,
            partIndex: 0,
            protocol: "http",
            directPlay: "0",
            directStream: "1"
        )
        #expect(items.contains { $0.name == "session" && $0.value == "sess-1" })
        #expect(items.contains { $0.name == "path" && $0.value == "/library/metadata/99" })
        #expect(items.contains { $0.name == "copyts" && $0.value == "1" })
    }

    @Test func transcodeQueryOmitsCopytsForHLS() {
        let server = PlexServer(name: "S", hostDescription: "http://127.0.0.1:32400")
        let items = server.plexTranscodeQueryItems(
            sessionID: "s",
            metadataPath: "/library/metadata/1",
            mediaIndex: 0,
            partIndex: 0,
            protocol: "hls",
            directPlay: "0",
            directStream: "0"
        )
        #expect(!items.contains { $0.name == "copyts" })
    }
}
