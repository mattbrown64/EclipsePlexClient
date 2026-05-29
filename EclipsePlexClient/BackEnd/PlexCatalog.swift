//
//  PlexCatalog.swift
//  EclipsePlexClient
//

import Foundation

// MARK: - Summary structs

nonisolated struct PlexMovieSummary: Identifiable, Hashable, Sendable {
    let ratingKey: String
    let title: String
    let year: Int?
    let summary: String?
    let thumbPath: String?
    var libraryOrder: Int = 0
    var addedAt: Int?
    var originallyAvailableAt: Int?
    var viewOffsetMs: Int?
    var durationMs: Int?
    var viewCount: Int?

    var id: String { ratingKey }

    var watchProgressFraction: Double? {
        PlexWatchProgress.fraction(viewOffsetMs: viewOffsetMs, durationMs: durationMs)
    }

    var isWatched: Bool {
        (viewCount ?? 0) > 0 && watchProgressFraction == nil
    }
}

nonisolated struct PlexPlaylistSummary: Identifiable, Hashable, Sendable {
    let ratingKey: String
    let title: String
    let summary: String?
    let thumbPath: String?
    var libraryOrder: Int = 0

    var id: String { ratingKey }
}

nonisolated struct PlexCollectionSummary: Identifiable, Hashable, Sendable {
    let ratingKey: String
    let title: String
    let summary: String?
    let thumbPath: String?
    var libraryOrder: Int = 0

    var id: String { ratingKey }
}

nonisolated struct PlexShowSummary: Identifiable, Hashable, Sendable {
    let ratingKey: String
    let title: String
    let year: Int?
    let summary: String?
    let thumbPath: String?
    var libraryOrder: Int = 0
    var addedAt: Int?
    var originallyAvailableAt: Int?

    var id: String { ratingKey }
}

nonisolated enum PlexWatchProgress {
    nonisolated static func fraction(viewOffsetMs: Int?, durationMs: Int?) -> Double? {
        guard let durationMs, durationMs > 0, let viewOffsetMs, viewOffsetMs > 0 else { return nil }
        if viewOffsetMs >= durationMs - 30_000 { return nil }
        return min(1, Double(viewOffsetMs) / Double(durationMs))
    }
}

nonisolated struct PlexSeasonSummary: Identifiable, Hashable, Sendable {
    let ratingKey: String
    let parentRatingKey: String
    let showTitle: String
    let seasonNumber: Int
    let title: String
    let thumbPath: String?
    var libraryOrder: Int = 0

    var id: String { ratingKey }
}

nonisolated struct PlexEpisodeSummary: Identifiable, Hashable, Sendable {
    let ratingKey: String
    let parentRatingKey: String
    let showRatingKey: String?
    let showTitle: String
    let seasonNumber: Int
    let episodeNumber: Int
    let title: String
    let summary: String?
    let durationSeconds: Int?
    let thumbPath: String?
    var showThumbPath: String?
    var libraryOrder: Int = 0
    var viewOffsetMs: Int?
    var durationMs: Int?
    var viewCount: Int?

    var id: String { ratingKey }

    var watchProgressFraction: Double? {
        PlexWatchProgress.fraction(viewOffsetMs: viewOffsetMs, durationMs: durationMs)
    }
}

nonisolated struct PlexPhotoSummary: Identifiable, Hashable, Sendable {
    let ratingKey: String
    let title: String
    let thumbPath: String?
    var libraryOrder: Int = 0
    var addedAt: Int?

    var id: String { ratingKey }
}

nonisolated struct PlexMusicTrackSummary: Identifiable, Hashable, Sendable {
    let ratingKey: String
    let title: String
    let album: String?
    let artist: String?
    let thumbPath: String?
    var libraryOrder: Int = 0

    var id: String { ratingKey }
}

// MARK: - Unified list row + navigation

