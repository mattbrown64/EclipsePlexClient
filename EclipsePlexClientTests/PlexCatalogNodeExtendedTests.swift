//
//  PlexCatalogNodeExtendedTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PlexCatalogNodeExtendedTests {
    @Test func episodePlaybackRatingKey() {
        let ep = PlexEpisodeSummary(
            ratingKey: "ep1",
            parentRatingKey: "s1",
            showRatingKey: "show1",
            showTitle: "Show",
            seasonNumber: 1,
            episodeNumber: 3,
            title: "Pilot",
            summary: nil,
            durationSeconds: 3600,
            thumbPath: nil
        )
        #expect(PlexCatalogNode.episode(ep).playbackRatingKey == "ep1")
    }

    @Test func seasonHasNoPlaybackRatingKey() {
        let season = PlexSeasonSummary(
            ratingKey: "s1",
            parentRatingKey: "show1",
            showTitle: "Show",
            seasonNumber: 1,
            title: "Season 1",
            thumbPath: nil
        )
        #expect(PlexCatalogNode.season(season).playbackRatingKey == nil)
    }

    @Test func emptySearchQueryMatchesAll() {
        let movie = PlexMovieSummary(
            ratingKey: "1",
            title: "Z",
            year: nil,
            summary: nil,
            thumbPath: nil
        )
        #expect(PlexCatalogNode.movie(movie).matchesSearch(trimmedQuery: ""))
    }

    @Test func searchHitIDCombinesLibraryAndNode() {
        let lib = PlexSampleData.libraryPreview()
        let nodes = PlexSampleData.catalogNodes(for: lib, parent: .root)
        let hit = PlexCatalogSearchHit(library: lib, node: nodes[0])
        #expect(hit.id == "\(lib.id)|\(nodes[0].id)")
    }

    @Test func hubRouteForSeasonIsBrowse() {
        let serverId = PlexSampleData.serverHomeId
        let library = PlexSampleData.libraries(for: serverId).first { $0.sectionType == .show }!
        let showNode = PlexSampleData.catalogNodes(for: library, parent: .root).first!
        guard case .show(let show) = showNode else {
            Issue.record("Need show fixture")
            return
        }
        let seasons = PlexSampleData.catalogNodes(for: library, parent: .show(ratingKey: show.ratingKey))
        guard case .season(let season) = seasons.first else {
            Issue.record("Need season fixture")
            return
        }
        let hit = PlexCatalogSearchHit(library: library, node: .season(season))
        if case .browse(_, let parent, _) = HomeHubFocus.hubRoute(for: hit) {
            if case .season(let key) = parent {
                #expect(key == season.ratingKey)
            } else {
                Issue.record("Expected season parent")
            }
        } else {
            Issue.record("Expected browse route for season")
        }
    }
}
