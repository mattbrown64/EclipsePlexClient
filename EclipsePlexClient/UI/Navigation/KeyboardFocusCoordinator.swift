//
//  KeyboardFocusCoordinator.swift
//  EclipsePlexClient
//

import Combine
import SwiftUI

/// Documented focus routes for keyboard navigation (Apple TV prep).
enum AppFocusRoute: String, Sendable {
    case sidebar
    case catalogList
    case detailActions
    case player
}

/// Shared keyboard routing state for browse UI.
@MainActor
final class KeyboardFocusCoordinator: ObservableObject {
    @Published var route: AppFocusRoute = .sidebar
    @Published var sidebarFocusedIndex: Int = 0
    @Published var catalogFocusedIndex: Int = 0

    func focusSidebar() { route = .sidebar }
    func focusCatalog() { route = .catalogList }
}

extension View {
    func keyboardFocusRing(active: Bool) -> some View {
        overlay {
            if active {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(2)
            }
        }
    }
}
