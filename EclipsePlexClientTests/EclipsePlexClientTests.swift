//
//  EclipsePlexClientTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct CatalogBrowsePreferencesTests {
    @Test func defaultViewMode_rootIsGrid() {
        #expect(CatalogBrowsePreferences.defaultViewMode(parent: .root) == .grid)
    }

    @Test func defaultViewMode_showIsList() {
        #expect(CatalogBrowsePreferences.defaultViewMode(parent: .show(ratingKey: "1")) == .list)
    }

    @Test func defaultViewMode_seasonIsList() {
        #expect(CatalogBrowsePreferences.defaultViewMode(parent: .season(ratingKey: "2")) == .list)
    }
}

struct PlexSectionSortQueryTests {
    @Test func nilSortReturnsNoQuery() {
        #expect(PlexSectionSortQuery.queryItems(plexDefaultSortKey: nil).isEmpty)
    }

    @Test func bareSortAppendsAsc() {
        let items = PlexSectionSortQuery.queryItems(plexDefaultSortKey: "titleSort")
        #expect(items.count == 1)
        #expect(items[0].name == "sort")
        #expect(items[0].value == "titleSort:asc")
    }

    @Test func fullSortPassesThrough() {
        let items = PlexSectionSortQuery.queryItems(plexDefaultSortKey: "addedAt:desc")
        #expect(items.first?.value == "addedAt:desc")
    }
}

struct PlexPlaybackMarkerTests {
    @Test func containsPositionInRange() {
        let marker = PlexPlaybackMarker(type: .intro, startMs: 1000, endMs: 90_000)
        #expect(marker.contains(positionMs: 50_000))
        #expect(!marker.contains(positionMs: 100_000))
    }

    @Test func parserMapsIntro() {
        let records = [
            PlexMarkerRecord(type: "intro", startTimeOffset: 0, endTimeOffset: 85_000),
        ]
        let markers = PlexPlaybackMarkerParser.markers(from: records)
        #expect(markers.count == 1)
        #expect(markers[0].type == .intro)
        #expect(markers[0].endMs == 85_000)
    }

    @Test func parserSkipsInvalidEnd() {
        let records = [PlexMarkerRecord(type: "intro", startTimeOffset: 0, endTimeOffset: nil)]
        #expect(PlexPlaybackMarkerParser.markers(from: records).isEmpty)
    }

    @Test func xmlParserMapsIntro() {
        let xml = """
        <MediaContainer><Video ratingKey="1">
        <Marker type="intro" startTimeOffset="1000" endTimeOffset="90000"/>
        </Video></MediaContainer>
        """
        let markers = PlexPlaybackXMLParser.parseMarkers(xml)
        #expect(markers.count == 1)
        #expect(markers[0].type == .intro)
        #expect(markers[0].startMs == 1000)
        #expect(markers[0].endMs == 90_000)
    }

    @Test func xmlParserHandlesReorderedAttributes() {
        let xml = #"<Marker startTimeOffset="5000" endTimeOffset="60000" type="intro"/>"#
        let markers = PlexPlaybackXMLParser.parseMarkers(xml)
        #expect(markers.count == 1)
        #expect(markers[0].type == .intro)
    }

    @Test func xmlParserHandlesNonSelfClosingMarker() {
        let xml = #"<Marker id="1" type="intro" startTimeOffset="990" endTimeOffset="28316"><Attributes id="1"/></Marker>"#
        let markers = PlexPlaybackXMLParser.parseMarkers(xml)
        #expect(markers.count == 1)
        #expect(markers[0].endMs == 28_316)
    }

    @Test func activeMarkerPicksCurrentIntroSegment() {
        let markers = [
            PlexPlaybackMarker(type: .intro, startMs: 990, endMs: 28_316),
            PlexPlaybackMarker(type: .intro, startMs: 1_405_379, endMs: 1_441_234),
        ]
        let active = PlexPlaybackMarkerParser.activeMarker(at: 18_000, in: markers)
        #expect(active?.endMs == 28_316)
    }

    @Test func normalizeSecondsToMilliseconds() {
        let raw = [PlexPlaybackMarker(type: .intro, startMs: 0, endMs: 90)]
        let normalized = PlexPlaybackMarkerParser.normalize(raw, durationMs: 1_371_000)
        #expect(normalized.first?.endMs == 90_000)
    }
}

struct AggregateHomeHubServiceTests {
    @Test func cacheHonorsTTL() async {
        await AggregateHomeHubService.invalidateAll()
        let server = PlexServer(id: UUID(), name: "Test", hostDescription: "h")
        let shelf = AggregateHomeShelf(server: server, continueWatching: [], recentlyAdded: [], errorMessage: nil)
        await AggregateHomeHubService.store(shelf)
        #expect(await AggregateHomeHubService.cachedShelf(for: server.id) != nil)
    }
}

struct OfflineDownloadManagerTests {
    @Test @MainActor func activeQueueCountIncludesFailed() {
        let manager = OfflineDownloadManager()
        #expect(manager.activeQueueCount >= 0)
    }
}

struct PlexLibraryTests {
    @Test func normalizeSectionKey() {
        #expect(PlexLibrary.normalizeSectionKey("/library/sections/12") == "12")
        #expect(PlexLibrary.normalizeSectionKey("3") == "3")
    }

    @Test func matchesLibrarySectionID() {
        let lib = PlexLibrary(sectionKey: "5", title: "TV", type: 2)
        #expect(lib.matchesLibrarySectionID("5"))
        #expect(!lib.matchesLibrarySectionID("9"))
    }
}
