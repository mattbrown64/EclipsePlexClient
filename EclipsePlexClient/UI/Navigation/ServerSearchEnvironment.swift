//
//  ServerSearchEnvironment.swift
//  EclipsePlexClient
//

import SwiftUI

/// Presents server-wide search for the selected Plex source (toolbar or ⌘F).
struct OpenServerSearchAction {
    var open: () -> Void
}

private struct OpenServerSearchKey: EnvironmentKey {
    static let defaultValue: OpenServerSearchAction? = nil
}

extension EnvironmentValues {
    var openServerSearch: OpenServerSearchAction? {
        get { self[OpenServerSearchKey.self] }
        set { self[OpenServerSearchKey.self] = newValue }
    }
}

extension Notification.Name {
    static let eclipsePlexOpenSearch = Notification.Name("eclipsePlexOpenSearch")
    static let eclipsePlexRefreshLibraries = Notification.Name("eclipsePlexRefreshLibraries")
}
