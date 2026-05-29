//
//  PseudoTVModels.swift
//  EclipsePlexClient
//

import Foundation

/// How a channel selects items from the library index.
nonisolated enum PseudoTVGroupingKind: String, Codable, Sendable, CaseIterable {
    case librarySection
    case tvGenre
    case movieGenre
    case decade
    case network
}

/// TV-only, movies-only, or both on one channel.
nonisolated enum PseudoTVContentMode: String, Codable, Sendable {
    case tvOnly
    case moviesOnly
    case mixed
}

nonisolated struct PseudoTVProgramRef: Codable, Hashable, Sendable, Identifiable {
    let ratingKey: String
    let title: String
    let durationMs: Int
    let thumbPath: String?
    let showRatingKey: String?
    let addedAt: Int?

    var id: String { ratingKey }

    var durationSeconds: Int { max(1, durationMs / 1000) }
}

nonisolated struct PseudoTVChannel: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let serverId: UUID
    let name: String
    let groupingKind: PseudoTVGroupingKind
    let groupingKey: String
    let contentMode: PseudoTVContentMode
    var isHidden: Bool
    var cycleGeneration: Int

    static func makeID(serverId: UUID, kind: PseudoTVGroupingKind, key: String) -> String {
        "\(serverId.uuidString)|\(kind.rawValue)|\(key)"
    }
}

/// One airing in the weekly grid (offset from Monday 00:00 local).
nonisolated struct PseudoTVSlot: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let startOffsetSeconds: Int
    let durationSeconds: Int
    let program: PseudoTVProgramRef

    var endOffsetSeconds: Int { startOffsetSeconds + durationSeconds }
}

nonisolated struct PseudoTVScheduleSnapshot: Codable, Sendable {
    let channelId: String
    let weekAnchorUnix: Int
    let generatedAt: Date
    let cycleGeneration: Int
    /// Sum of one full rotation through the content pool (seconds).
    let cycleDurationSeconds: Int
    let slots: [PseudoTVSlot]
    let contentPoolFingerprint: String

    var weekLengthSeconds: Int { 7 * 86_400 }
}

/// Resolved tune-in for playback.
nonisolated struct PseudoTVTuneIn: Sendable {
    let channel: PseudoTVChannel
    let program: PseudoTVProgramRef
    let offsetMs: Int
    let slot: PseudoTVSlot
}

nonisolated struct PseudoTVNowPlayingInfo: Sendable {
    let current: PseudoTVSlot?
    let offsetMs: Int
    let upNext: PseudoTVSlot?
}
