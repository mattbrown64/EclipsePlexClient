//
//  CatalogNavigationEnvironment.swift
//  EclipsePlexClient
//

import SwiftUI

/// Sidebar / hub actions for the detail column navigation stack.
struct CatalogNavigationActions {
    var selectLibrary: (PlexLibrary) -> Void = { _ in }
    var pushRoute: (CatalogNavigationRoute) -> Void = { _ in }
    var popRoute: () -> Void = {}
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
