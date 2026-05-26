//
//  SidebarFocusRowBuilderExtendedTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct SidebarFocusRowBuilderExtendedTests {
    @Test func noServerSectionWhenNothingSelected() {
        let ids = SidebarFocusRowBuilder.rowIDs(
            deviceServers: [PlexServer.downloads],
            plexServers: PlexSampleData.servers,
            selectedServer: nil,
            libraries: []
        )
        #expect(!ids.contains(AppSidebarView.FocusRowID.serverHome))
        #expect(!ids.contains(where: { $0.hasPrefix("library-") }))
    }

    @Test func liveServerIncludesPlaylistsRow() {
        let live = PlexServer(
            name: "Live",
            hostDescription: "https://192.168.1.1:32400",
            accessToken: "token"
        )
        let ids = SidebarFocusRowBuilder.rowIDs(
            deviceServers: [],
            plexServers: [live],
            selectedServer: live,
            libraries: [
                PlexLibrary(
                    serverId: live.id,
                    sectionKey: "1",
                    title: "Movies",
                    type: 1
                ),
            ]
        )
        #expect(ids.contains(AppSidebarView.FocusRowID.playlists))
    }

    @Test func downloadsServerOmitsPlaylists() {
        let ids = SidebarFocusRowBuilder.rowIDs(
            deviceServers: [],
            plexServers: [],
            selectedServer: PlexServer.downloads,
            libraries: OfflineDownloadsLibrary.libraries(for: PlexServer.downloadsServerID)
        )
        #expect(!ids.contains(AppSidebarView.FocusRowID.playlists))
    }

    @Test func deviceServersListedFirst() {
        let downloads = PlexServer.downloads
        let ids = SidebarFocusRowBuilder.rowIDs(
            deviceServers: [downloads],
            plexServers: [],
            selectedServer: nil,
            libraries: []
        )
        #expect(ids.first == AppSidebarView.FocusRowID.downloadsServer(downloads.id))
    }
}
