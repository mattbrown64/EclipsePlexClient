//  PlexServerTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PlexServerTests {
    @Test func downloadsServerIsStable() {
        #expect(PlexServer.downloads.id == PlexServer.downloadsServerID)
        #expect(PlexServer.downloads.isDownloadsServer)
    }

    @Test func usesLivePlexAPIRequiresTokenAndURL() {
        let noToken = PlexServer(name: "A", hostDescription: "https://plex.local:32400")
        #expect(!noToken.usesLivePlexAPI)
        let withToken = PlexServer(
            name: "B",
            hostDescription: "https://plex.local:32400",
            accessToken: "abc"
        )
        #expect(withToken.usesLivePlexAPI)
    }

    @Test func fixtureServerWithoutTokenIsNotLive() {
        let fixture = PlexSampleData.servers[0]
        #expect(!fixture.usesLivePlexAPI)
    }
}

struct OfflineDownloadsLibraryTests {
    @Test func librariesIncludeMoviesAndTV() {
        let libs = OfflineDownloadsLibrary.libraries(for: PlexServer.downloadsServerID)
        #expect(libs.count == 2)
        #expect(libs.contains(where: OfflineDownloadsLibrary.isMovies))
        #expect(libs.contains(where: OfflineDownloadsLibrary.isTV))
    }
}
