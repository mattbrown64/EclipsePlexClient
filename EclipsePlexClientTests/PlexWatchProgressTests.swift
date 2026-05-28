//  PlexWatchProgressTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PlexWatchProgressTests {
    @Test func fractionMidPlayback() {
        let f = PlexWatchProgress.fraction(viewOffsetMs: 600_000, durationMs: 1_200_000)
        #expect(f == 0.5)
    }

    @Test func fractionNilWhenNearEnd() {
        #expect(PlexWatchProgress.fraction(viewOffsetMs: 1_180_000, durationMs: 1_200_000) == nil)
    }

    @Test func fractionNilWhenNoDuration() {
        #expect(PlexWatchProgress.fraction(viewOffsetMs: 100, durationMs: nil) == nil)
        #expect(PlexWatchProgress.fraction(viewOffsetMs: nil, durationMs: 100) == nil)
    }

    @Test func fractionClampsToOne() {
        let f = PlexWatchProgress.fraction(viewOffsetMs: 900_000, durationMs: 1_000_000)
        #expect(f == 0.9)
    }
}
