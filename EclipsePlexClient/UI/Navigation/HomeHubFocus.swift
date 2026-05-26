//
//  HomeHubFocus.swift
//  EclipsePlexClient
//

import SwiftUI

/// One keyboard-focusable tile on a home screen (Continue Watching / Recently Added).
struct HomeFocusItem: Identifiable {
    let id: String
    let activate: @MainActor () -> Void
}

enum HomeHubFocus {
    static func focusID(shelfKey: String, hit: PlexCatalogSearchHit) -> String {
        "home|\(shelfKey)|\(hit.id)"
    }

    static func appendItems(
        into items: inout [HomeFocusItem],
        shelfKey: String,
        hits: [PlexCatalogSearchHit],
        plexServer: PlexServer,
        navigation: CatalogNavigationActions,
        onSelectServer: ((UUID) -> Void)? = nil,
        navigatesInPlace: Bool = false
    ) {
        for hit in hits {
            let itemID = focusID(shelfKey: shelfKey, hit: hit)
            items.append(
                HomeFocusItem(id: itemID) {
                    if !navigatesInPlace {
                        onSelectServer?(plexServer.id)
                        navigation.selectLibrary(hit.library)
                    }
                    navigation.pushRoute(hubRoute(for: hit))
                }
            )
        }
    }

    static func hubRoute(for hit: PlexCatalogSearchHit) -> CatalogNavigationRoute {
        switch hit.node {
        case .show(let show):
            return .showDetail(library: hit.library, show: show)
        case .season(let season):
            return .browse(
                library: hit.library,
                parent: .season(ratingKey: season.ratingKey),
                navigationTitle: season.title
            )
        case .movie, .episode, .musicTrack, .photo:
            return .media(library: hit.library, node: hit.node)
        }
    }
}
