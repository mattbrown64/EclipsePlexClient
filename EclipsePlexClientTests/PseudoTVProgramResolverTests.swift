//
//  PseudoTVProgramResolverTests.swift
//  EclipsePlexClientTests
//

import Foundation
import Testing
@testable import EclipsePlexClient

struct PseudoTVProgramResolverTests {
    @Test func resolvesSlotWithinWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = Date(timeIntervalSince1970: 0)
        let program = PseudoTVProgramRef(
            ratingKey: "1",
            title: "Test",
            durationMs: 3_600_000,
            thumbPath: nil,
            showRatingKey: nil,
            addedAt: nil
        )
        let slot = PseudoTVSlot(
            id: "s1",
            startOffsetSeconds: 3600,
            durationSeconds: 3600,
            program: program
        )
        let snapshot = PseudoTVScheduleSnapshot(
            channelId: "ch1",
            weekAnchorUnix: 0,
            generatedAt: Date(timeIntervalSince1970: 0),
            cycleGeneration: 1,
            cycleDurationSeconds: 7200,
            slots: [slot],
            contentPoolFingerprint: "fp"
        )
        let tuneDate = Date(timeIntervalSince1970: 5400)
        let hit = PseudoTVProgramResolver.slot(at: tuneDate, snapshot: snapshot, calendar: calendar)
        #expect(hit != nil)
        #expect(hit?.offsetMs == 1800_000)
    }

    @Test func cycleElapsedAfterDuration() {
        let snapshot = PseudoTVScheduleSnapshot(
            channelId: "ch1",
            weekAnchorUnix: 0,
            generatedAt: Date(timeIntervalSince1970: 0),
            cycleGeneration: 1,
            cycleDurationSeconds: 100,
            slots: [],
            contentPoolFingerprint: "fp"
        )
        let now = Date(timeIntervalSince1970: 200)
        #expect(PseudoTVProgramResolver.cycleHasElapsed(snapshot: snapshot, now: now))
    }
}
