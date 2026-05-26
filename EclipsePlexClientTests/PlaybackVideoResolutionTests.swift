//
//  PlaybackVideoResolutionTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PlaybackVideoResolutionTests {
    @Test func transcodeQualitiesForceTranscode() {
        #expect(PlaybackVideoResolution.p1080.forcesTranscode)
        #expect(PlaybackVideoResolution.p720.forcesTranscode)
        #expect(PlaybackVideoResolution.p480.forcesTranscode)
        #expect(!PlaybackVideoResolution.original.forcesTranscode)
    }

    @Test func plexVideoResolutionStrings() {
        #expect(PlaybackVideoResolution.p1080.plexVideoResolution == "1920x1080")
        #expect(PlaybackVideoResolution.p720.plexVideoResolution == "1280x720")
        #expect(PlaybackVideoResolution.p480.plexVideoResolution == "854x480")
        #expect(PlaybackVideoResolution.original.plexVideoResolution == "1280x720")
    }

    @Test func menuTitlesAreHumanReadable() {
        #expect(PlaybackVideoResolution.original.menuTitle == "Original")
        #expect(PlaybackVideoResolution.p1080.menuTitle == "1080p")
    }

    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(PlaybackVideoResolution.p720)
        let decoded = try JSONDecoder().decode(PlaybackVideoResolution.self, from: data)
        #expect(decoded == .p720)
    }
}
