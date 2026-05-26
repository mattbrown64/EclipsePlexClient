//
//  CatalogNavigationEnvironment.swift
//  EclipsePlexClient
//

import SwiftUI

/// Sidebar / hub actions for the detail column navigation stack.
///
/// `RootShellView` constructs this with closures that capture `@State` storage,
/// so the closures' behavior is stable across body re-evaluations even though
/// new closure instances are minted each time. Declare it always-equal so
/// SwiftUI's environment diff doesn't propagate spurious "changes" to every
/// catalog/hub descendant, which previously kicked every visible row through
/// its body whenever the root shell republished anything.
struct CatalogNavigationActions: Equatable {
    var selectLibrary: (PlexLibrary) -> Void = { _ in }
    var pushRoute: (CatalogNavigationRoute) -> Void = { _ in }
    var popRoute: () -> Void = {}

    static func == (lhs: CatalogNavigationActions, rhs: CatalogNavigationActions) -> Bool { true }
}

private struct CatalogNavigationActionsKey: EnvironmentKey {
    static let defaultValue = CatalogNavigationActions()
}

extension EnvironmentValues {
    var catalogNavigationActions: CatalogNavigationActions {
        get { self[CatalogNavigationActionsKey.self] }
        set { self[CatalogNavigationActionsKey.self] = newValue }
    }
}
