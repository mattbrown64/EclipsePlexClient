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
    /// Prefix for `HomeHubFocus` ids (e.g. `cw`, `ra`, or `serverUUID|cw`).
    var shelfKey: String = ""
    /// Index of the first hit in the parent home focus list.
    var homeFocusRangeStart: Int = 0
    var onSelectServer: ((UUID) -> Void)? = nil
    /// When true, only pushes a catalog route (already inside the target library).
    var navigatesInPlace: Bool = false

    @Environment(\.catalogNavigationActions) private var catalogNavigation
    @EnvironmentObject private var focusCoordinator: KeyboardFocusCoordinator

    var body: some View {
        if hits.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            // Iterate indices instead of `Array(hits.enumerated())`
                            // — the previous form allocated a fresh array on every
                            // parent body pass (which is amplified by focus ticks
                            // because the button's `buttonStyle(.browsePressable)`
                            // reads `focusCoordinator.homeFocusActive`).
                            ForEach(hits.indices, id: \.self) { localIndex in
                                let hit = hits[localIndex]
                                let globalIndex = homeFocusRangeStart + localIndex
                                let focusID = HomeHubFocus.focusID(shelfKey: shelfKey, hit: hit)
                                Button {
                                    if !navigatesInPlace {
                                        onSelectServer?(plexServer.id)
                                        catalogNavigation.selectLibrary(hit.library)
                                    }
                                    catalogNavigation.pushRoute(HomeHubFocus.hubRoute(for: hit))
                                } label: {
                                    HubTileView(plexServer: plexServer, hit: hit)
                                }
                                .buttonStyle(
                                    .browsePressable(
                                        focused: focusCoordinator.homeFocusActive(forIndex: globalIndex),
                                        chrome: .catalogPoster
                                    )
                                )
#if os(tvOS)
                                .tvCatalogTileFocus()
#endif
                                .accessibilityLabel(hit.node.listTitle)
                                .id(focusID)
                            }
                        }
                        .padding(.vertical, 4)
#if os(tvOS)
                        .tvHubShelfFocus()
#endif
                    }
                    .onChange(of: focusCoordinator.homeFocusedIndex) { _, index in
                        scrollHomeFocus(to: index, proxy: proxy)
                    }
                }
            }
        }
    }

    /// Fast path: every shelf's `onChange(of: homeFocusedIndex)` fires on every
    /// focus tick. Bail as cheaply as possible when the focus belongs to a
    /// different shelf so the N-shelf fanout doesn't bog navigation down. Only
    /// the owning shelf reaches the `scrollTo` call.
    private func scrollHomeFocus(to index: Int, proxy: ScrollViewProxy) {
        guard focusCoordinator.route == .homeHubs else { return }
        let localIndex = index - homeFocusRangeStart
        guard localIndex >= 0, localIndex < hits.count else { return }
        let focusID = HomeHubFocus.focusID(shelfKey: shelfKey, hit: hits[localIndex])
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(focusID, anchor: .center)
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
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
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
