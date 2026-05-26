//
//  BrowseMenuEnvironment.swift
//  EclipsePlexClient
//

import SwiftUI

/// Opens the browse menu (overlay on iPhone / compact, sidebar on regular split).
struct OpenBrowseMenuAction {
    var open: () -> Void
}

private struct OpenBrowseMenuKey: EnvironmentKey {
    static let defaultValue: OpenBrowseMenuAction? = nil
}

extension EnvironmentValues {
    var openBrowseMenu: OpenBrowseMenuAction? {
        get { self[OpenBrowseMenuKey.self] }
        set { self[OpenBrowseMenuKey.self] = newValue }
    }
}

/// Closes the browse menu (overlay on iPhone / compact, sidebar on split).
struct DismissBrowseMenuAction {
    var dismiss: () -> Void
}

private struct DismissBrowseMenuKey: EnvironmentKey {
    static let defaultValue: DismissBrowseMenuAction? = nil
}

extension EnvironmentValues {
    var dismissBrowseMenu: DismissBrowseMenuAction? {
        get { self[DismissBrowseMenuKey.self] }
        set { self[DismissBrowseMenuKey.self] = newValue }
    }
}

/// Leading toolbar control for servers and libraries.
struct BrowseToolbarButton: View {
    @Environment(\.openBrowseMenu) private var openBrowseMenu

    var body: some View {
        if let openBrowseMenu {
            Button(action: openBrowseMenu.open) {
                Label("Browse", systemImage: "sidebar.left")
            }
            .accessibilityIdentifier("browseMenuButton")
        }
    }
}

extension View {
    /// iPhone / compact iPad only — macOS split view already exposes the system sidebar toggle.
    func browseMenuToolbar() -> some View {
#if os(iOS) || os(tvOS)
        toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BrowseToolbarButton()
            }
        }
#else
        self
#endif
    }
}
