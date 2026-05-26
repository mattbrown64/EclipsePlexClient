//
//  SidebarFocusRowBuilder.swift
//  EclipsePlexClient
//

import Foundation

/// Builds keyboard-focus row order for the browse sidebar (shared by UI and tests).
enum SidebarFocusRowBuilder {
    static func rowIDs(
        deviceServers: [PlexServer],
        plexServers: [PlexServer],
        selectedServer: PlexServer?,
        libraries: [PlexLibrary]
    ) -> [String] {
        var ids: [String] = []
        for server in deviceServers {
            ids.append(AppSidebarView.FocusRowID.downloadsServer(server.id))
        }
        ids.append(AppSidebarView.FocusRowID.aggregateHome)
        for server in plexServers {
            ids.append(AppSidebarView.FocusRowID.plexServer(server.id))
        }
        if let selectedServer {
            ids.append(AppSidebarView.FocusRowID.serverHome)
            for library in libraries {
                ids.append(AppSidebarView.FocusRowID.library(library.id))
            }
            if selectedServer.usesLivePlexAPI, !selectedServer.isDownloadsServer {
                ids.append(AppSidebarView.FocusRowID.playlists)
            }
        }
        ids.append(AppSidebarView.FocusRowID.settings)
        return ids
    }
}
