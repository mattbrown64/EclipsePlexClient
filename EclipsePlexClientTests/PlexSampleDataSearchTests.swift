//
//  PlexSampleDataSearchTests.swift
//  EclipsePlexClientTests
//

import Testing
@testable import EclipsePlexClient

struct PlexSampleDataSearchTests {
    @Test func flattenedHitsIncludeNestedTV() {
        let serverId = PlexSampleData.serverHomeId
        let hits = PlexSampleData.flattenedCatalogHits(forServerId: serverId)
        #expect(!hits.isEmpty)
        let hasEpisode = hits.contains { hit in
            if case .episode = hit.node { return true }
            return false
        }
        #expect(hasEpisode)
    }

    @Test func catalogSearchFiltersByTitle() {
        let serverId = PlexSampleData.serverHomeId
        let hits = PlexSampleData.catalogSearchHits(forServerId: serverId, query: "Midnight")
        #expect(!hits.isEmpty)
        #expect(hits.allSatisfy { $0.node.matchesSearch(trimmedQuery: "Midnight") })
    }

    @Test func catalogSearchEmptyQueryReturnsEmpty() {
        let hits = PlexSampleData.catalogSearchHits(forServerId: PlexSampleData.serverHomeId, query: "   ")
        #expect(hits.isEmpty)
    }

    @Test func catalogSearchMatchesLibraryName() {
        let serverId = PlexSampleData.serverHomeId
        let hits = PlexSampleData.catalogSearchHits(forServerId: serverId, query: "Feature Films")
        #expect(!hits.isEmpty)
    }
}

struct PlexCatalogNodeTests {
    @Test func matchesSearchInSubtitle() {
        let movie = PlexMovieSummary(
            ratingKey: "1",
            title: "Alpha",
            year: 2020,
            summary: nil,
            thumbPath: nil
        )
        let node = PlexCatalogNode.movie(movie)
        #expect(node.matchesSearch(trimmedQuery: "2020"))
        #expect(!node.matchesSearch(trimmedQuery: "Beta"))
    }

    @Test func showDoesNotSupportPlayback() {
        let show = PlexShowSummary(
            ratingKey: "s1",
            title: "Show",
            year: nil,
            summary: nil,
            thumbPath: nil
        )
        #expect(!PlexCatalogNode.show(show).supportsVideoPlayback)
    }

    @Test func movieSupportsPlayback() {
        let movie = PlexMovieSummary(
            ratingKey: "m1",
            title: "Film",
            year: nil,
            summary: nil,
            thumbPath: nil
        )
        #expect(PlexCatalogNode.movie(movie).supportsVideoPlayback)
    }
}
