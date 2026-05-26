//
//  HomeHubFocusTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct HomeHubFocusTests {
    @Test func focusIDIsStable() {
        let serverId = PlexSampleData.serverHomeId
        let library = PlexSampleData.libraries(for: serverId).first!
        let nodes = PlexSampleData.catalogNodes(for: library, parent: .root)
        guard case .movie(let movie) = nodes.first else {
            Issue.record("Expected movie fixture")
            return
        }
        let hit = PlexCatalogSearchHit(library: library, node: .movie(movie))
        let id = HomeHubFocus.focusID(shelfKey: "cw", hit: hit)
        #expect(id.hasPrefix("home|cw|"))
        #expect(id.contains(hit.id))
    }

    @Test func hubRouteForMovieIsMedia() {
        let serverId = PlexSampleData.serverHomeId
        let library = PlexSampleData.libraries(for: serverId).first!
        let movie = PlexSampleData.catalogNodes(for: library, parent: .root).first!
        let hit = PlexCatalogSearchHit(library: library, node: movie)
        let route = HomeHubFocus.hubRoute(for: hit)
        if case .media = route {
            #expect(Bool(true))
        } else {
            Issue.record("Expected .media route for movie hit")
        }
    }

    @Test func hubRouteForShowIsShowDetail() {
        let serverId = PlexSampleData.serverHomeId
        let library = PlexSampleData.libraries(for: serverId).first { $0.sectionType == .show }!
        let showNode = PlexSampleData.catalogNodes(for: library, parent: .root).first!
        guard case .show(let show) = showNode else {
            Issue.record("Expected show fixture")
            return
        }
        let hit = PlexCatalogSearchHit(library: library, node: .show(show))
        if case .showDetail(_, let routedShow) = HomeHubFocus.hubRoute(for: hit) {
            #expect(routedShow.ratingKey == show.ratingKey)
        } else {
            Issue.record("Expected .showDetail")
        }
    }
}
