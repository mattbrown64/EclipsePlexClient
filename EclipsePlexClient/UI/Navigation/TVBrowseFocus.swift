//
//  TVBrowseFocus.swift
//  EclipsePlexClient
//

import SwiftUI

#if os(tvOS)
/// Groups browse regions for Siri Remote focus (sidebar vs home hubs vs catalog).
enum TVBrowseFocusSection: Hashable {
    case sidebar
    case homeHubs
    case catalog
    case detailActions
}

/// Focus targets on media detail (Watch / Resume).
enum TVDetailFocusField: Hashable {
    case watch
    case resume
}

extension View {
    /// Marks a browse region for Apple TV focus engine.
    func tvBrowseFocusSection(_ section: TVBrowseFocusSection) -> some View {
        focusSection()
            .accessibilityIdentifier("tvBrowseSection.\(section)")
    }

    /// Horizontal hub shelf: keeps Siri Remote focus inside the shelf.
    func tvHubShelfFocus() -> some View {
        focusSection()
            .accessibilityIdentifier("tvHubShelf")
    }

    /// Card-style focus for poster tiles on Apple TV.
    func tvCatalogTileFocus() -> some View {
        buttonStyle(.card)
            .accessibilityAddTraits(.isButton)
    }
}
#endif
