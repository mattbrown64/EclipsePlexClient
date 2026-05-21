//
//  EpisodePlayContext.swift
//  EclipsePlexClient
//

import Foundation

/// TV binge context so playback can offer the next episode when one finishes.
nonisolated struct EpisodePlayContext: Hashable, Sendable {
    let serverId: UUID
    let librarySectionID: String
    let showRatingKey: String
}