nonisolated enum PlexCatalogNode: Identifiable, Hashable, Sendable {
    case movie(PlexMovieSummary)
    case show(PlexShowSummary)
    case season(PlexSeasonSummary)
    case episode(PlexEpisodeSummary)
    case musicTrack(PlexMusicTrackSummary)
    case photo(PlexPhotoSummary)

    var id: String {
        switch self {
        case .movie(let m): return "movie:\(m.ratingKey)"
        case .show(let s): return "show:\(s.ratingKey)"
        case .season(let s): return "season:\(s.ratingKey)"
        case .episode(let e): return "episode:\(e.ratingKey)"
        case .musicTrack(let t): return "track:\(t.ratingKey)"
        case .photo(let p): return "photo:\(p.ratingKey)"
        }
    }

    var libraryOrder: Int {
        switch self {
        case .movie(let m): return m.libraryOrder
        case .show(let s): return s.libraryOrder
        case .season(let s): return s.libraryOrder
        case .episode(let e): return e.libraryOrder
        case .musicTrack(let t): return t.libraryOrder
        case .photo(let p): return p.libraryOrder
        }
    }

    var listTitle: String {
        switch self {
        case .movie(let m): return m.title
        case .show(let s): return s.title
        case .season(let s): return s.title
        case .episode(let e): return e.title
        case .musicTrack(let t): return t.title
        case .photo(let p): return p.title
        }
    }

    var listSubtitle: String? {
        switch self {
        case .movie(let m): return m.year.map { String($0) }
        case .show(let s): return s.year.map { String($0) } ?? "TV Show"
        case .season(let s): return "\(s.showTitle) · Season \(s.seasonNumber)"
        case .episode(let e):
            let seasonEpisode = "S\(e.seasonNumber) E\(e.episodeNumber)"
            if e.showTitle.isEmpty { return seasonEpisode }
            return "\(e.showTitle) · \(seasonEpisode)"
        case .musicTrack(let t):
            let parts = [t.artist, t.album].compactMap { $0 }
            return parts.isEmpty ? "Music" : parts.joined(separator: " · ")
        case .photo: return "Photo"
        }
    }

    var listThumbPath: String? {
        switch self {
        case .movie(let m): return m.thumbPath
        case .show(let s): return s.thumbPath
        case .season(let s): return s.thumbPath
        case .episode(let e): return e.thumbPath
        case .musicTrack(let t): return t.thumbPath
        case .photo(let p): return p.thumbPath
        }
    }

    var listYear: Int? {
        switch self {
        case .movie(let m): return m.year
        case .show(let s): return s.year
        case .season, .episode, .musicTrack, .photo: return nil
        }
    }

    var listAddedAt: Int? {
        switch self {
        case .movie(let m): return m.addedAt
        case .show(let s): return s.addedAt
        case .photo(let p): return p.addedAt
        default: return nil
        }
    }

    var listOriginallyAvailableAt: Int? {
        switch self {
        case .movie(let m): return m.originallyAvailableAt
        case .show(let s): return s.originallyAvailableAt
        default: return nil
        }
    }

    var listSeasonEpisodeOrder: (season: Int, episode: Int)? {
        switch self {
        case .season(let s): return (s.seasonNumber, 0)
        case .episode(let e): return (e.seasonNumber, e.episodeNumber)
        default: return nil
        }
    }

    var playbackRatingKey: String? {
        switch self {
        case .movie(let m): return m.ratingKey
        case .episode(let e): return e.ratingKey
        case .musicTrack(let t): return t.ratingKey
        case .show, .season, .photo: return nil
        }
    }

    var watchProgressFraction: Double? {
        switch self {
        case .movie(let m): return m.watchProgressFraction
        case .episode(let e): return e.watchProgressFraction
        case .show, .season, .musicTrack, .photo: return nil
        }
    }

    var supportsVideoPlayback: Bool {
        playbackRatingKey != nil
    }

    var galleryAccessibilityLabel: String {
        if let subtitle = listSubtitle {
            return "\(listTitle), \(subtitle)"
        }
        return listTitle
    }

    func matchesSearch(trimmedQuery: String) -> Bool {
        let q = trimmedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let needle = q.lowercased()
        if listTitle.lowercased().contains(needle) { return true }
        if let sub = listSubtitle, sub.lowercased().contains(needle) { return true }
        return false
    }
}

nonisolated struct PlexCatalogSearchHit: Identifiable, Hashable, Sendable {
    let library: PlexLibrary
    let node: PlexCatalogNode

    var id: String { "\(library.id)|\(node.id)" }
}

nonisolated enum PlexCatalogParent: Hashable, Sendable {
    case root
    case show(ratingKey: String)
    case season(ratingKey: String)
    case collection(ratingKey: String)
    case playlist(ratingKey: String)
}

nonisolated enum CatalogNavigationRoute: Hashable, Sendable {
    case browse(library: PlexLibrary, parent: PlexCatalogParent, navigationTitle: String)
    case showDetail(library: PlexLibrary, show: PlexShowSummary)
    case media(library: PlexLibrary, node: PlexCatalogNode)
    case serverPlaylists
    case playlistItems(playlistKey: String, title: String)
    case libraryCollections(library: PlexLibrary)
    case collectionItems(collectionKey: String, title: String, library: PlexLibrary)
    case liveTV
    case pseudoTV
}

nonisolated struct CatalogPageResult: Sendable {
    let nodes: [PlexCatalogNode]
    let totalSize: Int?
    let nextOffset: Int
    var hasMore: Bool
}

nonisolated enum CatalogWatchFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case unwatched
    case watched
    case inProgress

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .all: "All items"
        case .unwatched: "Unwatched"
        case .watched: "Watched"
        case .inProgress: "In progress"
        }
    }

    var shortTitle: String {
        switch self {
        case .all: "All"
        case .unwatched: "Unwatched"
        case .watched: "Watched"
        case .inProgress: "In progress"
        }
    }

    var plexQueryItems: [URLQueryItem] {
        switch self {
        case .all, .watched, .inProgress: return []
        case .unwatched: return [URLQueryItem(name: "unwatched", value: "1")]
        }
    }

    var filtersClientSideByViewCount: Bool {
        self == .watched
    }

    var filtersClientSideInProgress: Bool {
        self == .inProgress
    }
}

nonisolated struct CatalogListFilters: Hashable, Sendable {
    var genreFilterKey: String?
    var year: Int?

    var isActive: Bool {
        genreFilterKey != nil || year != nil
    }

    var plexQueryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let genreFilterKey, !genreFilterKey.isEmpty {
            items.append(URLQueryItem(name: "genre", value: genreFilterKey))
        }
        if let year {
            items.append(URLQueryItem(name: "year", value: String(year)))
        }
        return items
    }
}

nonisolated struct PlexLibraryGenre: Identifiable, Hashable, Sendable {
    let filterKey: String
    let title: String

    var id: String { filterKey }
}
