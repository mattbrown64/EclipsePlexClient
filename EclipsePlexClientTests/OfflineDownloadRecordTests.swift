//
//  OfflineDownloadRecordTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct OfflineDownloadRecordTests {
    @Test func inferLegacyEpisodeTitle() {
        let parsed = OfflineDownloadRecord.inferKindForMigration(title: "Breaking Bad · S2E4")
        #expect(parsed?.kind == .episode)
        #expect(parsed?.showTitle == "Breaking Bad")
        #expect(parsed?.season == 2)
        #expect(parsed?.episode == 4)
    }

    @Test func inferKindReturnsNilForPlainTitle() {
        #expect(OfflineDownloadRecord.inferKindForMigration(title: "Standalone Movie") == nil)
    }

    @Test func showGroupKeyUsesResolvedTitle() {
        let server = PlexServer(id: UUID(), name: "S", hostDescription: "h")
        let record = OfflineDownloadRecord.new(
            server: server,
            ratingKey: "1",
            title: "X · S1E1",
            thumbPath: nil,
            quality: .original,
            mediaKind: .episode,
            showTitle: "My Show"
        )
        #expect(record.showGroupKey.contains(server.id.uuidString))
        #expect(record.showGroupKey.lowercased().contains("my show"))
    }

    @Test func isPlayableRequiresCompletedPath() {
        let server = PlexServer(id: UUID(), name: "S", hostDescription: "h")
        var record = OfflineDownloadRecord.new(
            server: server,
            ratingKey: "1",
            title: "Film",
            thumbPath: nil,
            quality: .original
        )
        #expect(!record.isPlayable)
        record.state = OfflineDownloadRecord.State.completed
        record.relativeFilePath = "a.mp4"
        #expect(record.isPlayable)
    }

    @Test func displayTitlePrefersEpisodeTitle() {
        let server = PlexServer(id: UUID(), name: "S", hostDescription: "h")
        let record = OfflineDownloadRecord.new(
            server: server,
            ratingKey: "1",
            title: "Show · S1E2",
            thumbPath: nil,
            quality: .original,
            mediaKind: .episode,
            episodeTitle: "Pilot"
        )
        #expect(record.displayTitle == "Pilot")
    }
}
