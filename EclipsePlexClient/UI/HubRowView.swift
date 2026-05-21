//
//  HubRowView.swift
//  EclipsePlexClient
//

import SwiftUI

/// Horizontal shelf of Plex hub items (Continue Watching, Recently Added).
struct HubRowView: View {
    let title: String
    let hits: [PlexCatalogSearchHit]
    let plexServer: PlexServer

    @Environment(\.catalogNavigationActions) private var catalogNavigation

    var body: some View {
        if hits.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(hits) { hit in
                            Button {
                                catalogNavigation.selectLibrary(hit.library)
                                catalogNavigation.pushRoute(hubRoute(for: hit))
                            } label: {
                                HubTileView(plexServer: plexServer, hit: hit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func hubRoute(for hit: PlexCatalogSearchHit) -> CatalogNavigationRoute {
        switch hit.node {
        case .show(let show):
            return .showDetail(library: hit.library, show: show)
        case .season(let season):
            return .browse(
                library: hit.library,
                parent: .season(ratingKey: season.ratingKey),
                navigationTitle: season.title
            )
        case .movie, .episode, .musicTrack:
            return .media(library: hit.library, node: hit.node)
        }
    }
}

struct HubTileView: View {
    let plexServer: PlexServer
    let hit: PlexCatalogSearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CatalogArtworkImage(
                plexServer: plexServer,
                thumbPath: hit.node.listThumbPath,
                style: .hubTile,
                watchProgressFraction: hit.node.watchProgressFraction
            )
            Text(hit.node.listTitle)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)
            if let subtitle = hit.node.listSubtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)
            }
        }
    }
}
