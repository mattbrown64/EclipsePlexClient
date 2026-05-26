//
//  SidebarFocusRowBuilderTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct SidebarFocusRowBuilderTests {
    @Test func rowOrderMatchesVisibleSidebar() {
        let downloads = PlexServer.downloads
        let home = PlexSampleData.servers[0]
        let libraries = PlexSampleData.libraries(for: home.id)

        let ids = SidebarFocusRowBuilder.rowIDs(
            deviceServers: [downloads],
            plexServers: [home],
            selectedServer: home,
            libraries: libraries
        )

        #expect(ids.first == AppSidebarView.FocusRowID.downloadsServer(downloads.id))
        #expect(ids.contains(AppSidebarView.FocusRowID.aggregateHome))
        #expect(ids.contains(AppSidebarView.FocusRowID.plexServer(home.id)))
        #expect(ids.contains(AppSidebarView.FocusRowID.serverHome))
        #expect(ids.contains(AppSidebarView.FocusRowID.library(libraries[0].id)))
        #expect(ids.last == AppSidebarView.FocusRowID.settings)
    }

    @Test func playlistsRowOnlyForLiveServer() {
        let fixture = PlexSampleData.servers[0]
        let withoutPlaylists = SidebarFocusRowBuilder.rowIDs(
            deviceServers: [],
            plexServers: [],
            selectedServer: fixture,
            libraries: []
        )
        #expect(!withoutPlaylists.contains(AppSidebarView.FocusRowID.playlists))
    }
}
