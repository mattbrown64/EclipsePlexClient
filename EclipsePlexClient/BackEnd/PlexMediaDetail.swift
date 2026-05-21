//
//  PlexMediaDetail.swift
//  EclipsePlexClient
//

import Foundation

/// Rich metadata for a single Plex item (`/library/metadata/{ratingKey}`).
nonisolated struct PlexMediaDetail: Sendable {
    let ratingKey: String
    let title: String
    let summary: String?
    let year: Int?
    let thumbPath: String?
    let durationMs: Int?
    let viewOffsetMs: Int?
    let viewCount: Int?
    let contentRating: String?
    let studio: String?
    let rating: Double?
    let audienceRating: Double?
    let genres: [String]
    let directors: [String]
    let cast: [String]
    let markers: [PlexPlaybackMarker]
    let node: PlexCatalogNode?

    var isWatched: Bool {
        guard let viewCount, viewCount > 0 else { return false }
        guard let durationMs, durationMs > 0, let viewOffsetMs else { return viewCount > 0 }
        return viewOffsetMs >= durationMs - 30_000
    }

    var watchProgressFraction: Double? {
        guard let durationMs, durationMs > 0, let viewOffsetMs, viewOffsetMs > 0 else { return nil }
        return min(1, Double(viewOffsetMs) / Double(durationMs))
    }

    func replacing(markers newMarkers: [PlexPlaybackMarker]) -> PlexMediaDetail {
        PlexMediaDetail(
            ratingKey: ratingKey,
            title: title,
            summary: summary,
            year: year,
            thumbPath: thumbPath,
            durationMs: durationMs,
            viewOffsetMs: viewOffsetMs,
            viewCount: viewCount,
            contentRating: contentRating,
            studio: studio,
            rating: rating,
            audienceRating: audienceRating,
            genres: genres,
            directors: directors,
            cast: cast,
            markers: newMarkers,
            node: node
        )
    }
}
