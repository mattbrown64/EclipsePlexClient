//
//  PlexCatalog.swift
//  EclipsePlexClient
//

import Foundation

// MARK: - Summary structs (per-kind fields; maps from Plex API later)
//
// `thumbPath` holds server-relative Plex art URLs (e.g. `Video.thumb`, `Directory.thumb`).
// Resolve with `PlexServer.catalogArtworkURL(relativeThumbPath:)`.

nonisolated struct PlexMovieSummary: Identifiable, Hashable, Sendable {
    let ratingKey: String
    let title: String
    let year: Int?
    let summary: String?
    let thumbPath: String?

    var id: String { ratingKey }
}

nonisolated struct PlexShowSummary: Identifiable, Hashable, Sendable {
    let ratingKey: String
    let title: String
    let year: Int?
    let summary: String?
    let thumbPath: String?

    var id: String { ratingKey }
}

nonisolated struct PlexSeasonSummary: Identifiable, Hashable, Sendable {
    let ratingKey: String
    let parentRatingKey: String
    let showTitle: String
    let seasonNumber: Int
    /// Display title, e.g. "Season 3"
    let title: String
    let thumbPath: String?

    var id: String { ratingKey }
}

nonisolated struct PlexEpisodeSummary: Identifiable, Hashable, Sendable {
    let ratingKey: String
    let parentRatingKey: String
    let showTitle: String
    let seasonNumber: Int
    let episodeNumber: Int
    let title: String
    let summary: String?
    let durationSeconds: Int?
    let thumbPath: String?

    var id: String { ratingKey }
}

nonisolated struct PlexMusicTrackSummary: Identifiable, Hashable, Sendable {
    let ratingKey: String
    let title: String
    let album: String?
    let artist: String?
    let thumbPath: String?

    var id: String { ratingKey }
}

// MARK: - Unified list row + navigation

nonisolated enum PlexCatalogNode: Identifiable, Hashable, Sendable {
    case movie(PlexMovieSummary)
    case show(PlexShowSummary)
    case season(PlexSeasonSummary)
    case episode(PlexEpisodeSummary)
    case musicTrack(PlexMusicTrackSummary)

    var id: String {
        switch self {
        case .movie(let m): return "movie:\(m.ratingKey)"
        case .show(let s): return "show:\(s.ratingKey)"
        case .season(let s): return "season:\(s.ratingKey)"
        case .episode(let e): return "episode:\(e.ratingKey)"
        case .musicTrack(let t): return "track:\(t.ratingKey)"
        }
    }

    var listTitle: String {
        switch self {
        case .movie(let m): return m.title
        case .show(let s): return s.title
        case .season(let s): return s.title
        case .episode(let e): return e.title
        case .musicTrack(let t): return t.title
        }
    }

    var listSubtitle: String? {
        switch self {
        case .movie(let m):
            return m.year.map { String($0) }
        case .show(let s):
            return s.year.map { String($0) } ?? "TV Show"
        case .season(let s):
            return "\(s.showTitle) · Season \(s.seasonNumber)"
        case .episode(let e):
            return "S\(e.seasonNumber) E\(e.episodeNumber)"
        case .musicTrack(let t):
            let parts = [t.artist, t.album].compactMap { $0 }
            return parts.isEmpty ? "Music" : parts.joined(separator: " · ")
        }
    }

    var listThumbPath: String? {
        switch self {
        case .movie(let m): return m.thumbPath
        case .show(let s): return s.thumbPath
        case .season(let s): return s.thumbPath
        case .episode(let e): return e.thumbPath
        case .musicTrack(let t): return t.thumbPath
        }
    }

    /// Case-insensitive match on `listTitle` and `listSubtitle` (for local / fixture search).
    func matchesSearch(trimmedQuery: String) -> Bool {
        let q = trimmedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let needle = q.lowercased()
        if listTitle.lowercased().contains(needle) { return true }
        if let sub = listSubtitle, sub.lowercased().contains(needle) { return true }
        return false
    }
}

/// One row in a server-wide catalog search (which `PlexLibrary` the item belongs to).
nonisolated struct PlexCatalogSearchHit: Identifiable, Hashable, Sendable {
    let library: PlexLibrary
    let node: PlexCatalogNode

    var id: String { "\(library.id)|\(node.id)" }
}

/// Which level of the catalog tree we are listing (fixtures + future API use the same idea).
nonisolated enum PlexCatalogParent: Hashable, Sendable {
    case root
    case show(ratingKey: String)
    case season(ratingKey: String)
}
