//
//  PseudoTVProgramResolver.swift
//  EclipsePlexClient
//

import Foundation

/// Maps wall-clock time to weekly schedule slots and tune-in offsets.
enum PseudoTVProgramResolver {
    static let weekLengthSeconds = 7 * 86_400

    static func mondayWeekAnchor(containing date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: components) ?? cal.startOfDay(for: date)
    }

    static func secondsSinceWeekAnchor(_ date: Date, anchor: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: anchor)
        let t = date.timeIntervalSince(start)
        return max(0, Int(t) % weekLengthSeconds)
    }

    static func slot(
        at date: Date,
        snapshot: PseudoTVScheduleSnapshot,
        calendar: Calendar = .current
    ) -> (slot: PseudoTVSlot, offsetMs: Int)? {
        guard !snapshot.slots.isEmpty else { return nil }
        let anchor = Date(timeIntervalSince1970: TimeInterval(snapshot.weekAnchorUnix))
        let t = secondsSinceWeekAnchor(date, anchor: anchor, calendar: calendar)
        guard let hit = snapshot.slots.first(where: { s in
            let end = s.endOffsetSeconds
            if end <= weekLengthSeconds {
                return t >= s.startOffsetSeconds && t < end
            }
            return false
        }) else {
            return wrapSlot(at: t, slots: snapshot.slots)
        }
        let offsetSec = t - hit.startOffsetSeconds
        return (hit, max(0, offsetSec) * 1000)
    }

    private static func wrapSlot(at t: Int, slots: [PseudoTVSlot]) -> (slot: PseudoTVSlot, offsetMs: Int)? {
        let sorted = slots.sorted { $0.startOffsetSeconds < $1.startOffsetSeconds }
        guard let last = sorted.last else { return nil }
        let total = last.endOffsetSeconds
        guard total > 0 else { return nil }
        let wrapped = t % total
        guard let hit = sorted.first(where: { wrapped >= $0.startOffsetSeconds && wrapped < $0.endOffsetSeconds })
        else { return nil }
        return (hit, max(0, wrapped - hit.startOffsetSeconds) * 1000)
    }

    static func nowPlaying(
        at date: Date = Date(),
        snapshot: PseudoTVScheduleSnapshot,
        calendar: Calendar = .current
    ) -> PseudoTVNowPlayingInfo {
        guard let current = slot(at: date, snapshot: snapshot, calendar: calendar) else {
            return PseudoTVNowPlayingInfo(current: nil, offsetMs: 0, upNext: nil)
        }
        let sorted = snapshot.slots.sorted { $0.startOffsetSeconds < $1.startOffsetSeconds }
        let upNext = sorted.first { $0.startOffsetSeconds > current.slot.startOffsetSeconds } ?? sorted.first
        return PseudoTVNowPlayingInfo(current: current.slot, offsetMs: current.offsetMs, upNext: upNext)
    }

    static func cycleHasElapsed(snapshot: PseudoTVScheduleSnapshot, now: Date = Date()) -> Bool {
        let elapsed = now.timeIntervalSince(snapshot.generatedAt)
        return elapsed >= TimeInterval(snapshot.cycleDurationSeconds)
    }
}
