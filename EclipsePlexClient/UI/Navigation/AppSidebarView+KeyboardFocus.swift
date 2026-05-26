//
//  AppSidebarView+KeyboardFocus.swift
//  EclipsePlexClient
//

import SwiftUI

extension AppSidebarView {
    /// Stable row ids for keyboard focus (order must match `buildSidebarFocusRows`).
    enum FocusRowID {
        static func downloadsServer(_ id: UUID) -> String { "downloads-\(id.uuidString)" }
        static let aggregateHome = "aggregate-home"
        static func plexServer(_ id: UUID) -> String { "plex-\(id.uuidString)" }
        static let serverHome = "server-home"
        static func library(_ id: String) -> String { "library-\(id)" }
        static let playlists = "playlists"
        static let settings = "settings"
    }

    func buildSidebarFocusRows() -> [SidebarFocusRow] {
        let ids = SidebarFocusRowBuilder.rowIDs(
            deviceServers: deviceServers,
            plexServers: plexServers,
            selectedServer: selectedServer,
            libraries: libraries
        )
        return ids.map { id in
            SidebarFocusRow(id: id) { performSidebarAction(rowID: id) }
        }
    }

    private func performSidebarAction(rowID: String) {
        if let server = deviceServers.first(where: { FocusRowID.downloadsServer($0.id) == rowID }) {
            onSelectServer(server.id)
            return
        }
        if rowID == FocusRowID.aggregateHome {
            onSelectAllServersHome()
            return
        }
        if let server = plexServers.first(where: { FocusRowID.plexServer($0.id) == rowID }) {
            onSelectServer(server.id)
            return
        }
        if rowID == FocusRowID.serverHome {
            onSelectHome()
            return
        }
        if let library = libraries.first(where: { FocusRowID.library($0.id) == rowID }) {
            onSelectLibrary(library)
            return
        }
        if rowID == FocusRowID.playlists {
            onSelectPlaylists()
            return
        }
        if rowID == FocusRowID.settings {
            onSelectSettings()
        }
    }

    func isSidebarFocusActive(rowID: String, rows: [SidebarFocusRow], coordinator: KeyboardFocusCoordinator) -> Bool {
        guard coordinator.route == .sidebar,
              let index = rows.firstIndex(where: { $0.id == rowID })
        else { return false }
        return coordinator.sidebarFocusedIndex == index
    }
}
