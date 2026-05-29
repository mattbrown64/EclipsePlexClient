//
//  PseudoTVWeeklyGridBuilder.swift
//  EclipsePlexClient
//

import Foundation

enum PseudoTVWeeklyGridBuilder {
    static func build(
        channel: PseudoTVChannel,
        programs: [PseudoTVProgramRef],
        cycleGeneration: Int,
        calendar: Calendar = .current
    ) -> PseudoTVScheduleSnapshot? {
        guard !programs.isEmpty else { return nil }
        let anchor = PseudoTVProgramResolver.mondayWeekAnchor(containing: Date(), calendar: calendar)
        let weekAnchorUnix = Int(anchor.timeIntervalSince1970)

        var pool = programs
        if channel.contentMode == .moviesOnly {
            pool.shuffle()
        }

        var slots: [PseudoTVSlot] = []
        var cursor = 0
        var slotIndex = 0
        let weekCap = PseudoTVProgramResolver.weekLengthSeconds
        var cycleDuration = 0

        while cursor < weekCap, slotIndex < pool.count * 3 {
            let program = pool[slotIndex % pool.count]
            let duration = min(program.durationSeconds, 4 * 3600)
            if cursor + duration > weekCap { break }
            let slot = PseudoTVSlot(
                id: "\(channel.id)-\(slotIndex)",
                startOffsetSeconds: cursor,
                durationSeconds: duration,
                program: program
            )
            slots.append(slot)
            cursor += duration
            cycleDuration += duration
            slotIndex += 1
        }

        if slots.isEmpty { return nil }

        let fingerprint = pool.map(\.ratingKey).joined(separator: "|")
        return PseudoTVScheduleSnapshot(
            channelId: channel.id,
            weekAnchorUnix: weekAnchorUnix,
            generatedAt: Date(),
            cycleGeneration: cycleGeneration,
            cycleDurationSeconds: max(cycleDuration, 3600),
            slots: slots,
            contentPoolFingerprint: String(fingerprint.hashValue)
        )
    }
}
