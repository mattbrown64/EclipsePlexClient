//
//  PlexServer+Downloads.swift
//  EclipsePlexClient
//

import Foundation

extension PlexServer {
    /// Stable id for the virtual “Downloads” server (not persisted in `PlexServerRegistry`).
    static let downloadsServerID = UUID(uuidString: "E1C1E5E0-D0EE-4000-8000-000000000001")!

    /// Virtual server that aggregates offline files from every real Plex server.
    static var downloads: PlexServer {
        PlexServer(
            id: downloadsServerID,
            name: "Downloads",
            hostDescription: "Downloads on this device"
        )
    }

    var isDownloadsServer: Bool {
        id == Self.downloadsServerID
    }
}

enum OfflineDownloadsLibrary {
    static let moviesSectionKey = "offline-movies"
    static let tvSectionKey = "offline-tv"

    static func libraries(for downloadsServerID: UUID) -> [PlexLibrary] {
        [
            PlexLibrary(
                serverId: downloadsServerID,
                sectionKey: moviesSectionKey,
                title: "Movies",
                type: PlexSectionType.movie.rawValue
            ),
            PlexLibrary(
                serverId: downloadsServerID,
                sectionKey: tvSectionKey,
                title: "TV Shows",
                type: PlexSectionType.show.rawValue
            ),
        ]
    }

    static func isMovies(_ library: PlexLibrary) -> Bool {
        library.sectionKey == moviesSectionKey
    }

    static func isTV(_ library: PlexLibrary) -> Bool {
        library.sectionKey == tvSectionKey
    }
}
