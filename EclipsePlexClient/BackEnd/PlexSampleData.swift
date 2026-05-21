//
//  PlexSampleData.swift
//  EclipsePlexClient
//
//  Sample `PlexServer` / `PlexLibrary` values for SwiftUI previews and UI until networking exists.
//

import Foundation

/// Offline fixtures: `PlexSampleData.servers`, `PlexSampleData.libraries(for:)`.
///
/// Server IDs are fixed UUIDs so `@AppStorage` and selection state stay stable across launches.
nonisolated enum PlexSampleData {
    static let serverHomeId = UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!
    static let serverRemoteId = UUID(uuidString: "A1000000-0000-4000-8000-000000000002")!
    static let serverFriendId = UUID(uuidString: "A1000000-0000-4000-8000-000000000003")!

    static let servers: [PlexServer] = [
        PlexServer(id: serverHomeId, name: "Home", hostDescription: "192.168.1.10:32400"),
        PlexServer(id: serverRemoteId, name: "Remote", hostDescription: "https://plex.example.com"),
        PlexServer(id: serverFriendId, name: "Friend's share", hostDescription: "Shared — invite only"),
    ]

    /// Mimics `/library/sections` for one server; swaps in real API results later.
    /// Library titles differ per server so switching servers is obvious in the UI.
    static func libraries(for serverId: UUID) -> [PlexLibrary] {
        switch serverId {
        case serverHomeId:
            return [
                PlexLibrary(serverId: serverId, sectionKey: "1", title: "Feature Films", type: 1, thumbPath: "/:/resources/movie.png", uuid: "home-1"),
                PlexLibrary(serverId: serverId, sectionKey: "2", title: "Series Recordings", type: 2, thumbPath: "/:/resources/show.png", uuid: "home-2"),
                PlexLibrary(serverId: serverId, sectionKey: "3", title: "Home Music", type: 8, uuid: "home-3"),
            ]
        case serverRemoteId:
            return [
                PlexLibrary(serverId: serverId, sectionKey: "1", title: "Cloud Movies", type: 1, thumbPath: "/:/resources/movie.png", uuid: "remote-1"),
                PlexLibrary(serverId: serverId, sectionKey: "2", title: "Remote DVR", type: 2, thumbPath: "/:/resources/show.png", uuid: "remote-2"),
                PlexLibrary(serverId: serverId, sectionKey: "3", title: "Streaming Mix", type: 8, uuid: "remote-3"),
            ]
        case serverFriendId:
            return [
                PlexLibrary(serverId: serverId, sectionKey: "1", title: "Shared Cinema", type: 1, thumbPath: "/:/resources/movie.png", uuid: "friend-1"),
                PlexLibrary(serverId: serverId, sectionKey: "2", title: "Buddy's TV", type: 2, thumbPath: "/:/resources/show.png", uuid: "friend-2"),
                PlexLibrary(serverId: serverId, sectionKey: "3", title: "Party Playlist", type: 8, uuid: "friend-3"),
            ]
        default:
            return [
                PlexLibrary(serverId: serverId, sectionKey: "1", title: "Movies", type: 1, uuid: "fallback-1"),
                PlexLibrary(serverId: serverId, sectionKey: "2", title: "TV Shows", type: 2, uuid: "fallback-2"),
                PlexLibrary(serverId: serverId, sectionKey: "3", title: "Music", type: 8, uuid: "fallback-3"),
            ]
        }
    }

    /// One-off row for canvas tests.
    static func libraryPreview(
        serverId: UUID = serverHomeId,
        sectionKey: String = "1",
        title: String = "Movies",
        type: Int = 1
    ) -> PlexLibrary {
        PlexLibrary(
            serverId: serverId,
            sectionKey: sectionKey,
            title: title,
            type: type,
            thumbPath: nil,
            compositePath: nil,
            uuid: "preview-library",
            agent: nil,
            scanner: nil,
            language: nil
        )
    }

    // MARK: - Catalog fixtures (replace with API mapping later)

    /// Items for the current library level: root rows, seasons under a show, or episodes under a season.
    static func catalogNodes(for library: PlexLibrary, parent: PlexCatalogParent) -> [PlexCatalogNode] {
        switch parent {
        case .root:
            switch library.sectionType {
            case .movie, .photo: return movieNodes(for: library)
            case .show: return showNodes(for: library)
            case .music: return musicNodes(for: library)
            case .other: return movieNodes(for: library)
            }
        case .show(let showKey):
            return seasonNodes(for: library, showRatingKey: showKey)
        case .season(let seasonKey):
            return episodeNodes(for: library, seasonRatingKey: seasonKey)
        case .collection, .playlist:
            return []
        case .collection, .playlist:
            return []
        }
    }

    /// All fixture catalog nodes on this server, across every library and TV depth — for cross-library search until a real `/search` API exists.
    static func flattenedCatalogHits(forServerId serverId: UUID) -> [PlexCatalogSearchHit] {
        var out: [PlexCatalogSearchHit] = []
        for lib in libraries(for: serverId) {
            collectCatalogSearchHits(library: lib, parent: .root, into: &out)
        }
        return out
    }

    /// Filter flattened hits by query (title, subtitle, and library name).
    static func catalogSearchHits(forServerId serverId: UUID, query: String) -> [PlexCatalogSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let needle = q.lowercased()
        return flattenedCatalogHits(forServerId: serverId).filter { hit in
            if hit.library.title.lowercased().contains(needle) { return true }
            return hit.node.matchesSearch(trimmedQuery: q)
        }
    }

    private static func collectCatalogSearchHits(
        library: PlexLibrary,
        parent: PlexCatalogParent,
        into out: inout [PlexCatalogSearchHit]
    ) {
        for node in catalogNodes(for: library, parent: parent) {
            out.append(PlexCatalogSearchHit(library: library, node: node))
            switch node {
            case .show(let s):
                collectCatalogSearchHits(library: library, parent: .show(ratingKey: s.ratingKey), into: &out)
            case .season(let se):
                collectCatalogSearchHits(library: library, parent: .season(ratingKey: se.ratingKey), into: &out)
            default:
                break
            }
        }
    }

    private static func movieNodes(for library: PlexLibrary) -> [PlexCatalogNode] {
        let b = library.id
        return [
            .movie(PlexMovieSummary(
                ratingKey: "\(b):movie-1",
                title: "Fixture: Midnight in \(library.title)",
                year: 2021,
                summary: "Offline placeholder copy for a movie in this library.",
                thumbPath: "/library/metadata/50101/thumb/320"
            )),
            .movie(PlexMovieSummary(
                ratingKey: "\(b):movie-2",
                title: "Fixture: The \(library.title) Heist",
                year: 2024,
                summary: "Another placeholder movie row.",
                thumbPath: "/library/metadata/50102/thumb/320"
            )),
            .movie(PlexMovieSummary(
                ratingKey: "\(b):movie-3",
                title: "Fixture: Return to \(shortHostLabel(for: library))",
                year: 2018,
                summary: "Third fixture so lists scroll in previews.",
                thumbPath: "/library/metadata/50103/thumb/320"
            )),
        ]
    }

    private static func showNodes(for library: PlexLibrary) -> [PlexCatalogNode] {
        let b = library.id
        let a = PlexShowSummary(
            ratingKey: "\(b):show-a",
            title: "\(library.title): Westridge",
            year: 2019,
            summary: "Fixture TV series with seasons and episodes.",
            thumbPath: "/library/metadata/50201/thumb/320"
        )
        let s = PlexShowSummary(
            ratingKey: "\(b):show-b",
            title: "\(library.title): Night Shift",
            year: 2022,
            summary: "Second fixture show in this library.",
            thumbPath: "/library/metadata/50202/thumb/320"
        )
        return [.show(a), .show(s)]
    }

    private static func seasonNodes(for library: PlexLibrary, showRatingKey: String) -> [PlexCatalogNode] {
        let showTitle = showFixtureTitle(showRatingKey: showRatingKey, library: library)
        let isA = showRatingKey.hasSuffix(":show-a")
        let m1 = isA ? 50311 : 50321
        let m2 = isA ? 50312 : 50322
        let s1 = PlexSeasonSummary(
            ratingKey: "\(showRatingKey):season-1",
            parentRatingKey: showRatingKey,
            showTitle: showTitle,
            seasonNumber: 1,
            title: "Season 1",
            thumbPath: "/library/metadata/\(m1)/thumb/320"
        )
        let s2 = PlexSeasonSummary(
            ratingKey: "\(showRatingKey):season-2",
            parentRatingKey: showRatingKey,
            showTitle: showTitle,
            seasonNumber: 2,
            title: "Season 2",
            thumbPath: "/library/metadata/\(m2)/thumb/320"
        )
        return [.season(s1), .season(s2)]
    }

    private static func episodeNodes(for library: PlexLibrary, seasonRatingKey: String) -> [PlexCatalogNode] {
        guard let (showKey, seasonNumber) = splitSeasonRatingKey(seasonRatingKey) else { return [] }
        let showTitle = showFixtureTitle(showRatingKey: showKey, library: library)
        let base = seasonRatingKey
        let isA = showKey.hasSuffix(":show-a")
        let epBase = isA ? 50410 : 50420
        let meta1 = epBase + seasonNumber * 10 + 1
        let meta2 = epBase + seasonNumber * 10 + 2
        return [
            .episode(PlexEpisodeSummary(
                ratingKey: "\(base):ep-1",
                parentRatingKey: seasonRatingKey,
                showRatingKey: showKey,
                showTitle: showTitle,
                seasonNumber: seasonNumber,
                episodeNumber: 1,
                title: "Pilot (fixture)",
                summary: "Placeholder episode synopsis.",
                durationSeconds: 2_634,
                thumbPath: "/library/metadata/\(meta1)/thumb/320"
            )),
            .episode(PlexEpisodeSummary(
                ratingKey: "\(base):ep-2",
                parentRatingKey: seasonRatingKey,
                showRatingKey: showKey,
                showTitle: showTitle,
                seasonNumber: seasonNumber,
                episodeNumber: 2,
                title: "Second chair (fixture)",
                summary: "Another offline episode row.",
                durationSeconds: 2_412,
                thumbPath: "/library/metadata/\(meta2)/thumb/320"
            )),
        ]
    }

    private static func musicNodes(for library: PlexLibrary) -> [PlexCatalogNode] {
        let b = library.id
        return [
            .musicTrack(PlexMusicTrackSummary(
                ratingKey: "\(b):track-1",
                title: "Fixture: Opening theme",
                album: library.title,
                artist: "Offline Artist",
                thumbPath: "/library/metadata/50501/thumb/320"
            )),
            .musicTrack(PlexMusicTrackSummary(
                ratingKey: "\(b):track-2",
                title: "Fixture: B-side wander",
                album: library.title,
                artist: "Offline Artist",
                thumbPath: "/library/metadata/50502/thumb/320"
            )),
        ]
    }

    private static func showFixtureTitle(showRatingKey: String, library: PlexLibrary) -> String {
        if showRatingKey.hasSuffix(":show-a") { return "\(library.title): Westridge" }
        if showRatingKey.hasSuffix(":show-b") { return "\(library.title): Night Shift" }
        return library.title
    }

    private static func splitSeasonRatingKey(_ seasonRatingKey: String) -> (showRatingKey: String, seasonNumber: Int)? {
        guard let range = seasonRatingKey.range(of: ":season-", options: .backwards) else { return nil }
        let showKey = String(seasonRatingKey[..<range.lowerBound])
        let tail = seasonRatingKey[range.upperBound...]
        guard let num = Int(tail) else { return nil }
        return (showKey, num)
    }

    private static func shortHostLabel(for library: PlexLibrary) -> String {
        guard let sid = library.serverId,
              let server = servers.first(where: { $0.id == sid }) else { return "Server" }
        return server.name
    }
}
