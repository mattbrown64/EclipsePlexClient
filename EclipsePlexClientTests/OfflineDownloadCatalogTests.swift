//
//  OfflineDownloadCatalogTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct OfflineDownloadCatalogTests {
    @Test func recordRatingKeyRoundTrip() {
        let id = UUID()
        let key = OfflineDownloadCatalog.catalogRatingKey(for: id)
        #expect(OfflineDownloadCatalog.recordID(fromCatalogRatingKey: key) == id)
    }

    @Test func showGroupKeyRoundTrip() {
        let group = "server|breaking bad"
        let key = OfflineDownloadCatalog.showCatalogRatingKey(groupKey: group)
        #expect(OfflineDownloadCatalog.showGroupKey(fromCatalogRatingKey: key) == group)
    }

    @Test func movieLibraryRootNodes() {
        let server = PlexServer.downloads
        let library = OfflineDownloadsLibrary.libraries(for: server.id).first { OfflineDownloadsLibrary.isMovies($0) }!
        let record = OfflineDownloadRecord.new(
            server: server,
            ratingKey: "999",
            title: "Offline Film",
            thumbPath: nil,
            quality: .original,
            mediaKind: .movie
        )
        var completed = record
        completed.state = .completed
        completed.relativeFilePath = "film.mkv"
        let nodes = OfflineDownloadCatalog.nodes(
            records: [completed],
            library: library,
            parent: .root
        )
        #expect(nodes.count == 1)
        if case .movie(let m) = nodes[0] {
            #expect(m.title == "Offline Film")
        } else {
            Issue.record("Expected movie node")
        }
    }

    @Test func tvLibraryGroupsShows() {
        let server = PlexServer.downloads
        let library = OfflineDownloadsLibrary.libraries(for: server.id).first { OfflineDownloadsLibrary.isTV($0) }!
        let ep = OfflineDownloadRecord.new(
            server: server,
            ratingKey: "ep1",
            title: "Show · S1E1",
            thumbPath: nil,
            quality: .p720,
            mediaKind: .episode,
            showTitle: "Show",
            seasonNumber: 1,
            episodeNumber: 1
        )
        var completed = ep
        completed.state = .completed
        completed.relativeFilePath = "ep.mp4"
        let rootNodes = OfflineDownloadCatalog.nodes(records: [completed], library: library, parent: .root)
        #expect(rootNodes.count == 1)
        if case .show = rootNodes[0] {
            #expect(Bool(true))
        } else {
            Issue.record("Expected show grouping")
        }
    }
}
