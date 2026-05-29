//
//  PseudoTVLibraryIndexer.swift
//  EclipsePlexClient
//

import Foundation

/// Harvested catalog used to build auto channels.
struct PseudoTVLibraryIndex: Sendable {
    var movies: [IndexedMovie] = []
    var episodes: [IndexedEpisode] = []
    var recentEpisodeKeys: Set<String> = []
}

struct IndexedMovie: Sendable {
    let program: PseudoTVProgramRef
    let genres: [String]
    let year: Int?
    let libraryTitle: String
}

struct IndexedEpisode: Sendable {
    let program: PseudoTVProgramRef
    let showTitle: String
    let showRatingKey: String?
    let genres: [String]
    let network: String?
    let year: Int?
    let libraryTitle: String
}

enum PseudoTVLibraryIndexer {
    private static let maxShowsPerLibrary = 40
    private static let maxEpisodesPerShow = 80
    private static let maxMoviesPerLibrary = 200

    static func buildIndex(
        server: PlexServer,
        libraries: [PlexLibrary],
        client: PlexMediaServerClient
    ) async throws -> PseudoTVLibraryIndex {
        var index = PseudoTVLibraryIndex()
        let recentKeys = try await fetchRecentEpisodeKeys(client: client, libraries: libraries)
        index.recentEpisodeKeys = recentKeys

        for library in libraries {
            switch library.sectionType {
            case .movie:
                let movies = try await harvestMovies(library: library, client: client)
                index.movies.append(contentsOf: movies)
            case .show:
                let eps = try await harvestEpisodes(library: library, client: client)
                index.episodes.append(contentsOf: eps)
            default:
                continue
            }
        }
        return index
    }

    private static func fetchRecentEpisodeKeys(
        client: PlexMediaServerClient,
        libraries: [PlexLibrary]
    ) async throws -> Set<String> {
        let hits = try await client.fetchRecentlyAddedHits(libraries: libraries)
        return Set(hits.compactMap { hit -> String? in
            if case .episode(let e) = hit.node { return e.ratingKey }
            return nil
        })
    }

    private static func harvestMovies(
        library: PlexLibrary,
        client: PlexMediaServerClient
    ) async throws -> [IndexedMovie] {
        var results: [IndexedMovie] = []
        var offset = 0
        while results.count < maxMoviesPerLibrary {
            let page = try await client.fetchCatalogPage(
                library: library,
                parent: .root,
                offset: offset
            )
            for node in page.nodes {
                guard case .movie(let m) = node else { continue }
                let duration = m.durationMs ?? 7_200_000
                let program = PseudoTVProgramRef(
                    ratingKey: m.ratingKey,
                    title: m.title,
                    durationMs: duration,
                    thumbPath: m.thumbPath,
                    showRatingKey: nil,
                    addedAt: m.addedAt
                )
                results.append(IndexedMovie(
                    program: program,
                    genres: [],
                    year: m.year,
                    libraryTitle: library.title
                ))
                if results.count >= maxMoviesPerLibrary { break }
            }
            guard page.hasMore else { break }
            offset = page.nextOffset
        }
        return results
    }

    private static func harvestEpisodes(
        library: PlexLibrary,
        client: PlexMediaServerClient
    ) async throws -> [IndexedEpisode] {
        var results: [IndexedEpisode] = []
        let showsPage = try await client.fetchCatalogPage(library: library, parent: .root, offset: 0)
        let shows = showsPage.nodes.compactMap { node -> PlexShowSummary? in
            if case .show(let s) = node { return s }
            return nil
        }.prefix(maxShowsPerLibrary)

        for show in shows {
            var harvested = 0
            let seasonsPage = try await client.fetchCatalogPage(
                library: library,
                parent: .show(ratingKey: show.ratingKey),
                offset: 0
            )
            let seasons = seasonsPage.nodes.compactMap { node -> PlexSeasonSummary? in
                if case .season(let s) = node { return s }
                return nil
            }
            for season in seasons {
                var offset = 0
                while harvested < maxEpisodesPerShow {
                    let page = try await client.fetchCatalogPage(
                        library: library,
                        parent: .season(ratingKey: season.ratingKey),
                        offset: offset
                    )
                    for node in page.nodes {
                        guard case .episode(let e) = node else { continue }
                        let duration = e.durationMs ?? (e.durationSeconds.map { $0 * 1000 }) ?? 3_600_000
                        let program = PseudoTVProgramRef(
                            ratingKey: e.ratingKey,
                            title: "\(e.showTitle) · S\(e.seasonNumber)E\(e.episodeNumber)",
                            durationMs: duration,
                            thumbPath: e.thumbPath,
                            showRatingKey: e.showRatingKey,
                            addedAt: nil
                        )
                        results.append(IndexedEpisode(
                            program: program,
                            showTitle: e.showTitle,
                            showRatingKey: e.showRatingKey,
                            genres: [],
                            network: nil,
                            year: nil,
                            libraryTitle: library.title
                        ))
                        harvested += 1
                        if harvested >= maxEpisodesPerShow { break }
                    }
                    guard page.hasMore else { break }
                    offset = page.nextOffset
                }
                if harvested >= maxEpisodesPerShow { break }
            }
        }
        return results
    }
}
