//
//  SidebarInteractionState.swift
//  EclipsePlexClient
//

import Combine
import SwiftUI

/// Shared state so the split-view sidebar is non-interactive while full-screen style media is up.
final class SidebarInteractionState: ObservableObject {
    @Published var suppressSidebarInteraction = false
}
