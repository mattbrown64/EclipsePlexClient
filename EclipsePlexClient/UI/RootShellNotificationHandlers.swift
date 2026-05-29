//
//  RootShellNotificationHandlers.swift
//  EclipsePlexClient
//

import SwiftUI

/// Notification wiring for `RootShellView` (keeps the main body type-checkable).
struct RootShellNotificationHandlers: ViewModifier {
    @ObservedObject var plexRegistry: PlexServerRegistry
    let plexServers: [PlexServer]
    @Binding var connectionPickerServer: PlexServer?
    var refreshSelectedServerLibraries: () -> Void
    var presentBrowseMenu: () -> Void
    var presentServerSearch: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .eclipsePlexOpenBrowseMenu)) { _ in
                presentBrowseMenu()
            }
            .onReceive(NotificationCenter.default.publisher(for: .eclipsePlexOpenSearch)) { _ in
                presentServerSearch()
            }
            .onReceive(NotificationCenter.default.publisher(for: .eclipsePlexRefreshLibraries)) { _ in
                refreshSelectedServerLibraries()
            }
            .onReceive(NotificationCenter.default.publisher(for: .eclipsePlexRefreshAll)) { _ in
                Task {
                    await plexRegistry.refreshAllLibraries(force: true)
                    await AggregateHomeHubService.invalidateAll()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .eclipsePlexOpenConnectionPicker)) { note in
                guard let id = note.userInfo?["serverId"] as? UUID,
                      let server = plexServers.first(where: { $0.id == id })
                else { return }
                connectionPickerServer = server
            }
    }
}
