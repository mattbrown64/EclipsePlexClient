//
//  PlaybackPreferencesTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PlaybackSubtitleSelectionTests {
    @Test func plexTranscodeValues() {
        #expect(PlaybackSubtitleSelection.off.plexTranscodeValue == "none")
        #expect(PlaybackSubtitleSelection.auto.plexTranscodeValue == "auto")
        #expect(
            PlaybackSubtitleSelection.plexStream(id: "5", displayName: "English")
                .plexTranscodeValue == "5"
        )
    }

    @Test func requiresTranscodeBurnInForPlexStream() {
        #expect(PlaybackSubtitleSelection.off.requiresTranscodeBurnIn == false)
        #expect(
            PlaybackSubtitleSelection.plexStream(id: "1", displayName: "EN").requiresTranscodeBurnIn
        )
    }
}

struct PlaybackSpeedTests {
    @Test func nearestSpeed() {
        #expect(PlaybackSpeed.nearest(to: 1.0) == .normal)
        #expect(PlaybackSpeed.nearest(to: 1.24) == .s125)
        #expect(PlaybackSpeed.nearest(to: 0.8) == .s075)
    }
}

struct PlaybackSubtitleCodableTests {
    @Test func subtitleSelectionCodableRoundTrip() throws {
        let original = PlaybackSubtitleSelection.plexStream(id: "3", displayName: "English")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlaybackSubtitleSelection.self, from: data)
        if case .plexStream(let id, let title) = decoded {
            #expect(id == "3")
            #expect(title == "English")
        } else {
            Issue.record("Expected plexStream after decode")
        }
    }
}
